import 'dart:developer' as dev;
import '../../core/constants/api_constants.dart';
import '../../core/utils/date_time_formatter.dart';
import '../database/weather_monitoring_dao.dart';
import '../models/weather_current_model.dart';
import '../models/weather_daily_summary.dart';
import '../models/weather_monitoring_record.dart';
import '../models/weather_point.dart';
import '../network/weather_api_service.dart';
import '../storage/latest_weather_file_storage.dart';
import 'weather_repository.dart';

/// Triển khai WeatherRepository kết nối dữ liệu thực từ Backend Gateway:
/// - Bản ghi mới nhất (Latest) lưu vào FILE cục bộ trên app (không lưu database)
/// - Dữ liệu chuỗi 24h lưu vào bảng SQLite `weather_inday` (tự động xóa bản ghi quá 24h)
/// - Dữ liệu chuỗi 7d lưu vào bảng SQLite `weather_week` (tự động xóa bản ghi quá 7 ngày)
class AppWeatherRepository implements WeatherRepository {
  final WeatherApiService apiService;
  final WeatherMonitoringDao dao;
  final LatestWeatherFileStorage fileStorage;
  final String currentDeviceId;
  final String stationTimezone;

  AppWeatherRepository({
    required this.apiService,
    required this.dao,
    LatestWeatherFileStorage? fileStorage,
    this.currentDeviceId = ApiConstants.defaultStationId,
    this.stationTimezone = ApiConstants.defaultStationTimezone,
  }) : fileStorage = fileStorage ?? LatestWeatherFileStorage();

  @override
  Future<WeatherCurrentModel> getCurrentWeather() async {
    try {
      final response = await apiService.fetchLatestWeather(currentDeviceId);
      final data = response.data;

      if (data != null) {
        final record = WeatherMonitoringRecord.fromJson(
          data,
          defaultDeviceId: currentDeviceId,
        );

        if (record.deviceId != currentDeviceId) {
          throw StateError(
            'Mismatched station response: expected $currentDeviceId, got ${record.deviceId}',
          );
        }

        final current = WeatherCurrentModel(
          stationId: record.deviceId,
          stationName: ApiConstants.deviceStationMap[record.deviceId] ??
              ApiConstants.defaultStationName,
          timestamp: record.recordedAt,
          temperature: record.temperature,
          humidity: record.humidity,
          rainfall: record.rainfall,
          windSpeed: record.windSpeed,
          isOnline: true,
        );

        // Lưu bản ghi mới nhất vào FILE cục bộ trên app theo đúng stationId
        await fileStorage.saveLatest(current);

        return current;
      }
    } catch (e) {
      dev.log('Lỗi fetchLatestWeather từ API, đọc từ file cache: $e');
    }

    // Fallback: Đọc bản ghi mới nhất từ file cache theo đúng currentDeviceId khi mất mạng
    final cachedLatest = await fileStorage.readLatest(deviceId: currentDeviceId);
    if (cachedLatest != null && cachedLatest.stationId == currentDeviceId) {
      return cachedLatest.copyWith(
        stationName: ApiConstants.deviceStationMap[cachedLatest.stationId] ??
            cachedLatest.stationName,
        isOnline: false,
      );
    }

    // Trường hợp chưa từng có dữ liệu
    return WeatherCurrentModel(
      stationId: currentDeviceId,
      stationName: ApiConstants.deviceStationMap[currentDeviceId] ??
          ApiConstants.defaultStationName,
      timestamp: DateTime.now(),
      temperature: 0.0,
      humidity: 0.0,
      rainfall: 0.0,
      windSpeed: 0.0,
      isOnline: false,
    );
  }

  static String? computeOverlapSince(String? cursorIso, Duration overlap) {
    if (cursorIso == null || cursorIso.isEmpty) return null;
    final parsed = DateTime.tryParse(cursorIso);
    if (parsed == null) return cursorIso;
    return parsed.toUtc().subtract(overlap).toIso8601String();
  }

  static Duration? _fixedTimezoneOffset(String timezone) {
    switch (timezone) {
      case 'UTC':
      case 'Etc/UTC':
      case 'GMT':
        return Duration.zero;
      case 'Asia/Ho_Chi_Minh':
      case 'Asia/Bangkok':
      case 'Asia/Jakarta':
        return const Duration(hours: 7);
      case 'Asia/Kolkata':
        return const Duration(hours: 5, minutes: 30);
      case 'Asia/Tokyo':
      case 'Asia/Seoul':
        return const Duration(hours: 9);
      default:
        return null;
    }
  }

  /// Convert an instant to station wall-clock DateTime (year/month/day/hour/minute in station timezone).
  static DateTime toStationWallClock(DateTime dt, String stationTimezone) {
    final offset = _fixedTimezoneOffset(stationTimezone);
    if (offset == null) return dt.toLocal();
    final shifted = dt.toUtc().add(offset);
    return DateTime(
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
      shifted.minute,
      shifted.second,
      shifted.millisecond,
      shifted.microsecond,
    );
  }

  String? _latestRecordCursorIso(List<WeatherMonitoringRecord> records) {
    if (records.isEmpty) return null;
    DateTime latest = records.first.recordedAt.toUtc();
    for (final record in records.skip(1)) {
      final candidate = record.recordedAt.toUtc();
      if (candidate.isAfter(latest)) {
        latest = candidate;
      }
    }
    // Keep cursor at exact bucket boundary so open/updated current bucket is re-fetched and upserted idempotently.
    return latest.toIso8601String();
  }

  @override
  Future<List<WeatherPoint>> getIntraDayData() async {
    // Mốc thời gian hiện tại theo múi giờ của trạm
    final stationNow = toStationWallClock(DateTime.now(), stationTimezone);

    try {
      final cursorKey = WeatherMonitoringDao.buildCursorSeriesKey(
        range: '24h',
        resolution: '600s',
        timezone: stationTimezone,
      );
      final cursorIso = await dao.getSyncCursor(
        deviceId: currentDeviceId,
        series: cursorKey,
      );
      final since = computeOverlapSince(cursorIso, const Duration(hours: 1));
      final response = await apiService.fetchHistory(
        deviceId: currentDeviceId,
        range: '24h',
        since: since,
        timezone: stationTimezone,
      );

      final rawList = response.data['data'] as List<dynamic>? ?? [];
      final records = rawList
          .map((item) => WeatherMonitoringRecord.fromJson(
                item as Map<String, dynamic>,
                defaultDeviceId: currentDeviceId,
              ))
          .toList();

      // Lưu vào bảng weather_inday, cập nhật sync_cursors và dọn dẹp bản ghi quá 24h atomically
      await dao.saveIndayHistoryAndCleanup(
        records,
        deviceId: currentDeviceId,
        syncCursorIso: _latestRecordCursorIso(records),
        cursorSeriesKey: cursorKey,
      );
    } catch (e) {
      dev.log('Lỗi fetchHistory 24h, đọc từ bảng weather_inday: $e');
    }

    // Đọc từ SQLite bảng weather_inday các điểm đo từ 00:00 sáng hôm nay theo giờ trạm
    final all = await dao.getIndayRecords(deviceId: currentDeviceId);
    final todayRecords = all.where((r) {
      final d = toStationWallClock(r.recordedAt, stationTimezone);
      return d.year == stationNow.year &&
             d.month == stationNow.month &&
             d.day == stationNow.day;
    }).toList();
    todayRecords.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    return todayRecords.map((r) => r.toWeatherPoint()).toList();
  }

  @override
  Future<List<WeatherDailySummary>> get7DaysSummary() async {
    try {
      final cursorKey = WeatherMonitoringDao.buildCursorSeriesKey(
        range: '7d',
        resolution: '3600s',
        timezone: stationTimezone,
      );
      final cursorIso = await dao.getSyncCursor(
        deviceId: currentDeviceId,
        series: cursorKey,
      );
      final since = computeOverlapSince(cursorIso, const Duration(hours: 6));
      final response = await apiService.fetchHistory(
        deviceId: currentDeviceId,
        range: '7d',
        since: since,
        timezone: stationTimezone,
      );

      final rawList = response.data['data'] as List<dynamic>? ?? [];
      final records = rawList
          .map((item) => WeatherMonitoringRecord.fromJson(
                item as Map<String, dynamic>,
                defaultDeviceId: currentDeviceId,
              ))
          .toList();

      // Lưu vào bảng weather_week, cập nhật sync_cursors & dọn dẹp bản ghi quá 7 ngày atomically
      await dao.saveWeekHistoryAndCleanup(
        records,
        deviceId: currentDeviceId,
        syncCursorIso: _latestRecordCursorIso(records),
        cursorSeriesKey: cursorKey,
      );
    } catch (e) {
      dev.log('Lỗi fetchHistory 7d từ mạng, sử dụng dữ liệu bảng weather_week: $e');
    }

    // Đọc toàn bộ các bản ghi trong 7 ngày gần nhất từ bảng weather_week
    final localRecords = await dao.getWeekHistory7Days(deviceId: currentDeviceId);

    // Xây dựng danh sách chuẩn xác đủ 7 ngày liên tiếp từ (now - 6 ngày) đến hôm nay theo giờ trạm
    return buildContinuous7DaysSummary(
      localRecords,
      stationTimezone: stationTimezone,
    );
  }

  /// Gom nhóm số đo và tạo đủ 7 ngày liên tiếp tính đến ngày hiện tại
  /// Những ngày không có dữ liệu được đánh dấu hasData: false (None)
  static List<WeatherDailySummary> buildContinuous7DaysSummary(
    List<WeatherMonitoringRecord> records, {
    DateTime? referenceDate,
    String stationTimezone = ApiConstants.defaultStationTimezone,
  }) {
    final now = referenceDate ?? toStationWallClock(DateTime.now(), stationTimezone);
    final today = DateTime(now.year, now.month, now.day);

    // 1. Gom nhóm các bản ghi theo ngày dạng 'YYYY-MM-DD' theo múi giờ trạm
    final Map<String, List<WeatherMonitoringRecord>> groupedByDay = {};
    for (final r in records) {
      final local = toStationWallClock(r.recordedAt, stationTimezone);
      final key =
          '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
      groupedByDay.putIfAbsent(key, () => []).add(r);
    }

    // 2. Tạo đúng 7 ngày liên tiếp từ (today - 6 days) đến today
    final List<WeatherDailySummary> result = [];
    for (int i = 6; i >= 0; i--) {
      final targetDate = today.subtract(Duration(days: i));
      final dateKey =
          '${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';
      final shortLabel = DateTimeFormatter.formatShortDate(targetDate); // dd/MM

      final dayRecords = groupedByDay[dateKey];

      if (dayRecords != null && dayRecords.isNotEmpty) {
        double sumTemp = 0, minTemp = double.infinity, maxTemp = -double.infinity;
        double sumHumi = 0, sumRain = 0, sumWind = 0;
        bool hasAnyRainfallMm = false;
        bool allObserved = true;

        for (final r in dayRecords) {
          sumTemp += r.temperature;
          final lowTemp = r.tempMin ?? r.temperature;
          final highTemp = r.tempMax ?? r.temperature;
          if (lowTemp < minTemp) minTemp = lowTemp;
          if (highTemp > maxTemp) maxTemp = highTemp;
          sumHumi += r.humidity;
          if (r.rainfallMm != null) {
            sumRain += r.rainfallMm!;
            hasAnyRainfallMm = true;
            if (r.rainQuality != 'observed') {
              allObserved = false;
            }
          }
          sumWind += r.windSpeed;
        }

        final count = dayRecords.length;
        result.add(
          WeatherDailySummary(
            date: targetDate,
            dayOfWeek: shortLabel,
            avgTemperature: double.parse((sumTemp / count).toStringAsFixed(1)),
            minTemperature:
                double.parse((minTemp.isFinite ? minTemp : 0.0).toStringAsFixed(1)),
            maxTemperature:
                double.parse((maxTemp.isFinite ? maxTemp : 0.0).toStringAsFixed(1)),
            avgHumidity: double.parse((sumHumi / count).toStringAsFixed(1)),
            totalRainfall:
                hasAnyRainfallMm ? double.parse(sumRain.toStringAsFixed(1)) : 0.0,
            hasRainfallAmount: hasAnyRainfallMm,
            rainQuality: !hasAnyRainfallMm
                ? 'unknown'
                : (allObserved ? 'observed' : 'estimated'),
            avgWindSpeed: double.parse((sumWind / count).toStringAsFixed(1)),
            hasData: true,
          ),
        );
      } else {
        // Ngày không có dữ liệu đo -> None
        result.add(
          WeatherDailySummary.empty(
            date: targetDate,
            dayLabel: shortLabel,
          ),
        );
      }
    }

    return result;
  }

  @override
  Future<void> refreshAllData() async {
    // Làm mới tuần tự
    await getCurrentWeather();
    await getIntraDayData();
    await get7DaysSummary();
  }
}

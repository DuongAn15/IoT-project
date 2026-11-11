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

  AppWeatherRepository({
    required this.apiService,
    required this.dao,
    LatestWeatherFileStorage? fileStorage,
    this.currentDeviceId = ApiConstants.defaultStationId,
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

        // Lưu bản ghi mới nhất vào FILE cục bộ trên app (thay vì lưu database)
        await fileStorage.saveLatest(current);

        return current;
      }
    } catch (e) {
      dev.log('Lỗi fetchLatestWeather từ API, đọc từ file cache: $e');
    }

    // Fallback: Đọc bản ghi mới nhất từ file cache khi mất mạng
    final cachedLatest = await fileStorage.readLatest();
    if (cachedLatest != null) {
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

  @override
  Future<List<WeatherPoint>> getIntraDayData() async {
    // Mốc thời gian hiện tại theo giờ thiết bị (Local Time)
    final now = DateTime.now();

    try {
      final response = await apiService.fetchHistory(
        deviceId: currentDeviceId,
        range: '24h',
      );

      final rawList = response.data['data'] as List<dynamic>? ?? [];
      final records = rawList
          .map((item) => WeatherMonitoringRecord.fromJson(
                item as Map<String, dynamic>,
                defaultDeviceId: currentDeviceId,
              ))
          .toList();

      if (records.isNotEmpty) {
        // Lưu vào bảng weather_inday và dọn dẹp các bản ghi quá 24h
        await dao.saveIndayHistoryAndCleanup(records);

        // Chỉ lọc các điểm từ 00:00 sáng hôm nay đến hiện tại cho biểu đồ trong ngày
        final todayRecords = records.where((r) {
          final d = r.recordedAt;
          return d.year == now.year &&
                 d.month == now.month &&
                 d.day == now.day;
        }).toList();
        todayRecords.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

        return todayRecords.map((r) => r.toWeatherPoint()).toList();
      }
    } catch (e) {
      dev.log('Lỗi fetchHistory 24h, đọc từ bảng weather_inday: $e');
    }

    // Đọc từ SQLite bảng weather_inday các điểm đo từ 00:00 sáng hôm nay
    final all = await dao.getIndayRecords(deviceId: currentDeviceId);
    final todayRecords = all.where((r) {
      final d = r.recordedAt;
      return d.year == now.year &&
             d.month == now.month &&
             d.day == now.day;
    }).toList();
    todayRecords.sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    return todayRecords.map((r) => r.toWeatherPoint()).toList();
  }

  @override
  Future<List<WeatherDailySummary>> get7DaysSummary() async {
    try {
      final response = await apiService.fetchHistory(
        deviceId: currentDeviceId,
        range: '7d',
      );

      final rawList = response.data['data'] as List<dynamic>? ?? [];
      final records = rawList
          .map((item) => WeatherMonitoringRecord.fromJson(
                item as Map<String, dynamic>,
                defaultDeviceId: currentDeviceId,
              ))
          .toList();

      // Lưu vào bảng weather_week & tự động dọn dẹp các bản ghi quá 7 ngày
      await dao.saveWeekHistoryAndCleanup(records);
    } catch (e) {
      dev.log('Lỗi fetchHistory 7d từ mạng, sử dụng dữ liệu bảng weather_week: $e');
    }

    // Đọc toàn bộ các bản ghi trong 7 ngày gần nhất từ bảng weather_week
    final localRecords = await dao.getWeekHistory7Days(deviceId: currentDeviceId);

    // Xây dựng danh sách chuẩn xác đủ 7 ngày liên tiếp từ (now - 6 ngày) đến hôm nay
    return buildContinuous7DaysSummary(localRecords);
  }

  /// Gom nhóm số đo và tạo đủ 7 ngày liên tiếp tính đến ngày hiện tại
  /// Những ngày không có dữ liệu được đánh dấu hasData: false (None)
  static List<WeatherDailySummary> buildContinuous7DaysSummary(
    List<WeatherMonitoringRecord> records, {
    DateTime? referenceDate,
  }) {
    final now = referenceDate ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 1. Gom nhóm các bản ghi theo ngày dạng 'YYYY-MM-DD'
    final Map<String, List<WeatherMonitoringRecord>> groupedByDay = {};
    for (final r in records) {
      final local = r.recordedAt;
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

        for (final r in dayRecords) {
          sumTemp += r.temperature;
          if (r.temperature < minTemp) minTemp = r.temperature;
          if (r.temperature > maxTemp) maxTemp = r.temperature;
          sumHumi += r.humidity;
          sumRain += r.rainfall;
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
            totalRainfall: double.parse(sumRain.toStringAsFixed(1)),
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

import 'dart:developer' as dev;
import '../../core/constants/api_constants.dart';
import '../../core/utils/date_time_formatter.dart';
import '../database/weather_monitoring_dao.dart';
import '../models/weather_current_model.dart';
import '../models/weather_daily_summary.dart';
import '../models/weather_monitoring_record.dart';
import '../models/weather_point_5m.dart';
import '../network/weather_api_service.dart';
import 'weather_repository.dart';

/// Triển khai WeatherRepository kết nối dữ liệu thực từ Backend Gateway và lưu cache SQLite 7 ngày
class AppWeatherRepository implements WeatherRepository {
  final WeatherApiService apiService;
  final WeatherMonitoringDao dao;
  final String currentDeviceId;

  AppWeatherRepository({
    required this.apiService,
    required this.dao,
    this.currentDeviceId = ApiConstants.defaultStationId,
  });

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

        // Lưu bản ghi mới nhất vào SQLite
        await dao.insertRecord(record);

        return WeatherCurrentModel(
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
      }
    } catch (e) {
      dev.log('Lỗi fetchLatestWeather từ API, chuyển sang SQLite: $e');
    }

    // Fallback: Đọc bản ghi mới nhất từ SQLite khi mất mạng
    final localLatest = await dao.getLatestRecord(deviceId: currentDeviceId);
    if (localLatest != null) {
      return WeatherCurrentModel(
        stationId: localLatest.deviceId,
        stationName: ApiConstants.deviceStationMap[localLatest.deviceId] ??
            ApiConstants.defaultStationName,
        timestamp: localLatest.recordedAt,
        temperature: localLatest.temperature,
        humidity: localLatest.humidity,
        rainfall: localLatest.rainfall,
        windSpeed: localLatest.windSpeed,
        isOnline: false,
      );
    }

    // Trường hợp rỗng hoàn toàn
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
  Future<List<WeatherPoint5m>> getIntraDayData5m() async {
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
        // Lưu cache vào SQLite
        await dao.insertBatch(records);
        return records.map((r) => r.toWeatherPoint5m()).toList();
      }
    } catch (e) {
      dev.log('Lỗi fetchHistory 24h, đọc từ SQLite: $e');
    }

    // Đọc từ SQLite các điểm trong 24 giờ qua
    final cutoff = DateTime.now()
        .subtract(const Duration(hours: 24))
        .millisecondsSinceEpoch;
    final all = await dao.getAllRecords(deviceId: currentDeviceId);
    final in24h = all.where((r) => r.timestamp >= cutoff).toList();
    in24h.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return in24h.map((r) => r.toWeatherPoint5m()).toList();
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

      // Lưu vào SQLite & tự động dọn dẹp các bản ghi quá 7 ngày
      await dao.saveHistoryAndCleanup(records);
    } catch (e) {
      dev.log('Lỗi fetchHistory 7d từ mạng, sử dụng dữ liệu SQLite: $e');
    }

    // Đọc toàn bộ các bản ghi trong 7 ngày gần nhất từ SQLite
    final localRecords = await dao.getHistory7Days(deviceId: currentDeviceId);

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
    await getIntraDayData5m();
    await get7DaysSummary();
  }
}

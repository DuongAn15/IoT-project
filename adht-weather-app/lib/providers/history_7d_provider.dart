import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/weather_unit_helper.dart';

/// Provider lưu trữ tab chỉ số đang được chọn trên màn hình 7 Ngày
final history7dSelectedMetricProvider =
    StateProvider<WeatherMetricType>((ref) => WeatherMetricType.temperature);

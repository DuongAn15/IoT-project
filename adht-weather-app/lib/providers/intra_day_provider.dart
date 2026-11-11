import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/weather_unit_helper.dart';

/// Provider lưu trữ tab chỉ số đang được chọn trên màn hình Trong Ngày (Intra-day)
final intraDaySelectedMetricProvider =
    StateProvider<WeatherMetricType>((ref) => WeatherMetricType.temperature);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/weather_unit_helper.dart';

/// Bước thời gian lấy mẫu cho màn hình Diễn Biến Trong Ngày
enum IntraDayInterval {
  m15(15, '15 phút'),
  m30(30, '30 phút'),
  h1(60, '1 tiếng');

  final int minutes;
  final String label;
  const IntraDayInterval(this.minutes, this.label);
}

/// Provider lưu trữ tab chỉ số đang được chọn trên màn hình Trong Ngày (Intra-day)
final intraDaySelectedMetricProvider =
    StateProvider<WeatherMetricType>((ref) => WeatherMetricType.temperature);

/// Provider lưu trữ bước thời gian đang được chọn (mặc định 15 phút)
final intraDayIntervalProvider =
    StateProvider<IntraDayInterval>((ref) => IntraDayInterval.m15);


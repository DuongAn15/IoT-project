import 'package:intl/intl.dart';

/// Tiện ích chuyển đổi và định dạng thời gian chuẩn tiếng Việt
abstract class DateTimeFormatter {
  static final DateFormat _timeFormat = DateFormat('HH:mm');
  static final DateFormat _timeWithSecFormat = DateFormat('HH:mm:ss');
  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  static final DateFormat _shortDateFormat = DateFormat('dd/MM');

  /// Định dạng giờ phút (ví dụ: "14:25")
  static String formatTime(DateTime dateTime) {
    return _timeFormat.format(dateTime);
  }

  /// Định dạng giờ phút giây
  static String formatTimeWithSeconds(DateTime dateTime) {
    return _timeWithSecFormat.format(dateTime);
  }

  /// Định dạng ngày tháng năm ("04/11/2026")
  static String formatDate(DateTime dateTime) {
    return _dateFormat.format(dateTime);
  }

  /// Định dạng ngày tháng ngắn ("04/11")
  static String formatShortDate(DateTime dateTime) {
    return _shortDateFormat.format(dateTime);
  }

  /// Tên thứ trong tuần rút gọn tiếng Việt ("T2", "T3",..., "CN", "Hôm nay")
  static String getDayOfWeekLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);

    if (target.isAtSameMomentAs(today)) {
      return 'Hôm nay';
    }

    switch (date.weekday) {
      case DateTime.monday:
        return 'T2';
      case DateTime.tuesday:
        return 'T3';
      case DateTime.wednesday:
        return 'T4';
      case DateTime.thursday:
        return 'T5';
      case DateTime.friday:
        return 'T6';
      case DateTime.saturday:
        return 'T7';
      case DateTime.sunday:
        return 'CN';
      default:
        return '';
    }
  }

  /// Tên thứ đầy đủ ("Thứ Hai", "Hôm nay",...)
  static String getDayOfWeekFull(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);

    if (target.isAtSameMomentAs(today)) {
      return 'Hôm nay';
    }

    switch (date.weekday) {
      case DateTime.monday:
        return 'Thứ Hai';
      case DateTime.tuesday:
        return 'Thứ Ba';
      case DateTime.wednesday:
        return 'Thứ Tư';
      case DateTime.thursday:
        return 'Thứ Năm';
      case DateTime.friday:
        return 'Thứ Sáu';
      case DateTime.saturday:
        return 'Thứ Bảy';
      case DateTime.sunday:
        return 'Chủ Nhật';
      default:
        return '';
    }
  }

  /// Chuyển đổi số phút tính từ 00:00 thành chuỗi HH:mm
  static String minutesToTime(int totalMinutes) {
    final hour = (totalMinutes ~/ 60).clamp(0, 23);
    final minute = (totalMinutes % 60).clamp(0, 59);
    final hStr = hour.toString().padLeft(2, '0');
    final mStr = minute.toString().padLeft(2, '0');
    return '$hStr:$mStr';
  }

  /// Nhãn hiển thị cập nhật ("Cập nhật: 14:25 hôm nay")
  static String formatLastUpdated(DateTime dateTime) {
    final timeStr = formatTime(dateTime);
    final dayStr = getDayOfWeekLabel(dateTime).toLowerCase();
    return 'Cập nhật: $timeStr $dayStr';
  }
}

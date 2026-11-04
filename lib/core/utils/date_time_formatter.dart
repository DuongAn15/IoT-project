import 'package:intl/intl.dart';

/// Tiện ích chuyển đổi và định dạng thời gian chuẩn tiếng Việt
abstract class DateTimeFormatter {
  static final DateFormat _timeFormat = DateFormat('HH:mm');
  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  static final DateFormat _shortDateFormat = DateFormat('dd/MM');

  /// Định dạng giờ phút (ví dụ: "14:25")
  static String formatTime(DateTime dateTime) {
    return _timeFormat.format(dateTime);
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

  /// Chuyển đổi số phút tính từ 00:00 thành chuỗi HH:mm
  static String minutesToTime(int totalMinutes) {
    final hour = (totalMinutes ~/ 60).clamp(0, 23);
    final minute = (totalMinutes % 60).clamp(0, 59);
    final hStr = hour.toString().padLeft(2, '0');
    final mStr = minute.toString().padLeft(2, '0');
    return '$hStr:$mStr';
  }

  /// Chuyển đổi số phút tính từ 00:00 thành nhãn giờ rút gọn cho biểu đồ (ví dụ: 0 -> "0h", 180 -> "3h")
  static String minutesToHourLabel(int totalMinutes) {
    final hour = (totalMinutes ~/ 60).clamp(0, 23);
    return '${hour}h';
  }

  /// Nhãn hiển thị cập nhật ("Cập nhật: 14:25 04/11")
  static String formatLastUpdated(DateTime dateTime) {
    final timeStr = formatTime(dateTime);
    final dateStr = formatShortDate(dateTime);
    return 'Cập nhật: $timeStr $dateStr';
  }
}

import 'package:intl/intl.dart';

/// Tiện ích chuyển đổi và định dạng thời gian chuẩn tiếng Việt
abstract class DateTimeFormatter {
  static final DateFormat _timeFormat = DateFormat('HH:mm');
  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  static final DateFormat _shortDateFormat = DateFormat('dd/MM');

  /// Độ lệch múi giờ Việt Nam (UTC+7 / GMT+7)
  static const Duration vietnamTimezoneOffset = Duration(hours: 7);

  /// Thời điểm hiện tại theo giờ Việt Nam GMT+7
  static DateTime currentGmt7Time() {
    return DateTime.now().toUtc().add(vietnamTimezoneOffset);
  }

  /// Chuyển đổi một giá trị thời gian UTC (GMT+0) từ backend sang DateTime GMT+7 (giờ Việt Nam)
  static DateTime parseUtcToGmt7(dynamic rawTime) {
    if (rawTime == null) return currentGmt7Time();
    if (rawTime is DateTime) {
      final utc = rawTime.isUtc ? rawTime : rawTime.toUtc();
      return utc.add(vietnamTimezoneOffset);
    }
    if (rawTime is int) {
      final utc = DateTime.fromMillisecondsSinceEpoch(rawTime, isUtc: true);
      return utc.add(vietnamTimezoneOffset);
    }

    String timeStr = rawTime.toString().trim();
    if (timeStr.isEmpty) return currentGmt7Time();

    // Chuẩn hóa định dạng: Thay khoảng trắng bằng 'T'
    timeStr = timeStr.replaceFirst(' ', 'T');

    // Nếu chưa có đuôi múi giờ (Z hoặc offset), ép hiểu là UTC (GMT+0)
    final hasTimezone = timeStr.endsWith('Z') ||
        RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(timeStr);
    if (!hasTimezone) {
      timeStr = '${timeStr}Z';
    }

    try {
      final utc = DateTime.parse(timeStr).toUtc();
      return utc.add(vietnamTimezoneOffset);
    } catch (_) {
      return currentGmt7Time();
    }
  }

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

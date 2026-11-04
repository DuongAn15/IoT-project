import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/utils/date_time_formatter.dart';

/// Banner cảnh báo nhẹ khi đang xem dữ liệu offline từ bộ nhớ đệm
class OfflineIndicator extends StatelessWidget {
  final DateTime lastSavedTime;

  const OfflineIndicator({
    super.key,
    required this.lastSavedTime,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppDimensions.spaceMd),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spaceMd,
        vertical: AppDimensions.spaceSm,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3B2D0A) : const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(
          color: isDark ? const Color(0xFF78350F) : const Color(0xFFFDE68A),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            size: AppDimensions.iconMd,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppDimensions.spaceSm),
          Expanded(
            child: Text(
              'Chế độ ngoại tuyến • Dữ liệu lưu lúc ${DateTimeFormatter.formatTime(lastSavedTime)} ${DateTimeFormatter.formatDate(lastSavedTime)}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

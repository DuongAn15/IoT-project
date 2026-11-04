import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/utils/date_time_formatter.dart';

/// Header chuẩn hiển thị tên trạm quan trắc IoT, trạng thái kết nối và giờ cập nhật
class AppHeaderBar extends StatelessWidget {
  final String stationName;
  final DateTime lastUpdated;
  final bool isOnline;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onThemeToggle;
  final bool isDark;

  const AppHeaderBar({
    super.key,
    required this.stationName,
    required this.lastUpdated,
    this.isOnline = true,
    this.onSettingsTap,
    this.onThemeToggle,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spaceMd,
        vertical: AppDimensions.spaceSm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Station Info & Status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isOnline ? AppColors.success : AppColors.warning,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppDimensions.spaceSm),
                    Flexible(
                      child: Text(
                        stationName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  DateTimeFormatter.formatLastUpdated(lastUpdated),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),

          // Action Buttons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onThemeToggle != null)
                IconButton(
                  onPressed: onThemeToggle,
                  icon: Icon(
                    isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    size: AppDimensions.iconMd,
                    color: isDark ? AppColors.accentSunDark : AppColors.primaryLight,
                  ),
                  tooltip: isDark ? 'Chế độ Sáng' : 'Chế độ Tối',
                  visualDensity: VisualDensity.compact,
                ),
              if (onSettingsTap != null)
                IconButton(
                  onPressed: onSettingsTap,
                  icon: const Icon(
                    Icons.settings_outlined,
                    size: AppDimensions.iconMd,
                  ),
                  tooltip: 'Cài đặt trạm',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

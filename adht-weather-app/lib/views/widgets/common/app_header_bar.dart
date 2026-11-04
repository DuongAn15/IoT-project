import 'package:flutter/material.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';

/// Header thanh điều hướng: chứa Dropdown chọn trạm quan trắc, nút đổi Theme và icon Cài đặt
class AppHeaderBar extends StatelessWidget {
  final String stationName;
  final List<String> availableStations;
  final ValueChanged<String>? onStationChanged;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onThemeToggle;
  final bool isDark;

  const AppHeaderBar({
    super.key,
    required this.stationName,
    this.availableStations = ApiConstants.availableStations,
    this.onStationChanged,
    this.onSettingsTap,
    this.onThemeToggle,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Đảm bảo tên trạm hiện tại luôn nằm trong danh sách items
    final stations = availableStations.contains(stationName)
        ? availableStations
        : [stationName, ...availableStations];

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spaceMd,
        vertical: AppDimensions.spaceSm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Station Dropdown Selector (gần sát tên trạm, không bị kéo xa)
          Flexible(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: stationName,
                isExpanded: false,
                icon: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                    size: 22,
                  ),
                ),
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                dropdownColor: theme.cardTheme.color,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                ),
                items: stations.map((String station) {
                  return DropdownMenuItem<String>(
                    value: station,
                    child: Text(
                      station,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (newVal) {
                  if (newVal != null && newVal != stationName) {
                    onStationChanged?.call(newVal);
                  }
                },
              ),
            ),
          ),

          const SizedBox(width: AppDimensions.spaceSm),

          // Action Buttons: Theme Toggle & Settings Button
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
                  tooltip: 'Cài đặt',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../data/models/station_info.dart';

/// Header thanh điều hướng: chứa Dropdown chọn trạm quan trắc theo stationId thật, nút đổi Theme và icon Cài đặt
class AppHeaderBar extends StatelessWidget {
  final String stationName;
  final String? selectedStationId;
  final List<StationInfo>? stations;
  final ValueChanged<String>? onStationChanged;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onThemeToggle;
  final bool isDark;

  const AppHeaderBar({
    super.key,
    required this.stationName,
    this.selectedStationId,
    this.stations,
    this.onStationChanged,
    this.onSettingsTap,
    this.onThemeToggle,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalogue = (stations != null && stations!.isNotEmpty)
        ? stations!
        : StationInfo.fallbackCatalogue();
    final activeId = selectedStationId ??
        ApiConstants.resolveDeviceIdFromStationName(stationName);

    final effectiveStations = catalogue.any((s) => s.deviceId == activeId)
        ? catalogue
        : [StationInfo(deviceId: activeId, name: stationName), ...catalogue];

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spaceMd,
        vertical: AppDimensions.spaceSm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Station Dropdown Selector (dùng deviceId thật làm value)
          Flexible(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: activeId,
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
                items: effectiveStations.map((StationInfo station) {
                  return DropdownMenuItem<String>(
                    value: station.deviceId,
                    child: Text(
                      station.name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (newId) {
                  if (newId != null && newId != activeId) {
                    onStationChanged?.call(newId);
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

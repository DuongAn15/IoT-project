import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/utils/date_time_formatter.dart';
import '../../core/utils/weather_unit_helper.dart';
import '../../providers/history_7d_provider.dart';
import '../../providers/intra_day_provider.dart';
import '../../providers/theme_mode_provider.dart';
import '../../providers/weather_dashboard_provider.dart';
import '../widgets/charts/intra_day_spline_chart.dart';
import '../widgets/charts/seven_day_average_chart.dart';
import '../widgets/common/app_header_bar.dart';
import '../widgets/common/custom_pull_refresh.dart';
import '../widgets/common/offline_indicator.dart';
import '../widgets/common/shimmer_card_skeleton.dart';
import '../widgets/current/hero_weather_card.dart';
import 'history_7d_screen.dart';
import 'intra_day_detail_screen.dart';
import 'settings_screen.dart';

/// Màn hình chính Dashboard Tổng Quan Thời Tiết
class MainDashboardScreen extends ConsumerWidget {
  const MainDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(weatherDashboardProvider);
    final selectedIntraDayMetric = ref.watch(intraDaySelectedMetricProvider);
    final selectedHistoryMetric = ref.watch(history7dSelectedMetricProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: dashboardAsync.when(
          loading: () => const ShimmerCardSkeleton(),
          error: (err, stack) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
                const SizedBox(height: AppDimensions.spaceMd),
                Text('Không thể tải dữ liệu: $err'),
                const SizedBox(height: AppDimensions.spaceMd),
                FilledButton(
                  onPressed: () => ref.read(weatherDashboardProvider.notifier).refresh(),
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          ),
          data: (state) {
            // Tìm nhiệt độ thấp nhất và cao nhất trong ngày
            double? minToday;
            double? maxToday;
            if (state.intraDayPoints.isNotEmpty) {
              minToday = state.intraDayPoints
                  .map((p) => p.temperature)
                  .reduce((a, b) => a < b ? a : b);
              maxToday = state.intraDayPoints
                  .map((p) => p.temperature)
                  .reduce((a, b) => a > b ? a : b);
            }

            // Mặc định hiển thị diễn biến thời tiết hôm nay theo mốc 15 phút
            final intraDayPoints15m = state.intraDayPoints
                .where((p) => p.minutesFromMidnight % 15 == 0)
                .toList();
            final displayIntraDayPoints =
                intraDayPoints15m.length >= 2 ? intraDayPoints15m : state.intraDayPoints;

            return CustomPullRefresh(
              onRefresh: () => ref.read(weatherDashboardProvider.notifier).refresh(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Station Header Bar (Dropdown chọn trạm, icon đổi Theme & icon Cài đặt)
                    AppHeaderBar(
                      stationName: state.current.stationName,
                      isDark: isDark,
                      onStationChanged: (newStation) {
                        ref.read(weatherDashboardProvider.notifier).changeStation(newStation);
                      },
                      onThemeToggle: () {
                        ref.read(themeModeProvider.notifier).toggleTheme();
                      },
                      onSettingsTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SettingsScreen()),
                        );
                      },
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spaceMd),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 2. Offline Indicator if offline
                          if (state.isOffline)
                            OfflineIndicator(lastSavedTime: state.lastUpdated),

                          // 3. Unified Hero Weather Card (liền khối với đầy đủ 4 chỉ số cảm biến)
                          HeroWeatherCard(
                            current: state.current,
                            minTemp: minToday,
                            maxTemp: maxToday,
                          ),
                          const SizedBox(height: AppDimensions.spaceSm),

                          // Dòng chữ cập nhật thời gian chuyển xuống dưới Hero Card (căn trái, không icon đồng hồ)
                          Padding(
                            padding: const EdgeInsets.only(
                              left: AppDimensions.spaceXs,
                              top: AppDimensions.spaceXs,
                              bottom: AppDimensions.spaceSm,
                            ),
                            child: Text(
                              DateTimeFormatter.formatLastUpdated(state.lastUpdated),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppDimensions.spaceSm),

                          // 4. Khối Thời tiết hôm nay (Hiệu ứng trong suốt nổi khối)
                          _buildTranslucentCard(
                            context: context,
                            isDark: isDark,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Thời tiết hôm nay',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spaceXs),
                                      ),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => IntraDayDetailScreen(initialMetric: selectedIntraDayMetric),
                                          ),
                                        );
                                      },
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('Xem chi tiết'),
                                          SizedBox(width: 2),
                                          Icon(Icons.chevron_right_rounded, size: 18),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppDimensions.spaceXs),

                                // Bộ chọn chỉ số cho Thời tiết hôm nay
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: WeatherMetricType.values.map((metric) {
                                      final isSelected = metric == selectedIntraDayMetric;
                                      return Padding(
                                        padding: const EdgeInsets.only(right: AppDimensions.spaceSm),
                                        child: FilterChip(
                                          selected: isSelected,
                                          avatar: Icon(
                                            metric.icon,
                                            size: AppDimensions.iconSm,
                                            color: isSelected
                                                ? Colors.white
                                                : (isDark ? Colors.white70 : AppColors.primaryLight),
                                          ),
                                          label: Text(metric.labelVi),
                                          selectedColor: isDark ? AppColors.primaryDark : AppColors.primaryLight,
                                          labelStyle: theme.textTheme.labelMedium?.copyWith(
                                            color: isSelected ? Colors.white : null,
                                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                          ),
                                          onSelected: (_) {
                                            ref.read(intraDaySelectedMetricProvider.notifier).state = metric;
                                          },
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                                const SizedBox(height: AppDimensions.spaceMd),

                                // Tiêu đề phụ chỉ số đang chọn
                                Row(
                                  children: [
                                    Icon(
                                      selectedIntraDayMetric.icon,
                                      size: AppDimensions.iconSm,
                                      color: isDark ? AppColors.primaryDark : AppColors.primaryLight,
                                    ),
                                    const SizedBox(width: AppDimensions.spaceXs),
                                    Text(
                                      '${selectedIntraDayMetric.labelVi} (${selectedIntraDayMetric.unit}) từ 00:00 đến nay',
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppDimensions.spaceSm),
                                IntraDaySplineChart(
                                  points: displayIntraDayPoints,
                                  metricType: selectedIntraDayMetric,
                                  isCompact: true,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppDimensions.spaceMd),

                          // 5. Khối Lịch sử (Hiệu ứng trong suốt nổi khối)
                          _buildTranslucentCard(
                            context: context,
                            isDark: isDark,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Lịch sử',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.spaceXs),
                                      ),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const History7dScreen(),
                                          ),
                                        );
                                      },
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('Xem chi tiết'),
                                          SizedBox(width: 2),
                                          Icon(Icons.chevron_right_rounded, size: 18),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppDimensions.spaceXs),

                                // Bộ chọn chỉ số cho Lịch sử
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: WeatherMetricType.values.map((metric) {
                                      final isSelected = metric == selectedHistoryMetric;
                                      return Padding(
                                        padding: const EdgeInsets.only(right: AppDimensions.spaceSm),
                                        child: FilterChip(
                                          selected: isSelected,
                                          avatar: Icon(
                                            metric.icon,
                                            size: AppDimensions.iconSm,
                                            color: isSelected
                                                ? Colors.white
                                                : (isDark ? Colors.white70 : AppColors.primaryLight),
                                          ),
                                          label: Text(metric == WeatherMetricType.rainfall ? 'Lượng mưa' : metric.labelVi),
                                          selectedColor: isDark ? AppColors.primaryDark : AppColors.primaryLight,
                                          labelStyle: theme.textTheme.labelMedium?.copyWith(
                                            color: isSelected ? Colors.white : null,
                                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                          ),
                                          onSelected: (_) {
                                            ref.read(history7dSelectedMetricProvider.notifier).state = metric;
                                          },
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                                const SizedBox(height: AppDimensions.spaceMd),

                                // Tiêu đề phụ chỉ số đang chọn
                                Row(
                                  children: [
                                    Icon(
                                      selectedHistoryMetric.icon,
                                      size: AppDimensions.iconSm,
                                      color: isDark ? AppColors.primaryDark : AppColors.primaryLight,
                                    ),
                                    const SizedBox(width: AppDimensions.spaceXs),
                                    Text(
                                      selectedHistoryMetric == WeatherMetricType.rainfall
                                          ? 'Tổng lượng mưa (${selectedHistoryMetric.unit})'
                                          : 'Trung bình ${selectedHistoryMetric.labelVi} (${selectedHistoryMetric.unit})',
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppDimensions.spaceSm),
                                SevenDayAverageChart(
                                  dailySummaries: state.weeklySummaries,
                                  metricType: selectedHistoryMetric,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Khối container bán trong suốt kiểu nổi (Translucent Floating Container)
  Widget _buildTranslucentCard({
    required BuildContext context,
    required bool isDark,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : const Color(0xFFE2E8F0).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : const Color(0xFF94A3B8).withValues(alpha: 0.25),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 16,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppDimensions.spaceMd),
      child: child,
    );
  }
}

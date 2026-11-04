import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/utils/weather_unit_helper.dart';
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
  final Function(int)? onNavigateTab;

  const MainDashboardScreen({
    super.key,
    this.onNavigateTab,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(weatherDashboardProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: dashboardAsync.when(
          loading: () => const ShimmerCardSkeleton(),
          error: (err, stack) => Center(
            child: Padding(
              padding: const EdgeInsets.all(AppDimensions.spaceLg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 56, color: AppColors.error),
                  const SizedBox(height: AppDimensions.spaceMd),
                  Text(
                    'Không thể kết nối trạm quan trắc',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppDimensions.spaceSm),
                  Text(
                    err.toString(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppDimensions.spaceLg),
                  FilledButton.icon(
                    onPressed: () => ref.read(weatherDashboardProvider.notifier).refresh(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Thử kết nối lại'),
                  ),
                ],
              ),
            ),
          ),
          data: (state) {
            // Tính toán min/max nhiệt độ hôm nay từ chuỗi mốc 5 phút
            double? minToday;
            double? maxToday;
            if (state.intraDayPoints.isNotEmpty) {
              minToday = state.intraDayPoints.first.temperature;
              maxToday = state.intraDayPoints.first.temperature;
              for (final p in state.intraDayPoints) {
                if (p.temperature < minToday!) minToday = p.temperature;
                if (p.temperature > maxToday!) maxToday = p.temperature;
              }
            }

            return CustomPullRefresh(
              onRefresh: () => ref.read(weatherDashboardProvider.notifier).refresh(),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: AppDimensions.space2xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Station Header Bar
                    AppHeaderBar(
                      stationName: state.current.stationName,
                      lastUpdated: state.lastUpdated,
                      isOnline: state.current.isOnline,
                      isDark: isDark,
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
                            onMetricTap: (metricType) {
                              ref.read(intraDaySelectedMetricProvider.notifier).state = metricType;
                              if (onNavigateTab != null) {
                                onNavigateTab!(1); // Chuyển sang Tab Trong ngày
                              } else {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => IntraDayDetailScreen(initialMetric: metricType),
                                  ),
                                );
                              }
                            },
                          ),
                          const SizedBox(height: AppDimensions.spaceLg),

                          // 4. Intra-day preview chart section
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Diễn biến hôm nay',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  if (onNavigateTab != null) {
                                    onNavigateTab!(1);
                                  } else {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const IntraDayDetailScreen(),
                                      ),
                                    );
                                  }
                                },
                                child: const Row(
                                  children: [
                                    Text('Xem chi tiết'),
                                    SizedBox(width: 2),
                                    Icon(Icons.chevron_right_rounded, size: 18),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AppDimensions.spaceMd),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.thermostat_rounded,
                                        size: AppDimensions.iconSm,
                                        color: AppColors.temperature,
                                      ),
                                      const SizedBox(width: AppDimensions.spaceXs),
                                      Text(
                                        'Nhiệt độ (°C) từ 00:00 đến nay',
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppDimensions.spaceSm),
                                  IntraDaySplineChart(
                                    points: state.intraDayPoints,
                                    metricType: WeatherMetricType.temperature,
                                    isCompact: true,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: AppDimensions.spaceLg),

                          // 6. 7-day preview chart section
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Xu hướng 7 ngày gần nhất',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  if (onNavigateTab != null) {
                                    onNavigateTab!(2);
                                  } else {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const History7dScreen(),
                                      ),
                                    );
                                  }
                                },
                                child: const Row(
                                  children: [
                                    Text('Xem chi tiết'),
                                    SizedBox(width: 2),
                                    Icon(Icons.chevron_right_rounded, size: 18),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AppDimensions.spaceMd),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.calendar_month_rounded,
                                        size: AppDimensions.iconSm,
                                        color: AppColors.primaryLight,
                                      ),
                                      const SizedBox(width: AppDimensions.spaceXs),
                                      Text(
                                        'Nhiệt độ trung bình (°C)',
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: AppDimensions.spaceSm),
                                  SevenDayAverageChart(
                                    dailySummaries: state.weeklySummaries,
                                    metricType: WeatherMetricType.temperature,
                                  ),
                                ],
                              ),
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
}

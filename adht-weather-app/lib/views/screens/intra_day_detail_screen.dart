import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/utils/date_time_formatter.dart';
import '../../core/utils/weather_unit_helper.dart';
import '../../data/models/weather_point.dart';
import '../../providers/intra_day_provider.dart';
import '../../providers/weather_dashboard_provider.dart';
import '../widgets/charts/intra_day_spline_chart.dart';
import '../widgets/common/custom_pull_refresh.dart';
import '../widgets/common/shimmer_card_skeleton.dart';

/// Màn hình phân tích chi tiết diễn biến trong ngày mốc 5 phút
class IntraDayDetailScreen extends ConsumerWidget {
  final WeatherMetricType? initialMetric;

  const IntraDayDetailScreen({
    super.key,
    this.initialMetric,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(weatherDashboardProvider);
    final selectedMetric = ref.watch(intraDaySelectedMetricProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Diễn Biến Trong Ngày',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: dashboardAsync.when(
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
          final points = state.intraDayPoints;

          return CustomPullRefresh(
            onRefresh: () => ref.read(weatherDashboardProvider.notifier).refresh(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppDimensions.spaceMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Metric Segmented Tab Selector
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: WeatherMetricType.values.map((metric) {
                        final isSelected = metric == selectedMetric;
                        return Padding(
                          padding: const EdgeInsets.only(right: AppDimensions.spaceSm),
                          child: FilterChip(
                            selected: isSelected,
                            avatar: Icon(
                              metric.icon,
                              size: AppDimensions.iconSm,
                              color: isSelected ? Colors.white : (isDark ? Colors.white70 : AppColors.primaryLight),
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

                  // 2. Summary Stat Cards (Hiện tại, Cao nhất, Thấp nhất)
                  _buildStatCardsRow(context, points, selectedMetric),
                  const SizedBox(height: AppDimensions.spaceLg),

                  // 3. Interactive Spline Chart Card (Hiển thị tất cả bản ghi có trong ngày)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppDimensions.spaceMd),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Đồ thị ${selectedMetric.labelVi} (${selectedMetric.unit})',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isDark ? AppColors.surfaceVariantDark : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                                ),
                                child: Text(
                                  'Từ 00:00 đến ${DateTimeFormatter.formatTime(DateTime.now())}',
                                  style: theme.textTheme.labelSmall,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppDimensions.spaceMd),
                          IntraDaySplineChart(
                            points: points,
                            metricType: selectedMetric,
                            isCompact: false,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spaceLg),

                  // 4. Recent Readings Table Preview
                  _buildRecentReadingsList(
                    context,
                    points,
                    selectedMetric,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCardsRow(
    BuildContext context,
    List<WeatherPoint> points,
    WeatherMetricType metric,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    double currentVal = 0.0;
    double minVal = double.infinity;
    double maxVal = -double.infinity;

    for (final p in points) {
      double val = 0.0;
      switch (metric) {
        case WeatherMetricType.temperature:
          val = p.temperature;
          break;
        case WeatherMetricType.humidity:
          val = p.humidity;
          break;
        case WeatherMetricType.rainfall:
          val = p.rainfall;
          break;
        case WeatherMetricType.windSpeed:
          val = p.windSpeed;
          break;
      }
      if (val < minVal) minVal = val;
      if (val > maxVal) maxVal = val;
    }
    if (points.isNotEmpty) {
      final last = points.last;
      switch (metric) {
        case WeatherMetricType.temperature:
          currentVal = last.temperature;
          break;
        case WeatherMetricType.humidity:
          currentVal = last.humidity;
          break;
        case WeatherMetricType.rainfall:
          currentVal = last.rainfall;
          break;
        case WeatherMetricType.windSpeed:
          currentVal = last.windSpeed;
          break;
      }
    } else {
      minVal = 0.0;
      maxVal = 0.0;
    }

    final isHum = metric == WeatherMetricType.humidity;

    return Row(
      children: [
        Expanded(
          child: _buildMiniStatTile(
            theme: theme,
            isDark: isDark,
            title: 'Hiện tại',
            value: '${currentVal.toStringAsFixed(isHum ? 0 : 1)} ${metric.unit}',
            color: isDark ? AppColors.primaryDark : AppColors.primaryLight,
          ),
        ),
        const SizedBox(width: AppDimensions.spaceSm),
        Expanded(
          child: _buildMiniStatTile(
            theme: theme,
            isDark: isDark,
            title: 'Thấp nhất',
            value: '${minVal.toStringAsFixed(isHum ? 0 : 1)} ${metric.unit}',
            color: AppColors.info,
          ),
        ),
        const SizedBox(width: AppDimensions.spaceSm),
        Expanded(
          child: _buildMiniStatTile(
            theme: theme,
            isDark: isDark,
            title: 'Cao nhất',
            value: '${maxVal.toStringAsFixed(isHum ? 0 : 1)} ${metric.unit}',
            color: AppColors.temperature,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStatTile({
    required ThemeData theme,
    required bool isDark,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spaceSm,
        vertical: AppDimensions.spaceMd,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.labelSmall),
          const SizedBox(height: AppDimensions.spaceXs),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentReadingsList(
    BuildContext context,
    List<WeatherPoint> points,
    WeatherMetricType metric,
  ) {
    final theme = Theme.of(context);
    final recent = points.reversed.take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bản ghi gần nhất',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppDimensions.spaceSm),
        Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recent.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final point = recent[index];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.access_time_rounded, size: AppDimensions.iconSm),
                title: Text(
                  DateTimeFormatter.formatTime(point.timestamp),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${WeatherUnitHelper.formatTemp(point.temperature)} • ${WeatherUnitHelper.formatHumidity(point.humidity)} • Gió ${WeatherUnitHelper.formatWind(point.windSpeed)}',
                  style: theme.textTheme.bodySmall,
                ),
                trailing: Text(
                  point.rainfall > 0 ? '${point.rainfall} mm' : 'Khô ráo',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: point.rainfall > 0 ? AppColors.rainfall : null,
                    fontWeight: point.rainfall > 0 ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/utils/date_time_formatter.dart';
import '../../core/utils/weather_unit_helper.dart';
import '../../data/models/weather_daily_summary.dart';
import '../../providers/history_7d_provider.dart';
import '../../providers/weather_dashboard_provider.dart';
import '../widgets/charts/rainfall_bar_chart.dart';
import '../widgets/charts/seven_day_average_chart.dart';
import '../widgets/common/custom_pull_refresh.dart';
import '../widgets/common/shimmer_card_skeleton.dart';

/// Màn hình phân tích xu hướng 7 ngày gần nhất (Trung bình ngày & Tổng lượng mưa)
class History7dScreen extends ConsumerWidget {
  const History7dScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(weatherDashboardProvider);
    final selectedMetric = ref.watch(history7dSelectedMetricProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Xu Hướng 7 Ngày Gần Nhất',
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
          final summaries = state.weeklySummaries;

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
                            label: Text(metric == WeatherMetricType.rainfall ? 'Tổng Lượng mưa' : 'TB ${metric.labelVi}'),
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

                  // 2. Interactive Chart Card
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
                                selectedMetric == WeatherMetricType.rainfall
                                    ? 'Tổng Lượng Mưa 7 Ngày (mm)'
                                    : 'Giá Trị Trung Bình 7 Ngày (${selectedMetric.unit})',
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
                                  '7 ngày qua',
                                  style: theme.textTheme.labelSmall,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppDimensions.spaceMd),
                          if (selectedMetric == WeatherMetricType.rainfall)
                            RainfallBarChart(dailySummaries: summaries)
                          else
                            SevenDayAverageChart(
                              dailySummaries: summaries,
                              metricType: selectedMetric,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppDimensions.spaceLg),

                  // 3. Detailed Day-by-Day List
                  _buildDayByDayList(context, summaries),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDayByDayList(BuildContext context, List<WeatherDailySummary> summaries) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Chi tiết tổng hợp từng ngày',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppDimensions.spaceSm),
        Card(
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: summaries.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final summary = summaries[summaries.length - 1 - index]; // Mới nhất lên đầu
              final isToday = summary.dayOfWeek == 'Hôm nay';

              return Padding(
                padding: const EdgeInsets.all(AppDimensions.spaceMd),
                child: Row(
                  children: [
                    // Day of week & date
                    SizedBox(
                      width: 72,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            summary.dayOfWeek,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isToday
                                  ? (isDark ? AppColors.primaryDark : AppColors.primaryLight)
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            DateTimeFormatter.formatShortDate(summary.date),
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),

                    // Metrics breakdown
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          // Temp
                          _buildColumnMetric(
                            theme: theme,
                            label: 'Nhiệt độ TB',
                            value: '${summary.avgTemperature.toStringAsFixed(1)}°C',
                            subValue: '${summary.minTemperature.toStringAsFixed(0)}° - ${summary.maxTemperature.toStringAsFixed(0)}°',
                          ),

                          // Humidity
                          _buildColumnMetric(
                            theme: theme,
                            label: 'Độ ẩm TB',
                            value: '${summary.avgHumidity.toStringAsFixed(0)}%',
                          ),

                          // Rainfall
                          _buildColumnMetric(
                            theme: theme,
                            label: 'Mưa',
                            value: summary.totalRainfall > 0
                                ? '${summary.totalRainfall.toStringAsFixed(1)} mm'
                                : '0 mm',
                            valueColor: summary.totalRainfall > 0 ? AppColors.rainfall : null,
                          ),

                          // Wind
                          _buildColumnMetric(
                            theme: theme,
                            label: 'Gió TB',
                            value: '${summary.avgWindSpeed.toStringAsFixed(1)} km/h',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildColumnMetric({
    required ThemeData theme,
    required String label,
    required String value,
    String? subValue,
    Color? valueColor,
  }) {
    return Column(
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
        if (subValue != null)
          Text(
            subValue,
            style: theme.textTheme.labelSmall?.copyWith(fontSize: 9),
          ),
      ],
    );
  }
}

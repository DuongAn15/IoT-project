import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/utils/weather_unit_helper.dart';
import '../../providers/theme_mode_provider.dart';

/// Màn hình Cài đặt kết nối trạm đo và cấu hình giao diện
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Cài Đặt & Cấu Hình',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppDimensions.spaceMd),
        children: [
          // 1. Station Information Section
          _buildSectionHeader(context, 'Thông tin trạm quan trắc IoT'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.router_rounded, color: AppColors.primaryLight),
                  title: const Text('Mã trạm (Station ID)'),
                  subtitle: const Text(ApiConstants.defaultStationId),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 14, color: AppColors.success),
                        SizedBox(width: 4),
                        Text(
                          'Trực tuyến',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                const ListTile(
                  leading: Icon(Icons.place_outlined),
                  title: Text('Vị trí trạm'),
                  subtitle: Text(ApiConstants.defaultLocation),
                ),
                const Divider(),
                const ListTile(
                  leading: Icon(Icons.memory_rounded),
                  title: Text('Phiên bản Firmware'),
                  subtitle: Text('v2.4.1-iot'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.spaceLg),

          // 2. Sensor Status Check
          _buildSectionHeader(context, 'Trạng thái các cảm biến'),
          Card(
            child: Column(
              children: [
                _buildSensorStatusTile(
                  context,
                  type: WeatherMetricType.temperature,
                  sensorModel: 'Sensirion SHT31',
                  status: 'Hoạt động tốt',
                  color: AppColors.temperature,
                ),
                const Divider(),
                _buildSensorStatusTile(
                  context,
                  type: WeatherMetricType.humidity,
                  sensorModel: 'Sensirion SHT31',
                  status: 'Hoạt động tốt',
                  color: AppColors.humidity,
                ),
                const Divider(),
                _buildSensorStatusTile(
                  context,
                  type: WeatherMetricType.rainfall,
                  sensorModel: 'Tipping Bucket Rain Gauge',
                  status: 'Hoạt động tốt',
                  color: AppColors.rainfall,
                ),
                const Divider(),
                _buildSensorStatusTile(
                  context,
                  type: WeatherMetricType.windSpeed,
                  sensorModel: '3-Cup Anemometer Pulse',
                  status: 'Hoạt động tốt',
                  color: AppColors.windSpeed,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.spaceLg),

          // 3. Theme Mode Selection
          _buildSectionHeader(context, 'Giao diện & Chủ đề'),
          Card(
            child: RadioGroup<ThemeMode>(
              groupValue: themeMode,
              onChanged: (val) {
                if (val != null) ref.read(themeModeProvider.notifier).setThemeMode(val);
              },
              child: const Column(
                children: [
                  RadioListTile<ThemeMode>(
                    title: Text('Theo hệ điều hành'),
                    subtitle: Text('Tự động chuyển đổi theo cài đặt máy'),
                    secondary: Icon(Icons.brightness_auto_rounded),
                    value: ThemeMode.system,
                  ),
                  Divider(),
                  RadioListTile<ThemeMode>(
                    title: Text('Chế độ Sáng (Light Mode)'),
                    subtitle: Text('Phông nền trắng ngà dịu mắt'),
                    secondary: Icon(Icons.light_mode_rounded),
                    value: ThemeMode.light,
                  ),
                  Divider(),
                  RadioListTile<ThemeMode>(
                    title: Text('Chế độ Tối (Dark Mode)'),
                    subtitle: Text('Phông nền đen tối ưu pin & mắt'),
                    secondary: Icon(Icons.dark_mode_rounded),
                    value: ThemeMode.dark,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppDimensions.spaceLg),

          // 4. Offline SQLite Cache Management
          _buildSectionHeader(context, 'Bộ nhớ đệm SQLite 7 ngày'),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.storage_rounded),
                  title: Text('Chính sách lưu trữ'),
                  subtitle: Text('Tự động xóa bản ghi cũ hơn 7 ngày khi refresh'),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined, color: AppColors.warning),
                  title: const Text('Xóa bộ nhớ đệm SQLite'),
                  subtitle: const Text('Giải phóng dữ liệu đệm và nạp lại từ đầu'),
                  trailing: TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Đã dọn dẹp bộ nhớ đệm SQLite thành công!'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: const Text('Xóa đệm'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.spaceLg),

          // 5. About Section
          Center(
            child: Column(
              children: [
                Text(
                  'Weather Monitoring Mobile App',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Phiên bản 1.0.0 (UI-First Architecture)',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.spaceXl),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppDimensions.spaceXs,
        bottom: AppDimensions.spaceSm,
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primaryLight,
            ),
      ),
    );
  }

  Widget _buildSensorStatusTile(
    BuildContext context, {
    required WeatherMetricType type,
    required String sensorModel,
    required String status,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(AppDimensions.spaceSm),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(type.icon, size: AppDimensions.iconSm, color: color),
      ),
      title: Text(type.labelVi, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(sensorModel),
      trailing: Text(
        status,
        style: theme.textTheme.labelSmall?.copyWith(
          color: AppColors.success,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

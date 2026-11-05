import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/api_constants.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../providers/device_settings_provider.dart';

/// Màn hình Cài Đặt Trạm: Chọn Trạm, Điều Khiển Command & Cấu Hình Config
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _tempMaxController;
  late final TextEditingController _tempMinController;
  late final TextEditingController _humiMaxController;
  late final TextEditingController _windMaxController;
  late final TextEditingController _rainMaxController;

  @override
  void initState() {
    super.initState();
    final initialConfig = ref.read(deviceConfigProvider).config;
    _tempMaxController = TextEditingController(
      text: initialConfig.tempMax?.toString() ?? '38.0',
    );
    _tempMinController = TextEditingController(
      text: initialConfig.tempMin?.toString() ?? '10.0',
    );
    _humiMaxController = TextEditingController(
      text: initialConfig.humiMax?.toString() ?? '90.0',
    );
    _windMaxController = TextEditingController(
      text: initialConfig.windMax?.toString() ?? '15.0',
    );
    _rainMaxController = TextEditingController(
      text: initialConfig.rainMax?.toString() ?? '30.0',
    );
  }

  @override
  void dispose() {
    _tempMaxController.dispose();
    _tempMinController.dispose();
    _humiMaxController.dispose();
    _windMaxController.dispose();
    _rainMaxController.dispose();
    super.dispose();
  }

  void _showFeedback(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: AppDimensions.spaceSm),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedStationId = ref.watch(selectedDeviceIdProvider);

    // Lắng nghe trạng thái Command để hiển thị SnackBar
    ref.listen<DeviceCommandState>(deviceCommandProvider, (prev, next) {
      if (next.lastSuccessMessage != null &&
          next.lastSuccessMessage != prev?.lastSuccessMessage) {
        _showFeedback(next.lastSuccessMessage!);
      } else if (next.errorMessage != null &&
          next.errorMessage != prev?.errorMessage) {
        _showFeedback(next.errorMessage!, isError: true);
      }
    });

    // Lắng nghe trạng thái Config để hiển thị SnackBar
    ref.listen<DeviceConfigState>(deviceConfigProvider, (prev, next) {
      if (next.lastSuccessMessage != null &&
          next.lastSuccessMessage != prev?.lastSuccessMessage) {
        _showFeedback(next.lastSuccessMessage!);
      } else if (next.errorMessage != null &&
          next.errorMessage != prev?.errorMessage) {
        _showFeedback(next.errorMessage!, isError: true);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Cài Đặt & Cấu Hình Trạm',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppDimensions.spaceMd),
          children: [
            // Dropdown chọn trạm
            _buildStationSelector(selectedStationId),
            const SizedBox(height: AppDimensions.spaceLg),

            // Mục 1: Command (Điều khiển tức thời)
            _buildSectionTitle('Command'),
            const SizedBox(height: AppDimensions.spaceSm),
            _buildCommandCard(),
            const SizedBox(height: AppDimensions.spaceLg),

            // Mục 2: Config Alert (Cài đặt ngưỡng)
            _buildSectionTitle('Config Alert'),
            const SizedBox(height: AppDimensions.spaceSm),
            _buildConfigCard(),
            const SizedBox(height: AppDimensions.spaceXl),
          ],
        ),
      ),
    );
  }

  /// Dropdown chọn trạm đo
  Widget _buildStationSelector(String currentStationId) {
    final theme = Theme.of(context);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trạm quan trắc',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppDimensions.spaceSm),
            DropdownButtonFormField<String>(
              initialValue: currentStationId,
              isExpanded: true,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.spaceMd,
                  vertical: AppDimensions.spaceSm,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                ),
              ),
              items: ApiConstants.deviceStationMap.entries.map((entry) {
                return DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(
                    '${entry.key} (${entry.value})',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (newId) {
                if (newId != null) {
                  ref.read(selectedDeviceIdProvider.notifier).state = newId;
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Tiêu đề mục tối giản
  Widget _buildSectionTitle(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: AppDimensions.spaceXs),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  /// Mục 1: Khối lệnh Command với 3 nút bấm tức thời
  Widget _buildCommandCard() {
    final commandState = ref.watch(deviceCommandProvider);
    final notifier = ref.read(deviceCommandProvider.notifier);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spaceMd),
        child: Row(
          children: [
            // 1. Nút Bật LED
            Expanded(
              child: _buildCommandButton(
                label: 'Bật LED',
                icon: Icons.lightbulb_rounded,
                color: AppColors.warning,
                isLoading: commandState.activeCommand == 'led',
                isDisabled: commandState.isLoading,
                onPressed: () => notifier.sendInstantCommand(
                  'led',
                  arg: '1',
                  labelVi: 'bật đèn',
                ),
              ),
            ),
            const SizedBox(width: AppDimensions.spaceSm),

            // 2. Nút Còi Buzzer
            Expanded(
              child: _buildCommandButton(
                label: 'Buzzer',
                icon: Icons.volume_up_rounded,
                color: AppColors.primaryLight,
                isLoading: commandState.activeCommand == 'buzzer',
                isDisabled: commandState.isLoading,
                onPressed: () => notifier.sendInstantCommand(
                  'buzzer',
                  arg: '500',
                  labelVi: 'bật còi',
                ),
              ),
            ),
            const SizedBox(width: AppDimensions.spaceSm),

            // 3. Nút Reset
            Expanded(
              child: _buildCommandButton(
                label: 'Reset',
                icon: Icons.restart_alt_rounded,
                color: AppColors.error,
                isLoading: commandState.activeCommand == 'reboot',
                isDisabled: commandState.isLoading,
                onPressed: () => notifier.sendInstantCommand(
                  'reboot',
                  arg: 'now',
                  labelVi: 'reset',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Nút bấm lệnh con với icon và hiệu ứng loading độc lập
  Widget _buildCommandButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool isLoading,
    required bool isDisabled,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 72,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withValues(alpha: 0.5), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          backgroundColor: color.withValues(alpha: 0.06),
        ),
        onPressed: isDisabled ? null : onPressed,
        child: isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 24),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
      ),
    );
  }

  /// Mục 2: Khối cấu hình Config với các ô nhập liệu và nút Lưu Cấu Hình
  Widget _buildConfigCard() {
    final configState = ref.watch(deviceConfigProvider);
    final notifier = ref.read(deviceConfigProvider.notifier);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.spaceMd),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Ngưỡng nhiệt độ
              Row(
                children: [
                  Expanded(
                    child: _buildNumberInputField(
                      controller: _tempMaxController,
                      label: 'Ngưỡng nhiệt max',
                      suffix: '°C',
                      onChanged: (val) => notifier.updateTempMax(double.tryParse(val)),
                    ),
                  ),
                  const SizedBox(width: AppDimensions.spaceSm),
                  Expanded(
                    child: _buildNumberInputField(
                      controller: _tempMinController,
                      label: 'Ngưỡng nhiệt min',
                      suffix: '°C',
                      onChanged: (val) => notifier.updateTempMin(double.tryParse(val)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.spaceSm),

              // Ngưỡng độ ẩm & Gió
              Row(
                children: [
                  Expanded(
                    child: _buildNumberInputField(
                      controller: _humiMaxController,
                      label: 'Ngưỡng độ ẩm',
                      suffix: '%',
                      onChanged: (val) => notifier.updateHumiMax(double.tryParse(val)),
                    ),
                  ),
                  const SizedBox(width: AppDimensions.spaceSm),
                  Expanded(
                    child: _buildNumberInputField(
                      controller: _windMaxController,
                      label: 'Ngưỡng gió',
                      suffix: 'm/s',
                      onChanged: (val) => notifier.updateWindMax(double.tryParse(val)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.spaceSm),

              // Ngưỡng mưa
              _buildNumberInputField(
                controller: _rainMaxController,
                label: 'Ngưỡng độ mưa',
                suffix: 'mm/h',
                onChanged: (val) => notifier.updateRainMax(double.tryParse(val)),
              ),
              const SizedBox(height: AppDimensions.spaceSm),
              const Divider(),

              // Switch Auto Alert
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Container(
                  padding: const EdgeInsets.all(AppDimensions.spaceSm),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.notification_important_rounded,
                    color: AppColors.primaryLight,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Auto Alert',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                value: configState.config.autoWarning ?? true,
                onChanged: configState.isSaving
                    ? null
                    : (val) => notifier.toggleAutoWarning(val),
              ),
              const SizedBox(height: AppDimensions.spaceMd),

              // Nút Lưu Cấu Hình
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryLight,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                    ),
                  ),
                  onPressed: configState.isSaving
                      ? null
                      : () {
                          if (_formKey.currentState?.validate() ?? false) {
                            FocusScope.of(context).unfocus();
                            notifier.saveConfig();
                          }
                        },
                  icon: configState.isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(
                    configState.isSaving ? 'Đang Lưu Cấu Hình...' : 'Lưu Cấu Hình',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Widget ô nhập số liệu cảm biến tối giản, kích thước chữ vừa vặn
  Widget _buildNumberInputField({
    required TextEditingController controller,
    required String label,
    required String suffix,
    required ValueChanged<String> onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12),
        floatingLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        suffixText: suffix,
        suffixStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.spaceSm,
          vertical: AppDimensions.spaceSm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        ),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Không được để trống';
        }
        if (double.tryParse(value) == null) {
          return 'Cần nhập số hợp lệ';
        }
        return null;
      },
      onChanged: onChanged,
    );
  }
}

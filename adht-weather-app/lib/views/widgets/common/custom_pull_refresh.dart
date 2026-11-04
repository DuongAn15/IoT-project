import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';

/// Thành phần vuốt để làm mới (Native Pull-To-Refresh)
/// Có phản hồi xúc giác nhẹ (HapticFeedback) và màu sắc thích ứng Material 3.
class CustomPullRefresh extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;

  const CustomPullRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: () async {
        HapticFeedback.lightImpact();
        await onRefresh();
      },
      color: isDark ? AppColors.primaryDark : AppColors.primaryLight,
      backgroundColor: theme.cardTheme.color ?? theme.colorScheme.surface,
      displacement: 40,
      edgeOffset: 0,
      child: child,
    );
  }
}

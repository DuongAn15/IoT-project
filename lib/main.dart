import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'providers/theme_mode_provider.dart';
import 'views/screens/main_dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: WeatherMonitoringApp(),
    ),
  );
}

/// Gốc ứng dụng Weather Monitoring Mobile App
class WeatherMonitoringApp extends ConsumerWidget {
  const WeatherMonitoringApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Weather Monitoring',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const MainDashboardScreen(),
    );
  }
}

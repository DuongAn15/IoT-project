import 'package:flutter/material.dart';

/// Bảng màu chuẩn theo quy ước Weather Monitoring App
/// Tích hợp Design Tokens cho cả Light Mode và Dark Mode.
abstract class AppColors {
  // Brand & Accent Colors
  static const Color primaryLight = Color(0xFF0369A1); // Ocean Blue
  static const Color primaryDark = Color(0xFF38BDF8); // Sky Glow
  static const Color secondaryLight = Color(0xFF0EA5E9); // Sky Blue
  static const Color secondaryDark = Color(0xFF0284C7); // Deep Sky
  static const Color accentSunLight = Color(0xFFF59E0B); // Amber Sun
  static const Color accentSunDark = Color(0xFFFBBF24); // Warm Gold

  // Surface & Backgrounds
  static const Color bgLight = Color(0xFFF8FAFC); // Slate Light
  static const Color bgDark = Color(0xFF0B1120); // Dark Space
  static const Color surfaceLight = Color(0xFFFFFFFF); // Pure White
  static const Color surfaceDark = Color(0xFF1E293B); // Dark Slate Card
  static const Color surfaceVariantLight = Color(0xFFF1F5F9);
  static const Color surfaceVariantDark = Color(0xFF334155);

  // Text Colors
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryLight = Color(0xFF64748B);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
  static const Color textMutedLight = Color(0xFF94A3B8);
  static const Color textMutedDark = Color(0xFF64748B);

  // 4 Chỉ số cảm biến cốt lõi (Semantic Metric Colors)
  static const Color temperature = Color(0xFFEF4444); // Đỏ ấm / Cam nhiệt
  static const Color temperatureBg = Color(0xFFFEE2E2);
  static const Color temperatureBgDark = Color(0xFF451A1A);

  static const Color humidity = Color(0xFFC026D3); // Tím Magenta (Fuchsia / Magenta)
  static const Color humidityBg = Color(0xFFFAE8FF);
  static const Color humidityBgDark = Color(0xFF4A044E);

  static const Color rainfall = Color(0xFF06B6D4); // Xanh mây mưa / Cyan
  static const Color rainfallBg = Color(0xFFCFFAFE);
  static const Color rainfallBgDark = Color(0xFF0E3842);

  static const Color windSpeed = Color(0xFF10B981); // Xanh lục ngọc
  static const Color windSpeedBg = Color(0xFFD1FAE5);
  static const Color windSpeedBgDark = Color(0xFF063524);

  // Status Colors
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Chart Gradients for Spline Fill

  static const LinearGradient tempChartGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x99EF4444), Color(0x05EF4444)],
  );

  static const LinearGradient humidityChartGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x99C026D3), Color(0x05C026D3)],
  );

  static const LinearGradient windChartGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x9910B981), Color(0x0510B981)],
  );

  static const LinearGradient rainChartGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x9906B6D4), Color(0x0506B6D4)],
  );
}

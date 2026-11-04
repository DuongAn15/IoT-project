import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Hệ thống ColorScheme Material 3 cho Ứng dụng
abstract class AppColorSchemes {
  static const ColorScheme lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.primaryLight,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFBAE6FD),
    onPrimaryContainer: Color(0xFF0369A1),
    secondary: AppColors.secondaryLight,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFE0F2FE),
    onSecondaryContainer: Color(0xFF0284C7),
    tertiary: AppColors.accentSunLight,
    onTertiary: Colors.white,
    error: AppColors.error,
    onError: Colors.white,
    surface: AppColors.surfaceLight,
    onSurface: AppColors.textPrimaryLight,
    surfaceContainerHighest: AppColors.surfaceVariantLight,
    onSurfaceVariant: AppColors.textSecondaryLight,
    outline: Color(0xFFE2E8F0),
    outlineVariant: Color(0xFFCBD5E1),
    shadow: Color(0x14000000),
  );

  static const ColorScheme darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.primaryDark,
    onPrimary: Color(0xFF082F49),
    primaryContainer: Color(0xFF0369A1),
    onPrimaryContainer: Color(0xFFE0F2FE),
    secondary: AppColors.secondaryDark,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFF075985),
    onSecondaryContainer: Color(0xFFBAE6FD),
    tertiary: AppColors.accentSunDark,
    onTertiary: Color(0xFF451A03),
    error: Color(0xFFF87171),
    onError: Color(0xFF450A0A),
    surface: AppColors.surfaceDark,
    onSurface: AppColors.textPrimaryDark,
    surfaceContainerHighest: AppColors.surfaceVariantDark,
    onSurfaceVariant: AppColors.textSecondaryDark,
    outline: Color(0xFF334155),
    outlineVariant: Color(0xFF475569),
    shadow: Color(0x33000000),
  );
}

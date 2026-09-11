import 'package:flutter/material.dart';

/// Tokens de color de `docs/DESIGN_SYSTEM.md`.
abstract final class AppColors {
  static const Color primaryDark = Color(0xFF0B3C5D);
  static const Color primary = Color(0xFF1D84B5);
  static const Color accent = Color(0xFFFF6B5B);
  static const Color success = Color(0xFF2E9E5B);
  static const Color danger = Color(0xFFE23B3B);
  static const Color warning = Color(0xFFF2A93B);
  static const Color bg = Color(0xFFFBFDFE);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFDCE7EE);
  static const Color text = Color(0xFF12314A);
  static const Color textMuted = Color(0xFF5B7282);
}

abstract final class AppTheme {
  static ThemeData get light {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.primaryDark,
      onSecondary: Colors.white,
      error: AppColors.danger,
      onError: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.text,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.bg,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
        titleLarge: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
        bodyMedium: TextStyle(fontSize: 15, color: AppColors.text),
        bodySmall: TextStyle(fontSize: 13, color: AppColors.textMuted),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
      ),
    );
  }
}

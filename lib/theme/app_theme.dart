import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final StateProvider<ThemeMode> themeModeProvider =
    StateProvider<ThemeMode>((Ref ref) => ThemeMode.dark);

class AppTheme {
  static const Color midnightBackground = Color(0xFF0F0F1A);
  static const Color midnightSurface = Color(0xFF1A1A2E);
  static const Color midnightPrimary = Color(0xFF1A1A2E);
  static const Color accent = Color(0xFFE94560);
  static const Color midnightTextPrimary = Color(0xFFF0F0F0);
  static const Color midnightTextSecondary = Color(0xFF8888AA);

  static const Color paperBackground = Color(0xFFF5F0E8);
  static const Color paperSurface = Color(0xFFEDE8DF);
  static const Color paperPrimary = Color(0xFFEDE8DF);
  static const Color paperTextPrimary = Color(0xFF1A1A1A);
  static const Color paperTextSecondary = Color(0xFF666655);

  static ThemeData get midnightTheme {
    const ColorScheme colorScheme = ColorScheme.dark(
      primary: midnightPrimary,
      secondary: accent,
      surface: midnightSurface,
      onPrimary: midnightTextPrimary,
      onSecondary: Colors.white,
      onSurface: midnightTextPrimary,
    );

    final TextTheme baseText = Typography.material2021().white;
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: midnightBackground,
      appBarTheme: const AppBarTheme(toolbarHeight: 0),
      textTheme: _buildTextTheme(
        baseText,
        primaryText: midnightTextPrimary,
        secondaryText: midnightTextSecondary,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      cardTheme: const CardThemeData(
        color: midnightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
  }

  static ThemeData get paperTheme {
    const ColorScheme colorScheme = ColorScheme.light(
      primary: paperPrimary,
      secondary: accent,
      surface: paperSurface,
      onPrimary: paperTextPrimary,
      onSecondary: Colors.white,
      onSurface: paperTextPrimary,
    );

    final TextTheme baseText = Typography.material2021().black;
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: paperBackground,
      appBarTheme: const AppBarTheme(toolbarHeight: 0),
      textTheme: _buildTextTheme(
        baseText,
        primaryText: paperTextPrimary,
        secondaryText: paperTextSecondary,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      cardTheme: const CardThemeData(
        color: paperSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
  }

  static TextTheme _buildTextTheme(
    TextTheme base, {
    required Color primaryText,
    required Color secondaryText,
  }) {
    final TextTheme sansBody = base.apply(
      fontFamily: 'sans-serif',
      bodyColor: primaryText,
      displayColor: primaryText,
    );

    TextStyle? serif(TextStyle? style) => style?.copyWith(fontFamily: 'serif');

    return sansBody.copyWith(
      titleLarge: serif(sansBody.titleLarge),
      titleMedium: serif(sansBody.titleMedium),
      titleSmall: serif(sansBody.titleSmall),
      headlineLarge: serif(sansBody.headlineLarge),
      headlineMedium: serif(sansBody.headlineMedium),
      headlineSmall: serif(sansBody.headlineSmall),
      displayLarge: serif(sansBody.displayLarge),
      displayMedium: serif(sansBody.displayMedium),
      displaySmall: serif(sansBody.displaySmall),
      bodySmall: sansBody.bodySmall?.copyWith(color: secondaryText),
      bodyMedium: sansBody.bodyMedium?.copyWith(color: primaryText),
      bodyLarge: sansBody.bodyLarge?.copyWith(color: primaryText),
      labelMedium: sansBody.labelMedium?.copyWith(color: secondaryText),
    );
  }
}

import 'package:flutter/material.dart';

/// Centralized theme for the Cursor Controller app.
///
/// All color tokens and component themes are defined here so that individual
/// screens and widgets can reference them via `Theme.of(context)` instead of
/// hardcoding hex values.
abstract final class AppTheme {
  // ---------------------------------------------------------------------------
  // Color tokens
  // ---------------------------------------------------------------------------

  static const Color neonGreen = Color(0xFF00E676);
  static const Color darkGreen = Color(0xFF2E7D32);
  static const Color mutedGreen = Color(0xFF1A2E1A);

  static const Color backgroundDark = Color(0xFF0D0D0D);
  static const Color surfaceDark = Color(0xFF121212);
  static const Color surfaceContainerDark = Color(0xFF1A1A1A);

  static const Color textPrimary = Color(0xFFE0E0E0);
  static const Color textMuted = Color(0xFF606060);
  static const Color textSecondary = Color(0xFFB0B0B0);

  // ---------------------------------------------------------------------------
  // ThemeData
  // ---------------------------------------------------------------------------

  /// The single dark theme used throughout the app.
  ///
  /// Built on Material 3 with `colorSchemeSeed` for automatic tonal palette
  /// generation, then overridden where the terminal-green aesthetic requires
  /// specific values.
  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      colorSchemeSeed: neonGreen,
      brightness: Brightness.dark,
    );

    final colorScheme = base.colorScheme.copyWith(
      surface: backgroundDark,
      primary: neonGreen,
      primaryContainer: mutedGreen,
      onPrimaryContainer: neonGreen,
      outline: darkGreen,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: backgroundDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceDark,
        foregroundColor: neonGreen,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surfaceContainerDark,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainerDark,
        hintStyle: const TextStyle(color: textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: neonGreen, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: darkGreen, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: neonGreen, width: 1),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: neonGreen,
          foregroundColor: backgroundDark,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: neonGreen,
        foregroundColor: backgroundDark,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return neonGreen;
            }
            return surfaceContainerDark;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return backgroundDark;
            }
            return textSecondary;
          }),
          side: WidgetStateProperty.all(
            const BorderSide(color: darkGreen, width: 0.5),
          ),
        ),
      ),
    );
  }
}

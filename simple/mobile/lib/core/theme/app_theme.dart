import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static const Color electricBlue = Color(0xFF168BFF);
  static const Color deepBlue = Color(0xFF0A57D5);
  static const Color ink = Color(0xFF05080D);
  static const Color surface = Color(0xFF0C121C);
  static const Color surfaceHigh = Color(0xFF121C2A);

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: electricBlue,
      brightness: Brightness.light,
      surface: const Color(0xFFF4F8FF),
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: const Color(0xFFF4F8FF),
    );
  }

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: electricBlue,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF07366F),
      onPrimaryContainer: Color(0xFFD8E9FF),
      secondary: Color(0xFF68B5FF),
      onSecondary: Color(0xFF001A31),
      surface: surface,
      onSurface: Color(0xFFEAF2FF),
      error: Color(0xFFFF5F66),
      onError: Colors.white,
      outline: Color(0xFF314157),
    );
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: ink,
      appBarTheme: const AppBarTheme(
        backgroundColor: ink,
        foregroundColor: Color(0xFFF2F7FF),
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xFF090E16),
        indicatorColor: Color(0xFF07366F),
        labelTextStyle: WidgetStatePropertyAll(TextStyle(color: Color(0xFFD9E9FF))),
      ),
      dialogTheme: const DialogThemeData(backgroundColor: surfaceHigh),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: surfaceHigh),
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.brightness == Brightness.dark ? surfaceHigh : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.65)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      cardTheme: CardThemeData(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        color: scheme.brightness == Brightness.dark ? surface : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.35)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    );
  }
}

import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

abstract final class FlexShareTheme {
  static const navy = Color(0xFF1E3A8A);
  static const mint = Color(0xFF10B981);
  static const amber = Color(0xFFF59E0B);
  static const alabaster = Color(0xFFF8FAFC);
  static const white = Color(0xFFFFFFFF);
  static const charcoal = Color(0xFF0F172A);
  static const border = Color(0xFFE2E8F0);

  static const cardDecoration = BoxDecoration(
    color: white,
    border: Border.fromBorderSide(BorderSide(color: border)),
    borderRadius: BorderRadius.all(Radius.circular(8)),
    boxShadow: [
      BoxShadow(
        color: Color.fromRGBO(15, 23, 42, 0.05),
        offset: Offset(0, 4),
        blurRadius: 12,
      ),
    ],
  );

  static final light = _lightTheme;

  static final _lightTheme = ThemeData(
    useMaterial3: true,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: alabaster,
    colorScheme: ColorScheme(
      brightness: Brightness.light,
      primary: navy,
      onPrimary: white,
      primaryContainer: Color(0xFFDBEAFE),
      onPrimaryContainer: navy,
      secondary: mint,
      onSecondary: charcoal,
      secondaryContainer: Color(0xFFD1FAE5),
      onSecondaryContainer: Color(0xFF064E3B),
      tertiary: amber,
      onTertiary: charcoal,
      tertiaryContainer: Color(0xFFFEF3C7),
      onTertiaryContainer: Color(0xFF78350F),
      error: Color(0xFFB91C1C),
      onError: white,
      errorContainer: Color(0xFFFEE2E2),
      onErrorContainer: Color(0xFF7F1D1D),
      surface: white,
      onSurface: charcoal,
      onSurfaceVariant: Color(0xFF475569),
      outline: Color(0xFF94A3B8),
      outlineVariant: border,
      shadow: charcoal,
      scrim: charcoal,
      inverseSurface: charcoal,
      onInverseSurface: alabaster,
      inversePrimary: Color(0xFFBFDBFE),
      surfaceTint: navy,
    ),
    textTheme: const TextTheme(
      displayLarge: TextStyle(color: charcoal, fontWeight: FontWeight.w700),
      displayMedium: TextStyle(color: charcoal, fontWeight: FontWeight.w700),
      displaySmall: TextStyle(color: charcoal, fontWeight: FontWeight.w700),
      headlineLarge: TextStyle(color: charcoal, fontWeight: FontWeight.w700),
      headlineMedium: TextStyle(color: charcoal, fontWeight: FontWeight.w700),
      headlineSmall: TextStyle(color: charcoal, fontWeight: FontWeight.w700),
      titleLarge: TextStyle(color: charcoal, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: charcoal, fontWeight: FontWeight.w600),
      titleSmall: TextStyle(color: charcoal, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: charcoal),
      bodyMedium: TextStyle(color: charcoal),
      bodySmall: TextStyle(color: Color(0xFF475569)),
      labelLarge: TextStyle(color: charcoal, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(color: charcoal, fontWeight: FontWeight.w500),
      labelSmall: TextStyle(color: Color(0xFF475569)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: navy,
      foregroundColor: white,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: white),
      titleTextStyle: TextStyle(
        color: white,
        fontFamily: 'Inter',
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: const CardThemeData(
      color: white,
      elevation: 1,
      shadowColor: Color.fromRGBO(15, 23, 42, 0.05),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: border),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: navy,
        foregroundColor: white,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: navy,
        foregroundColor: white,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: navy,
        minimumSize: const Size(48, 48),
        side: const BorderSide(color: border),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: alabaster,
      selectedColor: Color(0xFFD1FAE5),
      side: BorderSide(color: border),
      shape: StadiumBorder(),
      labelStyle: TextStyle(color: charcoal, fontWeight: FontWeight.w500),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: navy, width: 2),
      ),
      labelStyle: const TextStyle(color: Color(0xFF475569)),
      hintStyle: const TextStyle(color: Color(0xFF64748B)),
    ),
    dividerTheme: const DividerThemeData(color: border, thickness: 1),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: white,
      selectedItemColor: navy,
      unselectedItemColor: Color(0xFF64748B),
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: white,
      indicatorColor: Color(0x2910B981),
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: charcoal,
      contentTextStyle: const TextStyle(color: white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );

  static TextStyle priceStyle(TextStyle? base) => (base ?? const TextStyle())
      .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  static BoxDecoration statusPill(Color color) => BoxDecoration(
        color: color.withAlpha(31),
        borderRadius: BorderRadius.circular(999),
      );
}
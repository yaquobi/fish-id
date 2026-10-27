import 'package:flutter/material.dart';

/// ألوان FISH ID من شعار حوات: كحلي عميق وذهبي. لا تُكتب قيم hex داخل الشاشات، فقط من هنا.
abstract final class AppColors {
  static const navy = Color(0xFF0B2236);
  static const navyDeep = Color(0xFF061624);
  static const navyLight = Color(0xFF14375A);
  static const gold = Color(0xFFF2C14E);
  static const ground = Color(0xFFF4F7FA);
  static const surface = Color(0xFFFFFFFF);
  static const line = Color(0xFFDCE5EC);
  static const ink = Color(0xFF0B1B2A);
  static const muted = Color(0xFF5A6B7A);
  static const onNavyMuted = Color(0xFFA9C7E2);
  static const good = Color(0xFF16A34A);
  static const warn = Color(0xFFD97706);
  static const bad = Color(0xFFDC2626);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Tajawal',
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.navy, primary: AppColors.navy, secondary: AppColors.gold, surface: AppColors.surface),
    scaffoldBackgroundColor: AppColors.ground,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.navy,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(fontFamily: 'Tajawal', fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppColors.line)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        textStyle: const TextStyle(fontFamily: 'Tajawal', fontSize: 17, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontFamily: 'Tajawal', fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

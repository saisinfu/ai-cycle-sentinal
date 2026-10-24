import 'package:flutter/material.dart';

import '../data/config.dart';
import '../data/zone.dart';

abstract final class AppColors {
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF1E1E1E);
  static const sunken = Color(0xFF161616);
  static const raised = Color(0xFF262626);
  static const line = Color(0xFF2E2E2E);
  static const green = Color(0xFF00E676);
  static const yellow = Color(0xFFFFD600);
  static const red = Color(0xFFFF5252);
  static const text = Color(0xFFF5F5F5);
  static const muted = Color(0xFFA0A0A0);

  // Provenance tags (never reuse status colours).
  static const tagData = Color(0xFF8AB4F8);
  static const tagCalc = Color(0xFFC3A6FF);
}

Color zoneColor(Zone z) => switch (z) {
      Zone.expansion => AppColors.green,
      Zone.earlyWarning => AppColors.yellow,
      Zone.digestion => AppColors.red,
    };

String zoneLabel(Zone z) => switch (z) {
      Zone.expansion => 'EXPANSION · ขยายตัว',
      Zone.earlyWarning => 'EARLY WARNING · เตือนล่วงหน้า',
      Zone.digestion => 'DIGESTION · ย่อยการลงทุน',
    };

String levelTh(Zone z) => switch (z) {
      Zone.expansion => 'แข็งแรง',
      Zone.earlyWarning => 'เฝ้าระวัง',
      Zone.digestion => 'อ่อนแอ',
    };

Color actionColor(StockAction a) => switch (a) {
      StockAction.buyDca || StockAction.overweightDca || StockAction.accumulate => AppColors.green,
      StockAction.pauseDca || StockAction.hold => AppColors.yellow,
      StockAction.reduceHoldings => AppColors.red,
    };

IconData sectorIcon(String icon) => switch (icon) {
      'chip' => Icons.memory_outlined,
      'bank' => Icons.account_balance_outlined,
      'health' => Icons.monitor_heart_outlined,
      'space' => Icons.rocket_launch_outlined,
      _ => Icons.insights,
    };

String confidenceTh(String c) => switch (c) {
      'high' => 'ความมั่นใจสูง',
      'low' => 'ความมั่นใจต่ำ',
      _ => 'ความมั่นใจปานกลาง',
    };

ThemeData buildTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.text,
      secondary: AppColors.green,
      error: AppColors.red,
      surface: AppColors.surface,
      onSurface: AppColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    dividerColor: AppColors.line,
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.sunken,
      indicatorColor: AppColors.raised,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
          color: states.contains(WidgetState.selected) ? AppColors.text : AppColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: states.contains(WidgetState.selected) ? AppColors.text : AppColors.muted),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.sunken,
      border: OutlineInputBorder(borderSide: BorderSide(color: AppColors.line)),
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.line)),
      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.muted)),
      isDense: true,
    ),
    textTheme: base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
  );
}

import 'package:flutter/material.dart';

import '../data/engine.dart';

abstract final class AppColors {
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF1E1E1E);
  static const raised = Color(0xFF262626);
  static const line = Color(0xFF2E2E2E);
  static const green = Color(0xFF00E676);
  static const yellow = Color(0xFFFFD600);
  static const red = Color(0xFFFF5252);
  static const text = Color(0xFFF5F5F5);
  static const muted = Color(0xFFA0A0A0);
}

Color zoneColor(Zone z) => switch (z) {
      Zone.expansion => AppColors.green,
      Zone.earlyWarning => AppColors.yellow,
      Zone.digestion => AppColors.red,
    };

String zoneTh(Zone z) => switch (z) {
      Zone.expansion => 'ขยายตัว',
      Zone.earlyWarning => 'เตือนล่วงหน้า',
      Zone.digestion => 'ช่วงย่อยการลงทุน',
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
      StockAction.pauseDca => AppColors.yellow,
      StockAction.reduceHoldings => AppColors.red,
    };

String actionTh(StockAction a) => switch (a) {
      StockAction.buyDca => 'ซื้อแบบ DCA',
      StockAction.pauseDca => 'พัก DCA / ถือไว้',
      StockAction.overweightDca => 'เพิ่มน้ำหนัก DCA',
      StockAction.reduceHoldings => 'ลดสัดส่วน',
      StockAction.accumulate => 'ถือ / สะสม',
    };

const statusCopy = {
  Zone.expansion: (
    'สัญญาณความต้องการ AI แข็งแรงทั้งชิป GPU และการใช้งานองค์กร ลงทุนแบบ DCA ตามปกติ',
    'Demand signals are strong across chips, GPUs and enterprise usage. Regular DCA applies.',
  ),
  Zone.earlyWarning: (
    'การลงทุนเริ่มเร็วกว่ารายได้ และความตึงตัวของซัพพลายเชนผ่อนคลายลง ชะลอการซื้อหุ้นชิป เน้นโครงสร้างพื้นฐานพลังงาน',
    'Spending is outpacing monetization and supply-chain tightness is easing. Slow new semis buying; favor power infrastructure.',
  ),
  Zone.digestion: (
    'หลายสัญญาณชี้ว่าเข้าสู่ช่วงย่อยการลงทุน AI พิจารณาลดสัดส่วนหุ้นชิป โครงสร้างพื้นฐานพลังงานยังเป็นขาป้องกัน',
    'Multiple signals point to an AI CapEx digestion phase. Review trims on semis; power infrastructure remains the defensive leg.',
  ),
};

const _monthsShort = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
const _monthsLong = [
  'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
  'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
];

/// "16 ต.ค."
String thDate(String iso) {
  final d = parseDate(iso);
  return '${d.day} ${_monthsShort[d.month - 1]}';
}

/// "16 ตุลาคม 2569"
String thDateLong(String iso) {
  final d = parseDate(iso);
  return '${d.day} ${_monthsLong[d.month - 1]} ${d.year + 543}';
}

ThemeData buildTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.green,
      secondary: AppColors.yellow,
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
    textTheme: base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
  );
}

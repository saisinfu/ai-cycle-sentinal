/// Flexible monthly budget: base amount + cash reserve, with concentration guardrails.
///
/// Each line (main-port asset or sector stock) gets base x multiplier from how far it trades
/// below its 52-week high. Guardrails (council review, Nov 2026):
/// - single companies are capped at x1.5; funds/ETFs may go to x2.5
/// - one company may not take more than [stockCapPct] % of the month's investable budget
/// - at most 1/6 of the reserve (plus this month's savings) is spent per month
/// - the reserve is not touched while the emergency fund is below its target
/// - with holdings entered, the base is tilted toward lines below their target weight
/// Rules and their backtest: backtest/dynamic_budget.py.
library;

import 'budget.dart';
import 'config.dart';
import 'models.dart';

enum FlexMode { off, dipOnly, gentle }

String flexModeKey(FlexMode m) => switch (m) { FlexMode.off => 'off', FlexMode.dipOnly => 'dip_only', FlexMode.gentle => 'gentle' };

FlexMode flexModeFrom(String? s) => switch (s) { 'off' => FlexMode.off, 'gentle' => FlexMode.gentle, _ => FlexMode.dipOnly };

String flexModeName(FlexMode m) => switch (m) {
      FlexMode.off => 'คงที่ทุกเดือน (DCA ปกติ)',
      FlexMode.dipOnly => 'ยืดหยุ่นเบา: ซื้อเพิ่มเมื่อย่อ',
      FlexMode.gentle => 'ยืดหยุ่นมาก: ลดตอนแพง เพิ่มตอนย่อ',
    };

String flexModeHelp(FlexMode m) => switch (m) {
      FlexMode.off => 'ลงเท่ากันทุกเดือนตามงบฐาน ไม่ใช้เงินสำรอง (เงินสดตามกฎหมวดยังเก็บไว้)',
      FlexMode.dipOnly => 'ปกติลง 90% ของงบฐาน กันไว้ 10% · ราคาต่ำกว่าจุดสูงสุด 10–20% ลง 1.5 เท่า · ต่ำกว่าเกิน 20% ลง 2.5 เท่าสำหรับกองทุน (หุ้นรายตัวสูงสุด 1.5 เท่า)',
      FlexMode.gentle => 'ใกล้จุดสูงสุด ลง 0.8 เท่า · −10 ถึง −20% ลง 1.5 เท่า · −20 ถึง −30% ลง 2 เท่า · เกิน −30% ลง 3 เท่าสำหรับกองทุน (หุ้นรายตัวสูงสุด 1.5 เท่า)',
    };

const singleStockMaxMultiplier = 1.5;

/// Same steps as backtest/dynamic_budget.py ("dip_only" and "gentle"); single companies capped.
double flexMultiplier(FlexMode mode, double? drawdownPct, {bool isFund = true}) {
  if (mode == FlexMode.off || drawdownPct == null) return 1.0;
  final dd = drawdownPct;
  final m = switch (mode) {
    FlexMode.dipOnly => dd > -10 ? 0.9 : dd > -20 ? 1.5 : 2.5,
    FlexMode.gentle => dd > -5 ? 0.8 : dd > -10 ? 1.0 : dd > -20 ? 1.5 : dd > -30 ? 2.0 : 3.0,
    FlexMode.off => 1.0,
  };
  return isFund ? m : (m > singleStockMaxMultiplier ? singleStockMaxMultiplier : m);
}

class FlexLine {
  const FlexLine({
    required this.key,
    required this.label,
    required this.ticker,
    required this.base,
    required this.multiplier,
    required this.planned,
    required this.isFund,
    this.drawdown,
    this.capped = false,
    this.tilt = 1.0,
  });

  /// 'main:<key>' or '<sectorId>:<ticker>'
  final String key;
  final String label;
  final String? ticker;

  /// Base after the rebalancing tilt.
  final double base;
  final double multiplier;
  final double planned;
  final bool isFund;
  final double? drawdown;

  /// Held back by the per-company ceiling.
  final bool capped;

  /// Rebalancing factor applied to the base (1 = none).
  final double tilt;
}

class FlexPlan {
  const FlexPlan({
    required this.mode,
    required this.baseTotal,
    required this.plannedTotal,
    required this.saved,
    required this.used,
    required this.reserveBefore,
    required this.reserveAfter,
    required this.capAmount,
    required this.shortfall,
    required this.lines,
    required this.stockCapPct,
    this.emergencyBlocked = false,
    this.paceLimited = false,
    this.monthsLeft,
    this.rebalanced = false,
  });

  final FlexMode mode;
  final double baseTotal;
  final double plannedTotal;
  final double saved;
  final double used;
  final double reserveBefore;
  final double reserveAfter;
  final double capAmount;
  final double shortfall;
  final Map<String, FlexLine> lines;
  final double stockCapPct;

  /// Reserve left untouched because the emergency fund is short.
  final bool emergencyBlocked;

  /// Spending limited to 1/6 of the reserve this month.
  final bool paceLimited;

  /// How many months of today's dip-buying the reserve would cover.
  final double? monthsLeft;
  final bool rebalanced;

  FlexLine? line(String key) => lines[key];
}

FlexPlan buildFlex({
  required BudgetPlan plan,
  required List<MainAsset> mainAssets,
  required MarketData market,
  required FlexMode mode,
  required double reserve,
  required double capMonths,
  double stockCapPct = 15,
  bool emergencyOk = true,
  Map<String, double> targetTilt = const {},
}) {
  final items = <({String key, String label, String? ticker, double base, bool isFund})>[];
  for (final (i, l) in plan.mainLines.indexed) {
    final a = i < mainAssets.length ? mainAssets[i] : null;
    items.add((key: 'main:${a?.key ?? i}', label: l.label, ticker: a?.proxy, base: l.amount, isFund: a?.isFund ?? true));
  }
  var cashParts = plan.unassignedTech;
  for (final sb in plan.sectors) {
    for (final l in sb.lines) {
      final isFund = sb.vm.config.stocks.where((s) => s.ticker == l.label).firstOrNull?.isFund ?? false;
      items.add((key: '${sb.vm.config.id}:${l.label}', label: l.label, ticker: l.label, base: l.amount, isFund: isFund));
    }
    cashParts += sb.cash;
  }

  final baseTotal = plan.main + plan.tech;
  final itemsBase = items.fold(0.0, (a, b) => a + b.base);

  // Rebalancing tilt: scale bases by target/actual, then renormalise to the same total.
  final tiltRaw = {for (final it in items) it.key: targetTilt[it.key] ?? 1.0};
  final tiltedSum = items.fold(0.0, (a, b) => a + b.base * tiltRaw[b.key]!);
  final norm = tiltedSum > 0 ? itemsBase / tiltedSum : 1.0;
  final base = {for (final it in items) it.key: it.base * tiltRaw[it.key]! * norm};
  final rebalanced = targetTilt.isNotEmpty && targetTilt.values.any((t) => (t - 1).abs() > 0.01);

  final dd = <String, double?>{};
  final mult = <String, double>{};
  var saved = cashParts, need = 0.0;
  for (final it in items) {
    final d = it.ticker == null ? null : market.quotes[it.ticker!]?.drawdownPct;
    final b = base[it.key]!;
    final m = b > 0 ? flexMultiplier(mode, d, isFund: it.isFund) : 1.0;
    dd[it.key] = d;
    mult[it.key] = m;
    if (m < 1) saved += b * (1 - m);
    if (m > 1) need += b * (m - 1);
  }

  // Per-company ceiling on the extra.
  final stockCap = stockCapPct > 0 ? baseTotal * stockCapPct / 100 : double.infinity;
  final extraWanted = <String, double>{};
  final capped = <String>{};
  var needCapped = 0.0;
  for (final it in items) {
    final b = base[it.key]!, m = mult[it.key]!;
    var extra = m > 1 ? b * (m - 1) : 0.0;
    if (!it.isFund && b + extra > stockCap) {
      extra = (stockCap - b).clamp(0.0, extra).toDouble();
      capped.add(it.key);
    }
    extraWanted[it.key] = extra;
    needCapped += extra;
  }

  // How much reserve may be spent this month.
  final pace = reserve / 6;
  var available = mode == FlexMode.off || !emergencyOk ? saved : pace + saved;
  if (mode != FlexMode.off && available > reserve + saved) available = reserve + saved;
  final scale = needCapped <= 0 ? 1.0 : (available >= needCapped ? 1.0 : (available <= 0 ? 0.0 : available / needCapped));
  final used = needCapped * scale;
  var after = reserve + saved - used;
  final cap = capMonths > 0 ? capMonths * baseTotal : double.infinity;

  final planned = <String, double>{};
  for (final it in items) {
    final b = base[it.key]!, m = mult[it.key]!;
    planned[it.key] = m >= 1 ? b + extraWanted[it.key]! * scale : b * m;
  }
  if (after > cap && itemsBase > 0) {
    final surplus = after - cap;
    for (final it in items) {
      planned[it.key] = planned[it.key]! + surplus * base[it.key]! / itemsBase;
    }
    after = cap;
  }

  final lines = <String, FlexLine>{
    for (final it in items)
      it.key: FlexLine(
        key: it.key,
        label: it.label,
        ticker: it.ticker,
        base: base[it.key]!,
        multiplier: mult[it.key]!,
        planned: planned[it.key]!,
        isFund: it.isFund,
        drawdown: dd[it.key],
        capped: capped.contains(it.key),
        tilt: tiltRaw[it.key]! * norm,
      ),
  };
  return FlexPlan(
    mode: mode,
    baseTotal: baseTotal,
    plannedTotal: planned.values.fold(0.0, (a, b) => a + b),
    saved: saved,
    used: used,
    reserveBefore: reserve,
    reserveAfter: after,
    capAmount: cap,
    shortfall: needCapped - used,
    lines: lines,
    stockCapPct: stockCapPct,
    emergencyBlocked: mode != FlexMode.off && !emergencyOk && reserve > 0 && needCapped > saved,
    paceLimited: mode != FlexMode.off && emergencyOk && needCapped > pace + saved && reserve > pace,
    monthsLeft: needCapped > 0 && mode != FlexMode.off ? after / needCapped : null,
    rebalanced: rebalanced,
  );
}

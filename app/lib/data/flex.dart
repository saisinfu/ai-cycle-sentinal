/// Flexible monthly budget: base amount + cash reserve.
///
/// Each line (main-port asset or sector stock) gets base x multiplier, where the
/// multiplier depends on how far that asset trades below its 52-week high. Money not
/// invested goes to the reserve; extra buys after falls come from the reserve and are
/// scaled down if the reserve is short. Above the cap (months of base budget) the
/// surplus is invested right away. Rules and their backtest: backtest/dynamic_budget.py.
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
      FlexMode.off => 'ลงเท่ากันทุกเดือนตามงบฐาน ไม่ใช้เงินสำรอง',
      FlexMode.dipOnly => 'ปกติลง 90% ของงบฐาน กันไว้ 10% · ราคาต่ำกว่าจุดสูงสุด 10–20% ลง 1.5 เท่า · ต่ำกว่าเกิน 20% ลง 2.5 เท่า (ใช้เงินสำรอง)',
      FlexMode.gentle => 'ใกล้จุดสูงสุด (ไม่ถึง −5%) ลง 0.8 เท่า · −5 ถึง −10% ลง 1 เท่า · −10 ถึง −20% ลง 1.5 เท่า · −20 ถึง −30% ลง 2 เท่า · เกิน −30% ลง 3 เท่า',
    };

/// Same steps as backtest/dynamic_budget.py ("dip_only" and "gentle").
double flexMultiplier(FlexMode mode, double? drawdownPct) {
  if (mode == FlexMode.off || drawdownPct == null) return 1.0;
  final dd = drawdownPct;
  return switch (mode) {
    FlexMode.dipOnly => dd > -10 ? 0.9 : dd > -20 ? 1.5 : 2.5,
    FlexMode.gentle => dd > -5 ? 0.8 : dd > -10 ? 1.0 : dd > -20 ? 1.5 : dd > -30 ? 2.0 : 3.0,
    FlexMode.off => 1.0,
  };
}

class FlexLine {
  const FlexLine({
    required this.key,
    required this.label,
    required this.ticker,
    required this.base,
    required this.multiplier,
    required this.planned,
    this.drawdown,
  });

  /// 'main:<key>' or '<sectorId>:<ticker>'
  final String key;
  final String label;
  final String? ticker;
  final double base;
  final double multiplier;
  final double planned;
  final double? drawdown;
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
  });

  final FlexMode mode;

  /// Base budget for main port + sector stocks (tax funds excluded).
  final double baseTotal;
  final double plannedTotal;

  /// Money put into the reserve this month (incl. sector cash parts).
  final double saved;

  /// Reserve money spent this month.
  final double used;
  final double reserveBefore;
  final double reserveAfter;
  final double capAmount;

  /// Extra buying the plan wanted but the reserve could not cover.
  final double shortfall;
  final Map<String, FlexLine> lines;

  FlexLine? line(String key) => lines[key];
}

FlexPlan buildFlex({
  required BudgetPlan plan,
  required List<MainAsset> mainAssets,
  required MarketData market,
  required FlexMode mode,
  required double reserve,
  required double capMonths,
}) {
  final items = <(String key, String label, String? ticker, double base)>[];
  for (final (i, l) in plan.mainLines.indexed) {
    final a = i < mainAssets.length ? mainAssets[i] : null;
    items.add(('main:${a?.key ?? i}', l.label, a?.proxy, l.amount));
  }
  var cashParts = plan.unassignedTech;
  for (final sb in plan.sectors) {
    for (final l in sb.lines) {
      items.add(('${sb.vm.config.id}:${l.label}', l.label, l.label, l.amount));
    }
    cashParts += sb.cash;
  }

  final baseTotal = plan.main + plan.tech;
  final dd = <String, double?>{};
  final mult = <String, double>{};
  var saved = cashParts, need = 0.0;
  for (final (key, _, ticker, base) in items) {
    final d = ticker == null ? null : market.quotes[ticker]?.drawdownPct;
    final m = base > 0 ? flexMultiplier(mode, d) : 1.0;
    dd[key] = d;
    mult[key] = m;
    if (m < 1) saved += base * (1 - m);
    if (m > 1) need += base * (m - 1);
  }
  final available = reserve + saved;
  final scale = need <= 0 ? 1.0 : (available >= need ? 1.0 : (available <= 0 ? 0.0 : available / need));
  final used = need * scale;
  var after = reserve + saved - used;
  final cap = capMonths > 0 ? capMonths * baseTotal : double.infinity;

  final planned = <String, double>{};
  for (final (key, _, _, base) in items) {
    final m = mult[key]!;
    planned[key] = m >= 1 ? base + base * (m - 1) * scale : base * m;
  }
  if (after > cap && baseTotal > 0) {
    final surplus = after - cap;
    for (final (key, _, _, base) in items) {
      planned[key] = planned[key]! + surplus * base / baseTotal;
    }
    after = cap;
  }

  final lines = <String, FlexLine>{
    for (final (key, label, ticker, base) in items)
      key: FlexLine(key: key, label: label, ticker: ticker, base: base, multiplier: mult[key]!, planned: planned[key]!, drawdown: dd[key]),
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
    shortfall: need - used,
    lines: lines,
  );
}

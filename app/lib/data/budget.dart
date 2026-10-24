/// Monthly DCA budget split and Thai personal income tax planner.
///
/// Tax rules (tax year 2569 / 2026), from the Revenue Department as reported by
/// Prudential (8 Oct 2026), Krungsri (16 Jun 2026; SSO 16 Jan 2026):
/// brackets 0/5/10/15/20/25/30/35%, employment expense 50% capped at 100,000,
/// personal allowance 60,000, social security up to 875 x 12 = 10,500,
/// ThaiESG 30% of income up to 300,000, RMF 30% up to 500,000 (RMF is inside
/// the combined 500,000 retirement cap with provident fund etc.),
/// life + health insurance 100,000 combined (health part up to 25,000).
library;

import 'dart:math' as math;

import 'config.dart';
import 'engine.dart';

/* ------------------------------- budget ------------------------------- */

class BudgetLine {
  const BudgetLine({required this.label, required this.amount, required this.note, required this.tag, this.detail});

  final String label;
  final double amount;
  final String note;

  /// 'rule' | 'calc' | 'data' | 'estimate'
  final String tag;
  final String? detail;
}

class SectorBudget {
  const SectorBudget({required this.vm, required this.weightPct, required this.amount, required this.lines, required this.cash});

  final SectorVM vm;
  final double weightPct;
  final double amount;
  final List<BudgetLine> lines;
  final double cash;
}

class BudgetPlan {
  const BudgetPlan({
    required this.total,
    required this.main,
    required this.tech,
    required this.tax,
    required this.mainLines,
    required this.sectors,
    required this.unassignedTech,
  });

  final double total;
  final double main;
  final double tech;
  final double tax;
  final List<BudgetLine> mainLines;
  final List<SectorBudget> sectors;

  /// Tech money not assigned to any sector weight (weights below 100%).
  final double unassignedTech;

  double get techCash => unassignedTech + sectors.fold<double>(0, (a, s) => a + s.cash);
}

String actionLabel(StockAction a) => switch (a) {
      StockAction.buyDca => 'ซื้อแบบ DCA',
      StockAction.pauseDca => 'พัก DCA / ถือไว้',
      StockAction.overweightDca => 'เพิ่มน้ำหนัก DCA',
      StockAction.reduceHoldings => 'ลดสัดส่วน',
      StockAction.accumulate => 'ถือ / สะสม',
      StockAction.hold => 'ถือไว้',
    };

BudgetPlan buildBudget({
  required double salary,
  required double dcaPct,
  required Map<String, double> buckets,
  required Map<String, double> mainSplit,
  required List<MainAsset> mainAssets,
  required Map<String, double> sectorWeights,
  required List<SectorVM> sectors,
}) {
  final total = salary * dcaPct / 100;
  final main = total * (buckets['main'] ?? 0) / 100;
  final tech = total * (buckets['tech'] ?? 0) / 100;
  final tax = total * (buckets['tax'] ?? 0) / 100;

  final mainLines = [
    for (final a in mainAssets)
      BudgetLine(
        label: a.name,
        amount: main * (mainSplit[a.key] ?? 0) / 100,
        note: '${(mainSplit[a.key] ?? 0).toStringAsFixed(0)}% ของพอร์ตหลัก · DCA สม่ำเสมอ ไม่ปรับตามวัฏจักร',
        tag: 'rule',
      ),
  ];

  var assigned = 0.0;
  final sectorBudgets = <SectorBudget>[];
  for (final vm in sectors) {
    final w = sectorWeights[vm.config.id] ?? 0;
    if (w <= 0) continue;
    assigned += w;
    final amount = tech * w / 100;
    final zone = vm.latest.zone;
    final lines = <BudgetLine>[];
    var spent = 0.0;
    for (final r in vm.recommendations) {
      final baht = amount * r.cell.allocationPct / 100;
      spent += baht;
      final why = r.cell.action == StockAction.reduceHoldings
          ? 'หมวด${zoneName(zone)} → กฎให้ทบทวนลด ${r.cell.trimPct?.toStringAsFixed(0) ?? '0'}% ของหุ้นที่ถือ'
          : r.cell.allocationPct > 0
              ? 'หมวด${zoneName(zone)} → กฎให้ ${r.cell.allocationPct.toStringAsFixed(0)}% ของงบหมวดนี้'
              : 'หมวด${zoneName(zone)} → กฎให้${actionLabel(r.cell.action)}';
      lines.add(BudgetLine(label: r.stock.ticker, amount: baht, note: why, tag: 'rule', detail: actionLabel(r.cell.action)));
    }
    sectorBudgets.add(SectorBudget(vm: vm, weightPct: w, amount: amount, lines: lines, cash: math.max(0.0, amount - spent)));
  }
  final unassigned = tech * math.max(0.0, 100 - assigned) / 100;

  return BudgetPlan(
    total: total,
    main: main,
    tech: tech,
    tax: tax,
    mainLines: mainLines,
    sectors: sectorBudgets,
    unassignedTech: unassigned,
  );
}

/* --------------------------------- tax --------------------------------- */

const taxBrackets = <(double, double)>[
  (150000, 0),
  (300000, 0.05),
  (500000, 0.10),
  (750000, 0.15),
  (1000000, 0.20),
  (2000000, 0.25),
  (5000000, 0.30),
  (double.infinity, 0.35),
];

double thaiTax(double net) {
  var tax = 0.0, lower = 0.0;
  for (final (upper, rate) in taxBrackets) {
    if (net <= lower) break;
    tax += (math.min(net, upper) - lower) * rate;
    lower = upper;
  }
  return tax;
}

double marginalRate(double net) {
  for (final (upper, rate) in taxBrackets) {
    if (net <= upper) return rate;
  }
  return 0.35;
}

class TaxInput {
  const TaxInput({
    required this.monthlySalary,
    required this.bonusMonths,
    required this.lifeInsurance,
    required this.healthInsurance,
    required this.providentFund,
    required this.otherDeductions,
    required this.esgBought,
    required this.rmfBought,
    required this.targetNet,
  });

  final double monthlySalary;
  final double bonusMonths;
  final double lifeInsurance;
  final double healthInsurance;
  final double providentFund;
  final double otherDeductions;
  final double esgBought;
  final double rmfBought;
  final double targetNet;
}

class TaxResult {
  const TaxResult({
    required this.income,
    required this.expense,
    required this.personal,
    required this.sso,
    required this.insurance,
    required this.otherDeductions,
    required this.fundsBought,
    required this.net,
    required this.tax,
    required this.needed,
    required this.esgRoom,
    required this.rmfRoom,
    required this.suggestEsg,
    required this.suggestRmf,
    required this.taxAfter,
  });

  final double income;
  final double expense;
  final double personal;
  final double sso;
  final double insurance;
  final double otherDeductions;
  final double fundsBought;
  final double net;
  final double tax;
  final double needed;
  final double esgRoom;
  final double rmfRoom;
  final double suggestEsg;
  final double suggestRmf;
  final double taxAfter;

  double get saved => tax - taxAfter;
  double get uncovered => math.max(0.0, needed - suggestEsg - suggestRmf);
}

TaxResult planTax(TaxInput i) {
  final income = i.monthlySalary * (12 + i.bonusMonths);
  final expense = math.min(income * 0.5, 100000.0);
  const personal = 60000.0;
  final sso = math.min(i.monthlySalary, 17500.0) * 0.05 * 12;
  final health = math.min(i.healthInsurance, 25000.0);
  final insurance = math.min(i.lifeInsurance + health, 100000.0);
  final pvd = math.min(i.providentFund, math.min(income * 0.15, 500000.0));
  final esgCap = math.min(income * 0.30, 300000.0);
  final esgUsed = math.min(i.esgBought, esgCap);
  final retirementCap = math.max(0.0, 500000 - pvd);
  final rmfCap = math.min(income * 0.30, retirementCap);
  final rmfUsed = math.min(i.rmfBought, rmfCap);
  final other = pvd + i.otherDeductions;
  final fundsBought = esgUsed + rmfUsed;

  final net = math.max(0.0, income - expense - personal - sso - insurance - other - fundsBought);
  final tax = thaiTax(net);
  final needed = math.max(0.0, net - i.targetNet);
  final esgRoom = math.max(0.0, esgCap - esgUsed);
  final rmfRoom = math.max(0.0, rmfCap - rmfUsed);
  final suggestEsg = math.min(needed, esgRoom);
  final suggestRmf = math.min(needed - suggestEsg, rmfRoom);
  final taxAfter = thaiTax(net - suggestEsg - suggestRmf);
  return TaxResult(
    income: income,
    expense: expense,
    personal: personal,
    sso: sso,
    insurance: insurance,
    otherDeductions: other,
    fundsBought: fundsBought,
    net: net,
    tax: tax,
    needed: needed,
    esgRoom: esgRoom,
    rmfRoom: rmfRoom,
    suggestEsg: suggestEsg,
    suggestRmf: suggestRmf,
    taxAfter: taxAfter,
  );
}

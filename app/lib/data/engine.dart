/// Scoring engine, hysteresis and decision matrix.
///
/// Identical rules to the Claude web dashboard and the daily update task:
/// clamped linear 0-100 per signal, weighted sum, bands 70 / 40 with a ±3
/// dead-band so a score hovering on a boundary does not flip status.
library;

import 'dart:math' as math;

import 'models.dart';

enum Zone { expansion, earlyWarning, digestion }

const double expansionThreshold = 70;
const double digestionThreshold = 40;
const double hysteresisBand = 3;

double _r1(double v) => (v * 10).roundToDouble() / 10;
double _r2(double v) => (v * 100).roundToDouble() / 100;

String signed(double v, [int digits = 1]) {
  final s = v.abs().toStringAsFixed(digits);
  if (double.parse(s) == 0) return s;
  return v > 0 ? '+$s' : '−$s';
}

class SignalSpec {
  const SignalSpec({
    required this.key,
    required this.label,
    required this.th,
    required this.short,
    required this.weight,
    required this.field,
    required this.worst,
    required this.best,
    required this.format,
  });

  final String key;
  final String label;
  final String th;
  final String short;
  final double weight;
  final String field;
  final double worst;
  final double best;
  final String Function(Reading r) format;
}

final List<SignalSpec> signals = [
  SignalSpec(
    key: 'capex_vs_revenue',
    label: 'Hyperscaler CapEx vs Cloud Revenue',
    th: 'การลงทุน CapEx เทียบรายได้',
    short: 'CapEx / รายได้',
    weight: 0.25,
    field: 'capex_to_cloud_revenue_ratio',
    worst: 2.0,
    best: 0.8,
    format: (r) => '${r.ind('capex_to_cloud_revenue_ratio').toStringAsFixed(2)} เท่า (CapEx ÷ รายได้คลาวด์)',
  ),
  SignalSpec(
    key: 'chip_lead_time',
    label: 'AI Chip Lead Time',
    th: 'ระยะรอชิป / งานค้างส่ง',
    short: 'ระยะรอชิป',
    weight: 0.20,
    field: 'chip_lead_time_weeks',
    worst: 8,
    best: 30,
    format: (r) => '${r.ind('chip_lead_time_weeks').toStringAsFixed(0)} สัปดาห์',
  ),
  SignalSpec(
    key: 'gpu_spot_price',
    label: 'GPU Spot Rental (H100 index)',
    th: 'ราคาเช่า GPU',
    short: 'ราคาเช่า GPU',
    weight: 0.20,
    field: 'gpu_spot_price_change_1m_pct',
    worst: -20,
    best: 10,
    format: (r) =>
        '\$${r.ind('gpu_spot_price_usd_hr').toStringAsFixed(2)}/ชม. (${signed(r.ind('gpu_spot_price_change_1m_pct'))}% ใน 1 เดือน)',
  ),
  SignalSpec(
    key: 'enterprise_adoption',
    label: 'Enterprise AI Adoption (Ramp AI Index)',
    th: 'การใช้งาน AI ในองค์กร',
    short: 'การใช้งานองค์กร',
    weight: 0.15,
    field: 'enterprise_ai_adoption_change_3m_pp',
    worst: -3,
    best: 3,
    format: (r) =>
        '${r.ind('enterprise_ai_adoption_pct').toStringAsFixed(1)}% ใช้ AI (${signed(r.ind('enterprise_ai_adoption_change_3m_pp'))} จุดใน 3 เดือน)',
  ),
  SignalSpec(
    key: 'power_grid',
    label: 'Power Grid Stress',
    th: 'คอขวดโครงข่ายไฟฟ้า',
    short: 'โครงข่ายไฟฟ้า',
    weight: 0.20,
    field: 'power_grid_stress_level',
    worst: 9,
    best: 2,
    format: (r) => '${r.ind('power_grid_stress_level').toStringAsFixed(1)}/10',
  ),
];

SignalSpec specFor(String key) => signals.firstWhere((s) => s.key == key);

double linearScore(double v, double worst, double best) =>
    _r1(((v - worst) / (best - worst) * 100).clamp(0, 100).toDouble());

Zone levelOf(double score) => classify(score);

Zone classify(double x) => x >= expansionThreshold
    ? Zone.expansion
    : x >= digestionThreshold
        ? Zone.earlyWarning
        : Zone.digestion;

Zone classifyWithHysteresis(double x, Zone? prev) {
  if (prev == null) return classify(x);
  final upper = prev == Zone.expansion ? expansionThreshold - hysteresisBand : expansionThreshold + hysteresisBand;
  final lower = prev == Zone.digestion ? digestionThreshold + hysteresisBand : digestionThreshold - hysteresisBand;
  if (x >= upper) return Zone.expansion;
  if (x < lower) return Zone.digestion;
  return Zone.earlyWarning;
}

class SubScore {
  const SubScore({required this.spec, required this.score, required this.weighted, required this.display});

  final SignalSpec spec;
  final double score;
  final double weighted;
  final String display;

  Zone get level => levelOf(score);
}

class Scored {
  const Scored({required this.reading, required this.index, required this.subs, required this.zone});

  final Reading reading;
  final double index;
  final List<SubScore> subs;
  final Zone zone;
}

({double index, List<SubScore> subs}) scoreReading(Reading r) {
  final subs = [
    for (final s in signals)
      () {
        final score = linearScore(r.ind(s.field), s.worst, s.best);
        return SubScore(spec: s, score: score, weighted: _r2(score * s.weight), display: s.format(r));
      }(),
  ];
  final index = _r1(subs.fold<double>(0, (a, s) => a + s.score * s.spec.weight));
  return (index: index, subs: subs);
}

List<Scored> scoreAll(List<Reading> readings) {
  final sorted = [...readings]..sort((a, b) => a.date.compareTo(b.date));
  Zone? prev;
  final out = <Scored>[];
  for (final r in sorted) {
    final s = scoreReading(r);
    final zone = classifyWithHysteresis(s.index, prev);
    prev = zone;
    out.add(Scored(reading: r, index: s.index, subs: s.subs, zone: zone));
  }
  return out;
}

/* ----------------------------- attribution ----------------------------- */

class Contribution {
  const Contribution({required this.spec, required this.delta});

  final SignalSpec spec;
  final double delta;
}

class Attribution {
  const Attribution({
    required this.fromDate,
    required this.fromScore,
    required this.toScore,
    required this.contributions,
  });

  final String fromDate;
  final double fromScore;
  final double toScore;
  final List<Contribution> contributions;

  double get change => _r1(toScore - fromScore);
}

DateTime parseDate(String d) => DateTime.utc(int.parse(d.substring(0, 4)), int.parse(d.substring(5, 7)), int.parse(d.substring(8, 10)));

Attribution? attributionFor(List<Scored> scored, int days) {
  if (scored.length < 2) return null;
  final last = scored.last;
  final cutoff = parseDate(last.reading.date).subtract(Duration(days: days));
  Scored? base;
  for (final s in scored.reversed) {
    if (!parseDate(s.reading.date).isAfter(cutoff)) {
      base = s;
      break;
    }
  }
  if (base == null) return null;
  final contributions = [
    for (var i = 0; i < last.subs.length; i++)
      Contribution(spec: last.subs[i].spec, delta: _r2(last.subs[i].weighted - base.subs[i].weighted)),
  ]..sort((a, b) => b.delta.abs().compareTo(a.delta.abs()));
  return Attribution(fromDate: base.reading.date, fromScore: base.index, toScore: last.index, contributions: contributions);
}

/* --------------------------- decision matrix --------------------------- */

enum StockAction { buyDca, pauseDca, overweightDca, reduceHoldings, accumulate }

class PriceZone {
  const PriceZone(this.label, this.low, this.high);

  final String label;
  final double low;
  final double high;
}

class Recommendation {
  const Recommendation({
    required this.ticker,
    required this.name,
    required this.action,
    required this.allocationPct,
    required this.trimPct,
    required this.referencePrice,
    required this.zones,
  });

  final String ticker;
  final String name;
  final StockAction action;
  final double allocationPct;
  final double? trimPct;
  final double referencePrice;
  final List<PriceZone> zones;
}

const _names = {'KLAC': 'KLA Corporation', 'AVGO': 'Broadcom Inc.', 'ETN': 'Eaton Corporation plc'};

const Map<Zone, Map<String, (StockAction, double, double?)>> _matrix = {
  Zone.expansion: {
    'KLAC': (StockAction.buyDca, 25.0, null),
    'AVGO': (StockAction.buyDca, 40.0, null),
    'ETN': (StockAction.buyDca, 35.0, null),
  },
  Zone.earlyWarning: {
    'KLAC': (StockAction.pauseDca, 0.0, null),
    'AVGO': (StockAction.pauseDca, 0.0, null),
    'ETN': (StockAction.overweightDca, 50.0, null),
  },
  Zone.digestion: {
    'KLAC': (StockAction.reduceHoldings, 0.0, 30.0),
    'AVGO': (StockAction.reduceHoldings, 0.0, 20.0),
    'ETN': (StockAction.accumulate, 60.0, null),
  },
};

const Map<StockAction, List<(String, double, double)>> _zoneTemplates = {
  StockAction.buyDca: [('โซน DCA', 0.92, 1.00), ('โซนซื้อเพิ่มเมื่อย่อ', 0.85, 0.92)],
  StockAction.overweightDca: [('โซน DCA', 0.93, 1.02), ('โซนซื้อเพิ่มเมื่อย่อ', 0.86, 0.93)],
  StockAction.accumulate: [('โซนสะสม', 0.88, 0.98), ('โซนราคาถูกมาก', 0.80, 0.88)],
  StockAction.pauseDca: [('โซนรอกลับเข้าซื้อ', 0.82, 0.90)],
  StockAction.reduceHoldings: [('โซนทยอยขายเมื่อราคาขึ้น', 1.00, 1.08), ('โซนรอกลับเข้าซื้อ', 0.75, 0.85)],
};

class ActionsResult {
  const ActionsResult(this.recommendations, this.cashReservePct);

  final List<Recommendation> recommendations;
  final double cashReservePct;
}

ActionsResult buildActions(Zone zone, Map<String, double> prices) {
  final recs = [
    for (final e in _matrix[zone]!.entries)
      Recommendation(
        ticker: e.key,
        name: _names[e.key]!,
        action: e.value.$1,
        allocationPct: e.value.$2,
        trimPct: e.value.$3,
        referencePrice: prices[e.key] ?? 0,
        zones: [
          for (final z in _zoneTemplates[e.value.$1]!) PriceZone(z.$1, (prices[e.key] ?? 0) * z.$2, (prices[e.key] ?? 0) * z.$3),
        ],
      ),
  ];
  final allocated = recs.fold<double>(0, (a, r) => a + r.allocationPct);
  return ActionsResult(recs, math.max(0.0, 100 - allocated));
}

/* ------------------------------ view model ------------------------------ */

class DashboardVM {
  DashboardVM({required this.live, required this.scored})
      : actions = buildActions(scored.last.zone, scored.last.reading.prices),
        attribution = {7: attributionFor(scored, 7), 30: attributionFor(scored, 30)};

  final bool live;
  final List<Scored> scored;
  final ActionsResult actions;
  final Map<int, Attribution?> attribution;

  Scored get latest => scored.last;
  Zone? get previousZone => scored.length > 1 ? scored[scored.length - 2].zone : null;
}

/* --------------------------- sample scenarios --------------------------- */

const _start = {
  'capex_to_cloud_revenue_ratio': 0.9,
  'chip_lead_time_weeks': 28.0,
  'gpu_spot_price_usd_hr': 2.85,
  'gpu_spot_price_change_1m_pct': 6.0,
  'enterprise_ai_adoption_pct': 62.0,
  'enterprise_ai_adoption_change_3m_pp': 2.5,
  'power_grid_stress_level': 4.0,
};

const Map<String, Map<String, double>> _ends = {
  'expansion': _start,
  'early_warning': {
    'capex_to_cloud_revenue_ratio': 1.5,
    'chip_lead_time_weeks': 22.0,
    'gpu_spot_price_usd_hr': 2.6,
    'gpu_spot_price_change_1m_pct': -5.0,
    'enterprise_ai_adoption_pct': 60.0,
    'enterprise_ai_adoption_change_3m_pp': 0.5,
    'power_grid_stress_level': 6.0,
  },
  'digestion': {
    'capex_to_cloud_revenue_ratio': 1.95,
    'chip_lead_time_weeks': 10.0,
    'gpu_spot_price_usd_hr': 1.6,
    'gpu_spot_price_change_1m_pct': -18.0,
    'enterprise_ai_adoption_pct': 55.0,
    'enterprise_ai_adoption_change_3m_pp': -2.0,
    'power_grid_stress_level': 8.6,
  },
};

const _noise = {
  'capex_to_cloud_revenue_ratio': 0.04,
  'chip_lead_time_weeks': 1.0,
  'gpu_spot_price_usd_hr': 0.08,
  'gpu_spot_price_change_1m_pct': 3.0,
  'enterprise_ai_adoption_pct': 0.4,
  'enterprise_ai_adoption_change_3m_pp': 0.35,
  'power_grid_stress_level': 0.25,
};

/// 90 simulated daily readings drifting from expansion to [scenario].
List<Reading> sampleReadings(String scenario) {
  final end = _ends[scenario] ?? _ends['early_warning']!;
  final rng = math.Random(9);
  double gauss() => (rng.nextDouble() + rng.nextDouble() + rng.nextDouble() - 1.5) * 2;
  final today = DateTime.now().toUtc();
  const days = 90;
  String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return [
    for (var i = 0; i < days; i++)
      () {
        final t = i / (days - 1);
        final ease = 0.5 - 0.5 * math.cos(math.pi * t);
        final ind = <String, double>{};
        for (final k in _start.keys) {
          final a = _start[k]!, b = end[k]!;
          ind[k] = a + (b - a) * ease + gauss() * _noise[k]!;
        }
        ind['power_grid_stress_level'] = ind['power_grid_stress_level']!.clamp(1, 10).toDouble();
        ind['chip_lead_time_weeks'] = math.max(0.0, ind['chip_lead_time_weeks']!);
        return Reading(
          date: iso(today.subtract(Duration(days: days - 1 - i))),
          indicators: ind,
          prices: const {'KLAC': 160.0, 'AVGO': 330.0, 'ETN': 380.0},
        );
      }(),
  ];
}

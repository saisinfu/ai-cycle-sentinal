/// Generic sector engine: score readings, apply hysteresis, explain changes,
/// derive alerts and build per-stock recommendations with price zones.
library;

import 'dart:math' as math;

import '../core/format.dart';
import 'config.dart';
import 'models.dart';
import 'zone.dart';

double _r1(double v) => (v * 10).roundToDouble() / 10;
double _r2(double v) => (v * 100).roundToDouble() / 100;

double linearScore(double v, double worst, double best) =>
    _r1(((v - worst) / (best - worst) * 100).clamp(0, 100).toDouble());

class SubScore {
  const SubScore({required this.spec, required this.raw, required this.score, required this.weighted, required this.display});

  final SignalSpec spec;
  final double raw;
  final double score;
  final double weighted;
  final String display;

  Zone get level => classify(score);
}

class Scored {
  const Scored({required this.reading, required this.index, required this.subs, required this.zone});

  final Reading reading;
  final double index;
  final List<SubScore> subs;
  final Zone zone;
}

/// Readings missing any signal field are skipped.
List<Scored> scoreAll(SectorConfig cfg, List<Reading> readings) {
  final sorted = [...readings]..sort((a, b) => a.date.compareTo(b.date));
  Zone? prev;
  final out = <Scored>[];
  for (final r in sorted) {
    if (!cfg.signals.every((s) => r.indicators.containsKey(s.field))) continue;
    final subs = [
      for (final s in cfg.signals)
        () {
          final raw = r.indicators[s.field]!;
          final score = linearScore(raw, s.worst, s.best);
          return SubScore(spec: s, raw: raw, score: score, weighted: _r2(score * s.weight), display: fillTemplate(s.display, r.indicators));
        }(),
    ];
    final index = _r1(subs.fold<double>(0, (a, s) => a + s.score * s.spec.weight));
    final zone = classifyWithHysteresis(index, prev);
    prev = zone;
    out.add(Scored(reading: r, index: index, subs: subs, zone: zone));
  }
  return out;
}

/* ----------------------------- attribution ----------------------------- */

class Contribution {
  const Contribution({required this.sub, required this.delta, required this.fromRaw});

  final SubScore sub;
  final double delta;
  final double fromRaw;
}

class Attribution {
  const Attribution({required this.from, required this.to, required this.contributions});

  final Scored from;
  final Scored to;
  final List<Contribution> contributions;

  double get change => _r1(to.index - from.index);
}

Attribution _diff(Scored from, Scored to) {
  final list = [
    for (var i = 0; i < to.subs.length; i++)
      Contribution(sub: to.subs[i], delta: _r2(to.subs[i].weighted - from.subs[i].weighted), fromRaw: from.subs[i].raw),
  ]..sort((a, b) => b.delta.abs().compareTo(a.delta.abs()));
  return Attribution(from: from, to: to, contributions: list);
}

Attribution? attributionFor(List<Scored> scored, int days) {
  if (scored.length < 2) return null;
  final last = scored.last;
  final cutoff = parseDate(last.reading.date).subtract(Duration(days: days));
  for (final s in scored.reversed) {
    if (!parseDate(s.reading.date).isAfter(cutoff)) return _diff(s, last);
  }
  return null;
}

/* -------------------------------- alerts -------------------------------- */

enum AlertKind { status, metric }

class AlertEvent {
  const AlertEvent({
    required this.sector,
    required this.kind,
    required this.date,
    required this.zone,
    required this.title,
    required this.message,
    required this.from,
    required this.to,
    this.rule,
  });

  final SectorConfig sector;
  final AlertKind kind;
  final String date;
  final Zone zone;
  final String title;
  final String message;
  final Scored from;
  final Scored to;
  final AlertRule? rule;

  Attribution get drivers => _diff(from, to);
}

String zoneName(Zone z) => switch (z) {
      Zone.expansion => 'ขยายตัว',
      Zone.earlyWarning => 'เตือนล่วงหน้า',
      Zone.digestion => 'ช่วงย่อยการลงทุน',
    };

/// Status changes and edge-triggered metric alerts across the whole history, newest first.
List<AlertEvent> alertsFor(SectorConfig cfg, List<Scored> scored) {
  final out = <AlertEvent>[];
  for (var i = 1; i < scored.length; i++) {
    final a = scored[i - 1], b = scored[i];
    if (a.zone != b.zone) {
      final verb = switch (b.zone) {
        Zone.expansion => 'กลับเข้าโซนขยายตัว',
        Zone.digestion => 'เข้าสู่ช่วงย่อยการลงทุน',
        Zone.earlyWarning => a.zone == Zone.expansion ? 'หลุดจากโซนขยายตัว' : 'ฟื้นออกจากโซนย่อยการลงทุน',
      };
      final top = _diff(a, b).contributions.first;
      out.add(AlertEvent(
        sector: cfg,
        kind: AlertKind.status,
        date: b.reading.date,
        zone: b.zone,
        title: '${cfg.name} · $verb',
        message: 'คะแนน ${a.index.toStringAsFixed(1)} → ${b.index.toStringAsFixed(1)} · สาเหตุหลัก: ${top.sub.spec.label}',
        from: a,
        to: b,
      ));
    }
    for (final rule in cfg.alerts) {
      final now = b.reading.indicators[rule.field], before = a.reading.indicators[rule.field];
      if (now != null && rule.test(now) && (before == null || !rule.test(before))) {
        out.add(AlertEvent(
          sector: cfg,
          kind: AlertKind.metric,
          date: b.reading.date,
          zone: rule.zone,
          title: '${cfg.name} · ${rule.title}',
          message: fillTemplate(rule.message, b.reading.indicators),
          from: a,
          to: b,
          rule: rule,
        ));
      }
    }
  }
  out.sort((x, y) => y.date.compareTo(x.date));
  return out;
}

/// Alerts whose condition is true on the latest reading (shown on the sector page).
List<AlertRule> activeAlerts(SectorConfig cfg, Scored latest) => [
      for (final r in cfg.alerts)
        if (latest.reading.indicators[r.field] != null && r.test(latest.reading.indicators[r.field]!)) r,
    ];

/* ------------------------------ price zones ------------------------------ */

enum ZoneMethod { fixed, ma200, pe }

ZoneMethod zoneMethodFrom(String? v) => switch (v) {
      'ma200' => ZoneMethod.ma200,
      'pe' => ZoneMethod.pe,
      _ => ZoneMethod.fixed,
    };

String zoneMethodKey(ZoneMethod m) => switch (m) {
      ZoneMethod.fixed => 'fixed',
      ZoneMethod.ma200 => 'ma200',
      ZoneMethod.pe => 'pe',
    };

String zoneMethodName(ZoneMethod m) => switch (m) {
      ZoneMethod.fixed => 'กรอบรอบราคาปิด',
      ZoneMethod.ma200 => 'เส้นค่าเฉลี่ย 200 วัน',
      ZoneMethod.pe => 'P/E เทียบค่าเฉลี่ย 5 ปี',
    };

const Map<StockAction, List<(String, double, double)>> _bands = {
  StockAction.buyDca: [('โซน DCA', 0.92, 1.00), ('โซนซื้อเพิ่มเมื่อย่อ', 0.85, 0.92)],
  StockAction.overweightDca: [('โซน DCA', 0.93, 1.02), ('โซนซื้อเพิ่มเมื่อย่อ', 0.86, 0.93)],
  StockAction.accumulate: [('โซนสะสม', 0.88, 0.98), ('โซนราคาถูกมาก', 0.80, 0.88)],
  StockAction.pauseDca: [('โซนรอกลับเข้าซื้อ', 0.82, 0.90)],
  StockAction.reduceHoldings: [('โซนทยอยขายเมื่อราคาขึ้น', 1.00, 1.08), ('โซนรอกลับเข้าซื้อ', 0.75, 0.85)],
  StockAction.hold: [('โซนรอกลับเข้าซื้อ', 0.85, 0.92)],
};

String bandText(StockAction a) =>
    _bands[a]!.map((b) => '${b.$1} ${(b.$2 * 100).round()}–${(b.$3 * 100).round()}%').join(' · ');

class PriceZone {
  const PriceZone(this.label, this.low, this.high);

  final String label;
  final double low;
  final double high;
}

class ZonePlan {
  const ZonePlan({
    required this.method,
    required this.anchor,
    required this.anchorText,
    required this.price,
    required this.currency,
    required this.zones,
    required this.position,
    required this.fallbackNote,
    required this.priceAsOf,
    required this.sourceUrl,
  });

  final ZoneMethod method;
  final double anchor;
  final String anchorText;
  final double price;
  final String currency;
  final List<PriceZone> zones;
  final String position;
  final String? fallbackNote;
  final String? priceAsOf;
  final String? sourceUrl;
}

ZonePlan? buildZonePlan(StockAction action, ZoneMethod wanted, Quote? quote, double? fallbackPrice, String? fallbackAsOf) {
  final price = quote?.price ?? fallbackPrice;
  if (price == null || price <= 0) return null;
  final cur = quote?.currency ?? 'USD';
  var method = wanted;
  String? note;
  double anchor = price;
  String anchorText = 'ราคาปิดล่าสุด ${money(price, cur)}';
  if (wanted == ZoneMethod.ma200) {
    if (quote?.ma200 != null) {
      anchor = quote!.ma200!;
      anchorText = 'ค่าเฉลี่ยราคา 200 วัน ${money(anchor, cur)}';
    } else {
      method = ZoneMethod.fixed;
      note = 'ยังไม่มีข้อมูลค่าเฉลี่ย 200 วัน จึงใช้ราคาปิดแทน';
    }
  } else if (wanted == ZoneMethod.pe) {
    final pe = quote?.pe, avg = quote?.pe5yAvg;
    if (pe != null && pe > 0 && avg != null && avg > 0) {
      final eps = price / pe;
      anchor = eps * avg;
      anchorText = 'กำไรต่อหุ้น ${money(eps, cur)} × P/E เฉลี่ย 5 ปี ${avg.toStringAsFixed(1)} = ${money(anchor, cur)} '
          '(P/E ตอนนี้ ${pe.toStringAsFixed(1)})';
    } else {
      method = ZoneMethod.fixed;
      note = 'ยังไม่มีข้อมูล P/E ย้อนหลัง จึงใช้ราคาปิดแทน';
    }
  }
  final zones = [for (final b in _bands[action]!) PriceZone(b.$1, anchor * b.$2, anchor * b.$3)];
  final first = zones.first;
  final String position;
  if (price > first.high) {
    position = 'ราคาตอนนี้สูงกว่า${first.label} ${((price / first.high - 1) * 100).toStringAsFixed(0)}%';
  } else if (price < first.low) {
    position = 'ราคาตอนนี้ต่ำกว่า${first.label} ${((1 - price / first.low) * 100).toStringAsFixed(0)}%';
  } else {
    position = 'ราคาตอนนี้อยู่ใน${first.label}';
  }
  return ZonePlan(
    method: method,
    anchor: anchor,
    anchorText: anchorText,
    price: price,
    currency: cur,
    zones: zones,
    position: position,
    fallbackNote: note,
    priceAsOf: quote?.asOf ?? fallbackAsOf,
    sourceUrl: method == ZoneMethod.pe ? (quote?.peSourceUrl ?? quote?.sourceUrl) : quote?.sourceUrl,
  );
}

/* ---------------------------- recommendations ---------------------------- */

class Recommendation {
  const Recommendation({required this.stock, required this.cell, required this.reason, required this.plan});

  final StockSpec stock;
  final RuleCell cell;
  final String reason;
  final ZonePlan? plan;
}

List<Recommendation> buildRecommendations(SectorConfig cfg, Scored latest, MarketData market, ZoneMethod method) {
  final cells = cfg.rules[latest.zone] ?? const {};
  return [
    for (final s in cfg.stocks)
      Recommendation(
        stock: s,
        cell: cells[s.ticker] ?? const RuleCell(StockAction.hold, 0, null),
        reason: cfg.reasons[latest.zone]?[s.ticker] ?? '',
        plan: buildZonePlan(
          (cells[s.ticker] ?? const RuleCell(StockAction.hold, 0, null)).action,
          method,
          market.quotes[s.ticker],
          latest.reading.prices[s.ticker],
          latest.reading.pricesAsOf,
        ),
      ),
  ];
}

double cashReservePct(SectorConfig cfg, Zone zone) {
  final cells = cfg.rules[zone] ?? const {};
  final allocated = cells.values.fold<double>(0, (a, c) => a + c.allocationPct);
  return math.max(0.0, 100 - allocated);
}

/* ------------------------------ sector view ------------------------------ */

class SectorVM {
  SectorVM({required this.config, required this.scored, required this.market, required this.method})
      : recommendations = buildRecommendations(config, scored.last, market, method),
        attribution = {
          7: attributionFor(scored, 7),
          30: attributionFor(scored, 30),
          90: attributionFor(scored, 90),
        },
        alerts = alertsFor(config, scored);

  final SectorConfig config;
  final List<Scored> scored;
  final MarketData market;
  final ZoneMethod method;
  final List<Recommendation> recommendations;
  final Map<int, Attribution?> attribution;
  final List<AlertEvent> alerts;

  Scored get latest => scored.last;
  Zone? get previousZone => scored.length > 1 ? scored[scored.length - 2].zone : null;

  /// Date the current status began.
  String get statusSince {
    var i = scored.length - 1;
    while (i > 0 && scored[i - 1].zone == latest.zone) {
      i--;
    }
    return scored[i].reading.date;
  }
}

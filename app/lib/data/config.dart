/// App configuration loaded from config/sectors.json (remote, with a bundled
/// fallback). Sector signals, stocks, rules and alert thresholds live here so
/// they can change without reinstalling the app.
library;

import 'zone.dart';

double _d(Object? v, [double fallback = 0]) => v is num ? v.toDouble() : fallback;
String _s(Object? v, [String fallback = '']) => v is String ? v : fallback;

class SignalSpec {
  const SignalSpec({
    required this.key,
    required this.field,
    required this.label,
    required this.labelEn,
    required this.short,
    required this.weight,
    required this.worst,
    required this.best,
    required this.display,
    required this.range,
    required this.why,
    required this.source,
    required this.sourceUrl,
    required this.frequency,
    required this.isEstimate,
  });

  factory SignalSpec.fromJson(Map j) => SignalSpec(
        key: _s(j['key']),
        field: _s(j['field']),
        label: _s(j['label']),
        labelEn: _s(j['label_en']),
        short: _s(j['short'], _s(j['label'])),
        weight: _d(j['weight']),
        worst: _d(j['worst']),
        best: _d(j['best'], 1),
        display: _s(j['display'], '{${_s(j['field'])}:2}'),
        range: _s(j['range']),
        why: _s(j['why']),
        source: _s(j['source']),
        sourceUrl: j['source_url'] is String ? j['source_url'] as String : null,
        frequency: _s(j['frequency']),
        isEstimate: j['kind'] == 'estimate',
      );

  final String key;
  final String field;
  final String label;
  final String labelEn;
  final String short;
  final double weight;
  final double worst;
  final double best;
  final String display;
  final String range;
  final String why;
  final String source;
  final String? sourceUrl;
  final String frequency;
  final bool isEstimate;
}

enum StockAction { buyDca, pauseDca, overweightDca, reduceHoldings, accumulate, hold }

StockAction _action(String v) => switch (v) {
      'BUY_DCA' => StockAction.buyDca,
      'PAUSE_DCA' => StockAction.pauseDca,
      'OVERWEIGHT_DCA' => StockAction.overweightDca,
      'REDUCE_HOLDINGS' => StockAction.reduceHoldings,
      'ACCUMULATE' => StockAction.accumulate,
      _ => StockAction.hold,
    };

class RuleCell {
  const RuleCell(this.action, this.allocationPct, this.trimPct);

  final StockAction action;
  final double allocationPct;
  final double? trimPct;
}

class StockSpec {
  const StockSpec(this.ticker, this.name);

  final String ticker;
  final String name;
}

class AlertRule {
  const AlertRule({
    required this.field,
    required this.op,
    required this.value,
    required this.zone,
    required this.title,
    required this.message,
  });

  factory AlertRule.fromJson(Map j) => AlertRule(
        field: _s(j['field']),
        op: _s(j['op'], '>'),
        value: _d(j['value']),
        zone: zoneFromCode(_s(j['zone'], 'W')),
        title: _s(j['title']),
        message: _s(j['message']),
      );

  final String field;
  final String op;
  final double value;
  final Zone zone;
  final String title;
  final String message;

  bool test(double v) => op == '<' ? v < value : v > value;
}

class SectorConfig {
  const SectorConfig({
    required this.id,
    required this.name,
    required this.icon,
    required this.dataPath,
    required this.confidence,
    required this.confidenceNote,
    required this.summary,
    required this.signals,
    required this.stocks,
    required this.rules,
    required this.rulesFromUser,
    required this.reasons,
    required this.alerts,
  });

  factory SectorConfig.fromJson(Map j) {
    final rules = <Zone, Map<String, RuleCell>>{};
    final rawRules = j['rules'];
    if (rawRules is Map) {
      rawRules.forEach((code, cells) {
        if (code is! String || cells is! Map) return;
        final m = <String, RuleCell>{};
        cells.forEach((ticker, cell) {
          if (ticker is String && cell is List && cell.isNotEmpty) {
            m[ticker] = RuleCell(
              _action(_s(cell[0])),
              cell.length > 1 ? _d(cell[1]) : 0,
              cell.length > 2 && cell[2] is num ? _d(cell[2]) : null,
            );
          }
        });
        rules[zoneFromCode(code)] = m;
      });
    }
    final reasons = <Zone, Map<String, String>>{};
    final rawReasons = j['reasons'];
    if (rawReasons is Map) {
      rawReasons.forEach((code, cells) {
        if (code is String && cells is Map) {
          reasons[zoneFromCode(code)] = {
            for (final e in cells.entries)
              if (e.key is String && e.value is String) e.key as String: e.value as String,
          };
        }
      });
    }
    final summary = <Zone, String>{};
    final rawSummary = j['summary'];
    if (rawSummary is Map) {
      rawSummary.forEach((code, text) {
        if (code is String && text is String) summary[zoneFromCode(code)] = text;
      });
    }
    return SectorConfig(
      id: _s(j['id']),
      name: _s(j['name']),
      icon: _s(j['icon']),
      dataPath: _s(j['data']),
      confidence: _s(j['confidence'], 'medium'),
      confidenceNote: _s(j['confidence_note']),
      summary: summary,
      signals: [
        for (final s in (j['signals'] as List? ?? const [])) if (s is Map) SignalSpec.fromJson(s),
      ],
      stocks: [
        for (final s in (j['stocks'] as List? ?? const []))
          if (s is Map) StockSpec(_s(s['ticker']), _s(s['name'])),
      ],
      rules: rules,
      rulesFromUser: j['rules_origin'] == 'user',
      reasons: reasons,
      alerts: [
        for (final a in (j['alerts'] as List? ?? const [])) if (a is Map) AlertRule.fromJson(a),
      ],
    );
  }

  final String id;
  final String name;
  final String icon;
  final String dataPath;
  final String confidence;
  final String confidenceNote;
  final Map<Zone, String> summary;
  final List<SignalSpec> signals;
  final List<StockSpec> stocks;
  final Map<Zone, Map<String, RuleCell>> rules;
  final bool rulesFromUser;
  final Map<Zone, Map<String, String>> reasons;
  final List<AlertRule> alerts;

  String stockName(String ticker) =>
      stocks.firstWhere((s) => s.ticker == ticker, orElse: () => StockSpec(ticker, ticker)).name;
}

class MainAsset {
  const MainAsset(this.key, this.name, this.proxy, this.note);

  final String key;
  final String name;
  final String proxy;
  final String note;
}

class AppConfig {
  const AppConfig({required this.sectors, required this.mainPort});

  factory AppConfig.fromJson(Map j) => AppConfig(
        sectors: [
          for (final s in (j['sectors'] as List? ?? const []))
            if (s is Map) SectorConfig.fromJson(s),
        ].where((s) => s.id.isNotEmpty && s.signals.isNotEmpty).toList(),
        mainPort: [
          for (final a in (j['main_port'] as List? ?? const []))
            if (a is Map) MainAsset(_s(a['key']), _s(a['name']), _s(a['proxy']), _s(a['note'])),
        ],
      );

  final List<SectorConfig> sectors;
  final List<MainAsset> mainPort;

  SectorConfig? sector(String id) {
    for (final s in sectors) {
      if (s.id == id) return s;
    }
    return null;
  }
}

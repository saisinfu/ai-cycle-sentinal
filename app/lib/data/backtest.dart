/// Backtest summary written by the GitHub backtest job (data/backtest.json).
library;

String _s(Object? v, [String d = '']) => v is String ? v : d;
double? _n(Object? v) => v is num ? v.toDouble() : null;
List<Map> _maps(Object? v) => v is List ? [for (final x in v) if (x is Map) x] : const [];
List<String> _strs(Object? v) => v is List ? [for (final x in v) if (x is String) x] : const [];

class StrategyRow {
  const StrategyRow({
    required this.label,
    required this.from,
    required this.to,
    this.plainIrr,
    this.previousIrr,
    this.currentIrr,
    this.plainDd,
    this.previousDd,
    this.currentDd,
  });

  factory StrategyRow.fromJson(Map j) => StrategyRow(
        label: _s(j['label']),
        from: _s(j['from']),
        to: _s(j['to']),
        plainIrr: _n(j['plain_irr']),
        previousIrr: _n(j['previous_irr']),
        currentIrr: _n(j['current_irr']),
        plainDd: _n(j['plain_dd']),
        previousDd: _n(j['previous_dd']),
        currentDd: _n(j['current_dd']),
      );

  final String label;
  final String from;
  final String to;
  final double? plainIrr;
  final double? previousIrr;
  final double? currentIrr;
  final double? plainDd;
  final double? previousDd;
  final double? currentDd;
}

class ZoneForward {
  const ZoneForward(this.zone, this.months, this.fwd12Mean, this.negShare);

  factory ZoneForward.fromJson(Map j) =>
      ZoneForward(_s(j['zone']), (_n(j['months']) ?? 0).round(), _n(j['fwd12_mean']), _n(j['fwd12_neg_share']));

  final String zone;
  final int months;
  final double? fwd12Mean;
  final double? negShare;
}

class SignalVerdict {
  const SignalVerdict(this.key, this.label, this.ic, this.verdict);

  factory SignalVerdict.fromJson(Map j) => SignalVerdict(_s(j['key']), _s(j['label']), _n(j['ic']), _s(j['verdict']));

  final String key;
  final String label;
  final double? ic;
  final String verdict;
}

class SectorBacktest {
  const SectorBacktest({
    required this.status,
    required this.headline,
    this.verdict = '',
    this.periodFrom = '',
    this.periodTo = '',
    this.months = 0,
    this.indexIc,
    this.strategies = const [],
    this.zones = const [],
    this.signals = const [],
    this.robustness = const [],
    this.caveats = const [],
    this.sources = const [],
  });

  factory SectorBacktest.fromJson(Map j) => SectorBacktest(
        status: _s(j['status'], 'not_tested'),
        headline: _s(j['headline']),
        verdict: _s(j['verdict']),
        periodFrom: _s(j['period_from']),
        periodTo: _s(j['period_to']),
        months: (_n(j['months']) ?? 0).round(),
        indexIc: _n(j['index_ic']),
        strategies: [for (final m in _maps(j['strategies'])) StrategyRow.fromJson(m)],
        zones: [for (final m in _maps(j['zones'])) ZoneForward.fromJson(m)],
        signals: [for (final m in _maps(j['signals'])) SignalVerdict.fromJson(m)],
        robustness: [for (final m in _maps(j['robustness'])) (_s(m['label']), _s(m['value']))],
        caveats: _strs(j['caveats']),
        sources: [for (final m in _maps(j['data_sources'])) (_s(m['label']), _s(m['url']))],
      );

  final String status;
  final String headline;
  final String verdict;
  final String periodFrom;
  final String periodTo;
  final int months;
  final double? indexIc;
  final List<StrategyRow> strategies;
  final List<ZoneForward> zones;
  final List<SignalVerdict> signals;
  final List<(String, String)> robustness;
  final List<String> caveats;
  final List<(String, String)> sources;

  bool get tested => status == 'tested';
}

class BacktestSummary {
  const BacktestSummary({required this.generated, required this.chartUrl, required this.detailsUrl, required this.sectors});

  factory BacktestSummary.fromJson(Map j) {
    final raw = j['sectors'];
    return BacktestSummary(
      generated: _s(j['generated']),
      chartUrl: _s(j['chart_url']),
      detailsUrl: _s(j['details_url']),
      sectors: {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.key is String && e.value is Map) e.key as String: SectorBacktest.fromJson(e.value as Map),
      },
    );
  }

  final String generated;
  final String chartUrl;
  final String detailsUrl;
  final Map<String, SectorBacktest> sectors;
}

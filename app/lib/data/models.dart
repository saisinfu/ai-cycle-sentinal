/// One daily reading as stored in data/readings.json (same schema as the
/// Claude dashboard's database).
library;

double? _num(Object? v) => v is num ? v.toDouble() : null;

Map<String, String> _strMap(Object? v) {
  if (v is! Map) return const {};
  final out = <String, String>{};
  v.forEach((k, val) {
    if (k is String && val is String) out[k] = val;
  });
  return out;
}

Map<String, double> _numMap(Object? v) {
  if (v is! Map) return const {};
  final out = <String, double>{};
  v.forEach((k, val) {
    final d = _num(val);
    if (k is String && d != null) out[k] = d;
  });
  return out;
}

class SourceLink {
  const SourceLink({required this.key, required this.label, required this.url});

  final String key;
  final String label;
  final String url;
}

class Reading {
  const Reading({
    required this.date,
    required this.indicators,
    this.confidence = const {},
    this.notes = const {},
    this.prices = const {},
    this.pricesAsOf,
    this.sources = const [],
  });

  /// Returns null when the entry is malformed (it is skipped, not fatal).
  static Reading? tryParse(Object? j) {
    if (j is! Map) return null;
    final date = j['date'];
    if (date is! String || date.length != 10) return null;
    final ind = _numMap(j['indicators']);
    const required = [
      'capex_to_cloud_revenue_ratio',
      'chip_lead_time_weeks',
      'gpu_spot_price_usd_hr',
      'gpu_spot_price_change_1m_pct',
      'enterprise_ai_adoption_pct',
      'enterprise_ai_adoption_change_3m_pp',
      'power_grid_stress_level',
    ];
    if (!required.every(ind.containsKey)) return null;
    final sources = <SourceLink>[];
    final rawSources = j['sources'];
    if (rawSources is List) {
      for (final s in rawSources) {
        if (s is Map && s['url'] is String && (s['url'] as String).startsWith('https://')) {
          sources.add(SourceLink(
            key: (s['key'] as String?) ?? '',
            label: (s['label'] as String?) ?? 'ที่มา',
            url: s['url'] as String,
          ));
        }
      }
    }
    return Reading(
      date: date,
      indicators: ind,
      confidence: _strMap(j['confidence']),
      notes: _strMap(j['notes_th']),
      prices: _numMap(j['prices']),
      pricesAsOf: j['prices_as_of'] is String ? j['prices_as_of'] as String : null,
      sources: sources,
    );
  }

  final String date;
  final Map<String, double> indicators;
  final Map<String, String> confidence;
  final Map<String, String> notes;
  final Map<String, double> prices;
  final String? pricesAsOf;
  final List<SourceLink> sources;

  double ind(String k) => indicators[k] ?? 0;
}

class ReadingsResult {
  const ReadingsResult({required this.readings, required this.fromCache, this.updatedAt});

  final List<Reading> readings;

  /// True when the network failed and the last saved copy is shown.
  final bool fromCache;
  final String? updatedAt;
}

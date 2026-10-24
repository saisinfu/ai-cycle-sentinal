/// Data files written by the daily Claude task.
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

  static Reading? tryParse(Object? j) {
    if (j is! Map) return null;
    final date = j['date'];
    if (date is! String || date.length != 10) return null;
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
      indicators: _numMap(j['indicators']),
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
}

class Quote {
  const Quote({
    required this.ticker,
    required this.price,
    required this.currency,
    this.asOf,
    this.ma200,
    this.pe,
    this.pe5yAvg,
    this.sourceUrl,
    this.peSourceUrl,
  });

  final String ticker;
  final double price;
  final String currency;
  final String? asOf;
  final double? ma200;
  final double? pe;
  final double? pe5yAvg;
  final String? sourceUrl;
  final String? peSourceUrl;
}

class MarketData {
  const MarketData({required this.quotes, this.updatedAt});

  factory MarketData.fromJson(Object? j) {
    final quotes = <String, Quote>{};
    if (j is Map && j['quotes'] is Map) {
      (j['quotes'] as Map).forEach((k, v) {
        if (k is String && v is Map && _num(v['price']) != null) {
          String? str(String key) => v[key] is String ? v[key] as String : null;
          quotes[k] = Quote(
            ticker: k,
            price: _num(v['price'])!,
            currency: str('currency') ?? 'USD',
            asOf: str('as_of'),
            ma200: _num(v['ma200']),
            pe: _num(v['pe']),
            pe5yAvg: _num(v['pe_5y_avg']),
            sourceUrl: str('source_url'),
            peSourceUrl: str('pe_source_url'),
          );
        }
      });
    }
    return MarketData(quotes: quotes, updatedAt: j is Map && j['updated_at'] is String ? j['updated_at'] as String : null);
  }

  static const empty = MarketData(quotes: {});

  final Map<String, Quote> quotes;
  final String? updatedAt;
}

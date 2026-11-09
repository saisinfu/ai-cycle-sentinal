/// News feed (data/news.json, written by Claude twice a day) and price events
/// (data/price_events.json, written by the GitHub market job).
library;

String _s(Object? v, [String d = '']) => v is String ? v : d;
double? _n(Object? v) => v is num ? v.toDouble() : null;
List<Map> _maps(Object? v) => v is List ? [for (final x in v) if (x is Map) x] : const [];

class NewsImpact {
  const NewsImpact({required this.target, required this.label, required this.direction, required this.strength, required this.reason});

  factory NewsImpact.fromJson(Map j) => NewsImpact(
        target: _s(j['target']),
        label: _s(j['label_th'], _s(j['target'])),
        direction: _s(j['direction'], 'mixed'),
        strength: _s(j['strength'], 'medium'),
        reason: _s(j['reason_th']),
      );

  /// sector id, ticker, or main:gold / main:sp500 / main:nasdaq / main:kkp
  final String target;
  final String label;

  /// negative | positive | mixed
  final String direction;

  /// high | medium | low
  final String strength;
  final String reason;
}

class NewsItem {
  const NewsItem({
    required this.id,
    required this.date,
    required this.time,
    required this.level,
    required this.category,
    required this.title,
    required this.summary,
    required this.impacts,
    required this.whatToDo,
    required this.watchNext,
    required this.sources,
  });

  factory NewsItem.fromJson(Map j) => NewsItem(
        id: _s(j['id']),
        date: _s(j['date']),
        time: _s(j['time_utc']),
        level: _s(j['level'], 'low'),
        category: _s(j['category'], 'market'),
        title: _s(j['title_th']),
        summary: _s(j['summary_th']),
        impacts: [for (final m in _maps(j['impacts'])) NewsImpact.fromJson(m)],
        whatToDo: _s(j['what_to_do_th']),
        watchNext: _s(j['watch_next_th']),
        sources: [for (final m in _maps(j['sources'])) if (_s(m['url']).startsWith('http')) (_s(m['label'], 'ที่มา'), _s(m['url']))],
      );

  final String id;
  final String date;
  final String time;

  /// high | medium | low
  final String level;
  final String category;
  final String title;
  final String summary;
  final List<NewsImpact> impacts;
  final String whatToDo;
  final String watchNext;
  final List<(String, String)> sources;

  String get sortKey => time.isNotEmpty ? time : date;
}

List<NewsItem> parseNews(Object? j) {
  if (j is! Map) return const [];
  final items = [for (final m in _maps(j['items'])) NewsItem.fromJson(m)]..removeWhere((n) => n.title.isEmpty || n.date.isEmpty);
  items.sort((a, b) => b.sortKey.compareTo(a.sortKey));
  return items;
}

class PriceEvent {
  const PriceEvent({
    required this.date,
    required this.ticker,
    required this.name,
    required this.kind,
    required this.value,
    required this.price,
    required this.title,
    required this.detail,
    this.drawdown,
  });

  factory PriceEvent.fromJson(Map j) => PriceEvent(
        date: _s(j['date']),
        ticker: _s(j['ticker']),
        name: _s(j['name'], _s(j['ticker'])),
        kind: _s(j['kind']),
        value: _n(j['value']) ?? 0,
        price: _n(j['price']) ?? 0,
        drawdown: _n(j['drawdown_pct']),
        title: _s(j['title_th']),
        detail: _s(j['detail_th']),
      );

  final String date;
  final String ticker;
  final String name;

  /// day_drop | drawdown
  final String kind;
  final double value;
  final double price;
  final double? drawdown;
  final String title;
  final String detail;
}

class PriceEvents {
  const PriceEvents({required this.events, this.dayDropPct = -7, this.drawdownPct = -20});

  factory PriceEvents.fromJson(Object? j) {
    if (j is! Map) return const PriceEvents(events: []);
    final rules = j['rules'] is Map ? j['rules'] as Map : const {};
    final ev = [for (final m in _maps(j['events'])) PriceEvent.fromJson(m)]..sort((a, b) => b.date.compareTo(a.date));
    return PriceEvents(events: ev, dayDropPct: _n(rules['day_drop_pct']) ?? -7, drawdownPct: _n(rules['drawdown_pct']) ?? -20);
  }

  final List<PriceEvent> events;
  final double dayDropPct;
  final double drawdownPct;
}

/// Summary message of one morning/evening Claude run (data/briefs.json) — the same text
/// the user gets as a push notification.
class Brief {
  const Brief({
    required this.id,
    required this.date,
    required this.run,
    required this.time,
    required this.headline,
    required this.text,
    required this.level,
    required this.newsIds,
    this.reconstructed = false,
  });

  factory Brief.fromJson(Map j) => Brief(
        id: _s(j['id']),
        date: _s(j['date']),
        run: _s(j['run'], 'morning'),
        time: _s(j['time_utc']),
        headline: _s(j['headline_th']),
        text: _s(j['text_th']),
        level: _s(j['level'], 'low'),
        newsIds: [for (final x in (j['news_ids'] is List ? j['news_ids'] as List : const [])) if (x is String) x],
        reconstructed: j['reconstructed'] == true,
      );

  final String id;
  final String date;

  /// morning | evening
  final String run;
  final String time;
  final String headline;
  final String text;
  final String level;
  final List<String> newsIds;

  /// Rebuilt from the news feed rather than the original notification text.
  final bool reconstructed;

  String get runTh => run == 'evening' ? 'รอบค่ำ' : 'รอบเช้า';
  String get sortKey => time.isNotEmpty ? time : '$date${run == 'evening' ? 'T20' : 'T08'}';
}

List<Brief> parseBriefs(Object? j) {
  if (j is! Map) return const [];
  final items = [for (final m in _maps(j['items'])) Brief.fromJson(m)]..removeWhere((b) => b.date.isEmpty || (b.headline.isEmpty && b.text.isEmpty));
  items.sort((a, b) => b.sortKey.compareTo(a.sortKey));
  return items;
}

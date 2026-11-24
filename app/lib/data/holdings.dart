/// What the owner actually holds (entered by hand, stored on the phone), valued in baht.
library;

import 'config.dart';
import 'models.dart';

class Holding {
  const Holding({required this.key, required this.label, this.ticker, this.units = 0, this.costThb = 0, this.manualValueThb});

  factory Holding.fromJson(Map j) => Holding(
        key: j['key'] is String ? j['key'] as String : '',
        label: j['label'] is String ? j['label'] as String : '',
        ticker: j['ticker'] is String ? j['ticker'] as String : null,
        units: j['units'] is num ? (j['units'] as num).toDouble() : 0,
        costThb: j['costThb'] is num ? (j['costThb'] as num).toDouble() : 0,
        manualValueThb: j['manualValueThb'] is num ? (j['manualValueThb'] as num).toDouble() : null,
      );

  /// Same keys as the monthly plan: 'main:<key>' or '<sectorId>:<ticker>'.
  final String key;
  final String label;

  /// Yahoo ticker used for the price (null = value entered by hand).
  final String? ticker;
  final double units;

  /// Total amount paid, in baht.
  final double costThb;

  /// For things without a usable price (Thai gold bar, Thai mutual funds): current value typed in.
  final double? manualValueThb;

  Holding copyWith({double? units, double? costThb, double? manualValueThb, bool clearManual = false}) => Holding(
        key: key,
        label: label,
        ticker: ticker,
        units: units ?? this.units,
        costThb: costThb ?? this.costThb,
        manualValueThb: clearManual ? null : (manualValueThb ?? this.manualValueThb),
      );

  Map<String, Object?> toJson() => {
        'key': key,
        'label': label,
        'ticker': ticker,
        'units': units,
        'costThb': costThb,
        'manualValueThb': manualValueThb,
      };

  bool get isEmpty => units <= 0 && (manualValueThb ?? 0) <= 0 && costThb <= 0;
}

/// Baht per US dollar from the market snapshot (THB=X), with a fallback.
double usdThb(MarketData m) => m.quotes['THB=X']?.price ?? 33.0;

class HoldingValue {
  const HoldingValue({
    required this.holding,
    required this.valueThb,
    required this.theme,
    required this.isFund,
    required this.isUsd,
    required this.bucket,
    this.priced = true,
  });

  final Holding holding;
  final double valueThb;
  final String theme;
  final bool isFund;
  final bool isUsd;

  /// 'main' or 'tech' (individual stocks).
  final String bucket;

  /// False when no price was available and nothing was typed in.
  final bool priced;

  double get pnlThb => valueThb - holding.costThb;
  double? get pnlPct => holding.costThb > 0 ? (valueThb / holding.costThb - 1) * 100 : null;
}

class PortfolioView {
  const PortfolioView({
    required this.values,
    required this.total,
    required this.cost,
    required this.byTheme,
    required this.byBucket,
    required this.usdShare,
    required this.worstCaseThb,
    required this.fx,
  });

  final List<HoldingValue> values;
  final double total;
  final double cost;
  final Map<String, double> byTheme;
  final Map<String, double> byBucket;

  /// Share of the portfolio priced in US dollars (0–1).
  final double usdShare;

  /// Loss in baht in the stress scenario (see [worstCaseNote]).
  final double worstCaseThb;
  final double fx;

  bool get isEmpty => values.isEmpty || total <= 0;
  double get pnl => total - cost;
  double? get pnlPct => cost > 0 ? (total / cost - 1) * 100 : null;
  double weightOf(String key) {
    if (total <= 0) return 0;
    final v = values.where((x) => x.holding.key == key).fold(0.0, (a, b) => a + b.valueThb);
    return v / total;
  }
}

const worstCaseNote = 'สถานการณ์จำลองแย่มาก: หุ้นรายตัวลง 50% · กองทุนเทคลง 45% · กองทุนหุ้นทั่วไปลง 35% · ทองลง 35% · หุ้นไทยลง 40% '
    'และเงินบาทแข็งขึ้น 10% (สินทรัพย์ดอลลาร์มีค่าเป็นบาทลดลงอีก)';

String themeTh(String t) => switch (t) {
      'tech' => 'เทค/AI',
      'gold' => 'ทองคำ',
      'us' => 'หุ้นสหรัฐทั้งตลาด',
      'thai' => 'หุ้นไทย',
      'finance' => 'การเงิน',
      'health' => 'สุขภาพ',
      'staples' => 'ของใช้จำเป็น',
      'travel' => 'ท่องเที่ยว',
      'space' => 'อวกาศ/กลาโหม',
      _ => 'อื่นๆ',
    };

PortfolioView buildPortfolio(List<Holding> holdings, AppConfig config, MarketData market) {
  final fx = usdThb(market);
  final values = <HoldingValue>[];
  for (final h in holdings) {
    if (h.isEmpty) continue;
    var theme = 'other', isFund = true, bucket = 'main';
    if (h.key.startsWith('main:')) {
      final a = config.mainPort.where((x) => 'main:${x.key}' == h.key).firstOrNull;
      theme = a?.theme ?? 'other';
      isFund = a?.isFund ?? true;
    } else {
      final sid = h.key.split(':').first;
      final s = config.sector(sid);
      theme = s?.theme ?? 'other';
      isFund = s?.stocks.where((x) => x.ticker == h.ticker).firstOrNull?.isFund ?? false;
      bucket = 'tech';
    }
    final q = h.ticker == null ? null : market.quotes[h.ticker!];
    final isUsd = q != null ? q.currency != 'THB' : !(h.ticker?.endsWith('.BK') ?? true);
    double value;
    var priced = true;
    if (h.manualValueThb != null) {
      value = h.manualValueThb!;
    } else if (q != null && h.units > 0) {
      value = h.units * q.price * (q.currency == 'THB' ? 1 : fx);
    } else {
      value = h.costThb;
      priced = false;
    }
    values.add(HoldingValue(holding: h, valueThb: value, theme: theme, isFund: isFund, isUsd: isUsd, bucket: bucket, priced: priced));
  }
  final total = values.fold(0.0, (a, b) => a + b.valueThb);
  final cost = values.fold(0.0, (a, b) => a + b.holding.costThb);
  final byTheme = <String, double>{};
  final byBucket = <String, double>{};
  var usd = 0.0, worst = 0.0;
  for (final v in values) {
    byTheme[v.theme] = (byTheme[v.theme] ?? 0) + v.valueThb;
    byBucket[v.bucket] = (byBucket[v.bucket] ?? 0) + v.valueThb;
    if (v.isUsd) usd += v.valueThb;
    final shock = !v.isFund
        ? (v.theme == 'thai' ? 0.40 : 0.50)
        : switch (v.theme) { 'tech' => 0.45, 'gold' => 0.35, 'thai' => 0.40, _ => 0.35 };
    final after = v.valueThb * (1 - shock) * (v.isUsd ? 1 / 1.10 : 1);
    worst += v.valueThb - after;
  }
  return PortfolioView(
    values: values..sort((a, b) => b.valueThb.compareTo(a.valueThb)),
    total: total,
    cost: cost,
    byTheme: byTheme,
    byBucket: byBucket,
    usdShare: total > 0 ? usd / total : 0,
    worstCaseThb: worst,
    fx: fx,
  );
}

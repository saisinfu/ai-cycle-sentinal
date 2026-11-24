import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backtest.dart';
import '../data/budget.dart';
import '../data/feed.dart';
import '../data/flex.dart';
import '../data/holdings.dart';
import '../data/config.dart';
import '../data/engine.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'settings.dart';

final repositoryProvider = Provider<Repository>((ref) => Repository());

final configProvider = FutureProvider<AppConfig>((ref) => ref.watch(repositoryProvider).loadConfig());

final marketProvider = FutureProvider<MarketData>((ref) => ref.watch(repositoryProvider).loadMarket());

final backtestProvider = FutureProvider<BacktestSummary?>((ref) => ref.watch(repositoryProvider).loadBacktest());

final readingsProvider = FutureProvider.family<Loaded<List<Reading>>, String>(
  (ref, path) => ref.watch(repositoryProvider).loadReadings(path),
);

/// One sector's scored view, or null while loading / when it has no data.
final sectorVMProvider = Provider.family<AsyncValue<SectorVM?>, String>((ref, id) {
  final cfg = ref.watch(configProvider);
  return cfg.when(
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
    data: (config) {
      final sector = config.sector(id);
      if (sector == null) return const AsyncValue.data(null);
      final readings = ref.watch(readingsProvider(sector.dataPath));
      final market = ref.watch(marketProvider).valueOrNull ?? MarketData.empty;
      final method = ref.watch(settingsProvider.select((s) => s.zoneMethod));
      return readings.whenData((loaded) {
        final scored = scoreAll(sector, loaded.value);
        if (scored.isEmpty) return null;
        return SectorVM(config: sector, scored: scored, market: market, method: method);
      });
    },
  );
});

/// All sectors that have loaded, in config order.
final allSectorsProvider = Provider<List<SectorVM>>((ref) {
  final config = ref.watch(configProvider).valueOrNull;
  if (config == null) return const [];
  return [
    for (final s in config.sectors)
      if (ref.watch(sectorVMProvider(s.id)).valueOrNull case final SectorVM vm) vm,
  ];
});

final allAlertsProvider = Provider<List<AlertEvent>>((ref) {
  final settings = ref.watch(settingsProvider);
  final list = [
    for (final vm in ref.watch(allSectorsProvider))
      if (settings.isFollowed(vm.config.id)) ...vm.alerts,
  ]..sort((a, b) => b.date.compareTo(a.date));
  return list;
});

final budgetProvider = Provider<BudgetPlan?>((ref) {
  final config = ref.watch(configProvider).valueOrNull;
  if (config == null) return null;
  final s = ref.watch(settingsProvider);
  return buildBudget(
    salary: s.salary,
    dcaPct: s.dcaPct,
    buckets: s.buckets,
    mainSplit: s.mainSplit,
    mainAssets: config.mainPort,
    sectorWeights: s.sectorWeights,
    sectors: ref.watch(allSectorsProvider),
  );
});

final newsProvider = FutureProvider<List<NewsItem>>((ref) => ref.watch(repositoryProvider).loadNews());

final briefsProvider = FutureProvider<List<Brief>>((ref) => ref.watch(repositoryProvider).loadBriefs());

final priceEventsProvider = FutureProvider<PriceEvents>((ref) => ref.watch(repositoryProvider).loadPriceEvents());

/// Price events for tickers the user can see (sector stocks + main-port proxies).
final followedPriceEventsProvider = Provider<List<PriceEvent>>((ref) {
  final ev = ref.watch(priceEventsProvider).valueOrNull?.events ?? const [];
  final config = ref.watch(configProvider).valueOrNull;
  final settings = ref.watch(settingsProvider);
  if (config == null) return ev;
  final tickers = <String>{
    for (final a in config.mainPort) a.proxy,
    for (final s in config.sectors)
      if (settings.isFollowed(s.id)) ...s.stocks.map((x) => x.ticker),
  };
  return [for (final e in ev) if (tickers.contains(e.ticker)) e];
});

final flexProvider = Provider<FlexPlan?>((ref) {
  final plan = ref.watch(budgetProvider);
  final config = ref.watch(configProvider).valueOrNull;
  final market = ref.watch(marketProvider).valueOrNull;
  if (plan == null || config == null) return null;
  final s = ref.watch(settingsProvider);
  return buildFlex(
    plan: plan,
    mainAssets: config.mainPort,
    market: market ?? MarketData.empty,
    mode: s.flexMode,
    reserve: s.planReserve,
    capMonths: s.reserveCapMonths,
    stockCapPct: s.stockCapPct,
    emergencyOk: s.emergencyOk,
    targetTilt: ref.watch(rebalanceTiltProvider),
  );
});

final portfolioProvider = Provider<PortfolioView?>((ref) {
  final config = ref.watch(configProvider).valueOrNull;
  if (config == null) return null;
  final holdings = ref.watch(settingsProvider.select((s) => s.holdings));
  final market = ref.watch(marketProvider).valueOrNull ?? MarketData.empty;
  return buildPortfolio(holdings, config, market);
});

/// Target weight (share of the monthly base) per plan line key.
final targetWeightsProvider = Provider<Map<String, double>>((ref) {
  final plan = ref.watch(budgetProvider);
  final config = ref.watch(configProvider).valueOrNull;
  if (plan == null || config == null) return const {};
  final raw = <String, double>{};
  for (final (i, l) in plan.mainLines.indexed) {
    if (i < config.mainPort.length) raw['main:${config.mainPort[i].key}'] = l.amount;
  }
  for (final sb in plan.sectors) {
    for (final l in sb.lines) {
      raw['${sb.vm.config.id}:${l.label}'] = l.amount;
    }
  }
  final total = raw.values.fold(0.0, (a, b) => a + b);
  return total <= 0 ? const {} : {for (final e in raw.entries) e.key: e.value / total};
});

/// Rebalancing factors: >1 for lines below target, <1 above (bounded 0.5–2).
final rebalanceTiltProvider = Provider<Map<String, double>>((ref) {
  final s = ref.watch(settingsProvider);
  if (!s.rebalance) return const {};
  final pv = ref.watch(portfolioProvider);
  if (pv == null || pv.isEmpty) return const {};
  final targets = ref.watch(targetWeightsProvider);
  final heldKeys = {for (final v in pv.values) v.holding.key};
  if (!targets.keys.any(heldKeys.contains)) return const {};
  final planTotal = pv.values.where((v) => targets.containsKey(v.holding.key)).fold(0.0, (a, b) => a + b.valueThb);
  if (planTotal <= 0) return const {};
  return {
    for (final e in targets.entries)
      if (e.value > 0)
        e.key: () {
          final actual = pv.values.where((v) => v.holding.key == e.key).fold(0.0, (a, b) => a + b.valueThb) / planTotal;
          if (actual <= 0) return 2.0;
          return (e.value / actual).clamp(0.5, 2.0).toDouble();
        }(),
  };
});

/// Targets that touch money the owner actually has: main port, funded sectors and
/// anything entered as a holding (keys, sector ids and tickers).
final myTargetsProvider = Provider<Set<String>>((ref) {
  final config = ref.watch(configProvider).valueOrNull;
  final holdings = ref.watch(settingsProvider.select((s) => s.holdings));
  final out = <String>{};
  if (config != null) {
    for (final a in config.mainPort) {
      out.add('main:${a.key}');
      out.add(a.proxy);
    }
    for (final sec in config.sectors) {
      if (!sec.funded) continue;
      out.add(sec.id);
      out.addAll(sec.stocks.map((x) => x.ticker));
    }
  }
  for (final h in holdings) {
    if (h.isEmpty) continue;
    out.add(h.key);
    if (h.ticker != null) out.add(h.ticker!);
    if (!h.key.startsWith('main:')) out.add(h.key.split(':').first);
  }
  return out;
});

bool newsTouches(NewsItem n, Set<String> mine) => n.impacts.any((i) => mine.contains(i.target));

/// Last time the alerts tab was opened; before the first visit, the last two days count as new.
String effectiveSeen(String seenAt) =>
    seenAt.isNotEmpty ? seenAt : DateTime.now().toUtc().subtract(const Duration(days: 2)).toIso8601String().substring(0, 10);

bool isNewSince(String key, String seen) => key.compareTo(seen) > 0;

/// Badge count: only things worth opening the tab for, and only since the last visit.
final unreadAlertsProvider = Provider<int>((ref) {
  final seen = effectiveSeen(ref.watch(settingsProvider.select((s) => s.alertsSeenAt)));
  final day = seen.length >= 10 ? seen.substring(0, 10) : seen;
  final mine = ref.watch(myTargetsProvider);
  final news = ref.watch(newsProvider).valueOrNull ?? const <NewsItem>[];
  return news.where((n) => n.level == 'high' && isNewSince(n.sortKey, seen)).length +
      ref.watch(followedPriceEventsProvider).where((e) => mine.contains(e.ticker) && isNewSince(e.date, day)).length +
      ref.watch(allAlertsProvider).where((a) => a.kind == AlertKind.status && isNewSince(a.date, day)).length;
});

/// How fresh the data on screen is.
class DataStatus {
  const DataStatus({required this.oldestSectorDate, required this.newestSectorDate, required this.priceAsOf, required this.offline});

  final String? oldestSectorDate;
  final String? newestSectorDate;
  final String? priceAsOf;
  final bool offline;

  /// Hours since the oldest followed sector reading (date at 08:00 Bangkok).
  double? get sectorAgeHours {
    final d = oldestSectorDate == null ? null : DateTime.tryParse('${oldestSectorDate}T01:00:00Z');
    return d == null ? null : DateTime.now().toUtc().difference(d).inMinutes / 60;
  }

  bool get stale => offline || (sectorAgeHours ?? 0) > 36;
}

final dataStatusProvider = Provider<DataStatus>((ref) {
  final config = ref.watch(configProvider).valueOrNull;
  final s = ref.watch(settingsProvider);
  var offline = false;
  String? oldest, newest;
  if (config != null) {
    for (final sec in config.sectors) {
      if (!s.isFollowed(sec.id)) continue;
      final r = ref.watch(readingsProvider(sec.dataPath)).valueOrNull;
      if (r == null) continue;
      if (r.fromCache) offline = true;
      if (r.value.isEmpty) continue;
      final d = r.value.last.date;
      if (oldest == null || d.compareTo(oldest) < 0) oldest = d;
      if (newest == null || d.compareTo(newest) > 0) newest = d;
    }
  }
  final market = ref.watch(marketProvider).valueOrNull;
  if (market?.fromCache ?? false) offline = true;
  return DataStatus(oldestSectorDate: oldest, newestSectorDate: newest, priceAsOf: market?.quotes['SPY']?.asOf, offline: offline);
});

final taxProvider = Provider<TaxResult>((ref) {
  final s = ref.watch(settingsProvider);
  return planTax(TaxInput(
    monthlySalary: s.salary,
    bonusMonths: s.bonusMonths,
    lifeInsurance: s.lifeInsurance,
    healthInsurance: s.healthInsurance,
    providentFund: s.providentFund,
    otherDeductions: s.otherDeductions,
    esgBought: s.esgBought,
    rmfBought: s.rmfBought,
    targetNet: s.targetNet,
  ));
});

/// Refresh every remote file.
void refreshAll(WidgetRef ref) {
  ref.invalidate(configProvider);
  ref.invalidate(marketProvider);
  ref.invalidate(readingsProvider);
  ref.invalidate(backtestProvider);
  ref.invalidate(newsProvider);
  ref.invalidate(briefsProvider);
  ref.invalidate(priceEventsProvider);
}

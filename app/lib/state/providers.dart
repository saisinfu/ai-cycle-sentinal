import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/budget.dart';
import '../data/config.dart';
import '../data/engine.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'settings.dart';

final repositoryProvider = Provider<Repository>((ref) => Repository());

final configProvider = FutureProvider<AppConfig>((ref) => ref.watch(repositoryProvider).loadConfig());

final marketProvider = FutureProvider<MarketData>((ref) => ref.watch(repositoryProvider).loadMarket());

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
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/engine.dart';
import '../data/models.dart';
import '../data/repository.dart';

final repositoryProvider = Provider<ReadingsRepository>((ref) => ReadingsRepository());

/// Downloads the latest readings (falls back to the last saved copy offline).
final readingsProvider = FutureProvider<ReadingsResult>((ref) => ref.watch(repositoryProvider).load());

/// true = real data, false = simulated scenarios.
final liveModeProvider = StateProvider<bool>((ref) => true);

final scenarioProvider = StateProvider<String>((ref) => 'early_warning');

final attributionDaysProvider = StateProvider<int>((ref) => 7);

final sampleVMProvider = Provider.family<DashboardVM, String>(
  (ref, scenario) => DashboardVM(live: false, scored: scoreAll(sampleReadings(scenario))),
);

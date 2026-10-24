import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../state/providers.dart';
import 'alerts_screen.dart';
import 'budget_screen.dart';
import 'overview_screen.dart';
import 'settings_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _tab = 0;

  void _go(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    final latest = ref.watch(allSectorsProvider).map((s) => s.latest.reading.date).fold<String?>(null, (a, b) => a == null || b.compareTo(a) > 0 ? b : a);
    final todayAlerts = latest == null ? 0 : ref.watch(allAlertsProvider).where((a) => a.date == latest).length;
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          OverviewScreen(onOpenBudget: () => _go(1)),
          BudgetScreen(onOpenSettings: () => _go(3)),
          const AlertsScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _go,
        destinations: [
          const NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'ภาพรวม'),
          const NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'งบเดือนนี้'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: todayAlerts > 0,
              backgroundColor: AppColors.red,
              label: Text('$todayAlerts'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
            selectedIcon: const Icon(Icons.notifications_rounded),
            label: 'แจ้งเตือน',
          ),
          const NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'ตั้งค่า'),
        ],
      ),
    );
  }
}

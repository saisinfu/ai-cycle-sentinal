import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../state/providers.dart';
import '../state/settings.dart';
import 'alerts_screen.dart';
import 'budget_screen.dart';
import 'overview_screen.dart';
import 'portfolio_screen.dart';
import 'settings_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _overview = 0, _budget = 1, _portfolio = 2, _alerts = 3, _settings = 4;

  int _tab = _overview;

  /// "Seen" mark as it was when the alerts tab was last opened, so new items stay marked while reading.
  String _seenBefore = '';

  void _go(int i) {
    if (i == _alerts && _tab != _alerts) {
      final n = ref.read(settingsProvider.notifier);
      _seenBefore = effectiveSeen(ref.read(settingsProvider).alertsSeenAt);
      n.update((s) => s.copyWith(alertsSeenAt: DateTime.now().toUtc().toIso8601String()));
    }
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadAlertsProvider);
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          OverviewScreen(onOpenBudget: () => _go(_budget), onOpenAlerts: () => _go(_alerts), onOpenPortfolio: () => _go(_portfolio)),
          BudgetScreen(onOpenSettings: () => _go(_settings)),
          PortfolioScreen(onOpenBudget: () => _go(_budget)),
          AlertsScreen(seenBefore: _seenBefore),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _go,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          const NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'ภาพรวม'),
          const NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'งบเดือนนี้'),
          const NavigationDestination(icon: Icon(Icons.pie_chart_outline), selectedIcon: Icon(Icons.pie_chart), label: 'พอร์ต'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unread > 0 && _tab != _alerts,
              backgroundColor: AppColors.buy,
              textColor: AppColors.background,
              label: Text('$unread'),
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

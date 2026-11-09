import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/engine.dart';
import '../data/feed.dart';
import '../state/providers.dart';
import '../state/settings.dart';
import 'alerts_screen.dart';
import 'briefs_screen.dart';
import 'news_screen.dart';
import 'sector_screen.dart';
import 'widgets/common.dart';
import 'widgets/gauge.dart';
import 'widgets/market_pulse.dart';

class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key, required this.onOpenBudget, required this.onOpenAlerts});

  final VoidCallback onOpenBudget;
  final VoidCallback onOpenAlerts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider);
    final settings = ref.watch(settingsProvider);
    final budget = ref.watch(budgetProvider);
    final alerts = ref.watch(allAlertsProvider);
    final sectors = ref.watch(allSectorsProvider).where((vm) => settings.isFollowed(vm.config.id)).toList();
    final latestDate = sectors.isEmpty ? null : sectors.map((s) => s.latest.reading.date).reduce((a, b) => a.compareTo(b) > 0 ? a : b);
    final today = latestDate == null ? const <AlertEvent>[] : alerts.where((a) => a.date == latestDate).toList();
    final market = ref.watch(marketProvider).valueOrNull;
    final flex = ref.watch(flexProvider);
    final prices = ref.watch(followedPriceEventsProvider);
    final lastTrading = market?.quotes['SPY']?.asOf;
    final todayPrices = lastTrading == null ? const <PriceEvent>[] : prices.where((e) => e.date.compareTo(lastTrading) >= 0).toList();
    final briefs = ref.watch(briefsProvider).valueOrNull ?? const <Brief>[];
    final cutoff = isoDate(DateTime.now().subtract(const Duration(days: 4)));
    final news = (ref.watch(newsProvider).valueOrNull ?? const <NewsItem>[])
        .where((n) => n.level != 'low' && n.date.compareTo(cutoff) >= 0)
        .take(3)
        .toList();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI-CYCLE SENTINEL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 2)),
            Text(latestDate == null ? 'กำลังโหลด…' : 'ข้อมูลล่าสุด ${thDateLong(latestDate)}',
                style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          ],
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.text,
        backgroundColor: AppColors.surface,
        onRefresh: () async => refreshAll(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (config.hasError && sectors.isEmpty)
              ErrorCard(message: '${config.error}', onRetry: () => refreshAll(ref))
            else if (sectors.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: Center(child: CircularProgressIndicator(color: AppColors.text)),
              )
            else ...[
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('สรุปวันนี้'),
                    const SizedBox(height: 8),
                    if (todayPrices.isNotEmpty)
                      InkWell(
                        onTap: onOpenAlerts,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.trending_down, size: 16, color: AppColors.red),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'ราคาร่วงแรง ${todayPrices.length} ตัว: ${todayPrices.map((e) => e.ticker).toSet().join(', ')}',
                                  style: const TextStyle(fontSize: 14, height: 1.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (today.isEmpty && todayPrices.isEmpty)
                      const Text('ไม่มีหมวดไหนเปลี่ยนสถานะ และไม่มีหุ้นร่วงแรงใหม่', style: TextStyle(fontSize: 14, height: 1.5))
                    else if (today.isEmpty)
                      const Text('คะแนนพื้นฐานของทุกหมวดยังไม่เปลี่ยนสถานะ', style: TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5))
                    else
                      for (final a in today.take(3))
                        InkWell(
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AlertDetailScreen(event: a))),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(top: 7, right: 10),
                                  decoration: BoxDecoration(color: zoneColor(a.zone), shape: BoxShape.circle),
                                ),
                                Expanded(child: Text('${a.title} · ${a.message}', style: const TextStyle(fontSize: 14, height: 1.5))),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              ),
              if (briefs.isNotEmpty) ...[
                const SectionHeader(title: 'สรุปล่าสุดจาก Claude'),
                BriefCard(
                  brief: briefs.first,
                  onMore: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BriefsScreen())),
                ),
              ],
              if (news.isNotEmpty) ...[
                SectionHeader(title: 'ข่าวสำคัญล่าสุด', trailing: 'ดูทั้งหมด', onTrailing: onOpenAlerts),
                for (final n in news) Padding(padding: const EdgeInsets.only(bottom: 8), child: NewsTile(item: n, compact: true)),
              ],
              if (budget != null) ...[
                const SizedBox(height: kGap),
                Material(
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius), side: const BorderSide(color: AppColors.line)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(kRadius),
                    onTap: onOpenBudget,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Eyebrow('งบลงทุนเดือน${thMonthYear(DateTime.now())}'),
                                const SizedBox(height: 6),
                                Text('${baht((flex?.plannedTotal ?? budget.main + budget.tech) + budget.tax)} บาท',
                                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, fontFeatures: tabular)),
                                const SizedBox(height: 2),
                                Text(
                                  flex == null || flex.used == 0 && flex.saved == 0
                                      ? 'หลัก ${baht(budget.main)} · Tech/AI ${baht(budget.tech)} · ลดหย่อน ${baht(budget.tax)}'
                                      : 'งบฐาน ${baht(budget.total)} · ใช้เงินสำรอง ${baht(flex.used)} · เก็บเข้าสำรอง ${baht(flex.saved)}',
                                  style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: AppColors.muted),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (market != null && market.quotes.isNotEmpty) ...[
                const SizedBox(height: kGap),
                MarketPulseCard(
                  market: market,
                  sectors: [for (final vm in sectors) vm.config],
                  onSector: (id) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SectorScreen(sectorId: id))),
                ),
              ],
              SectionHeader(title: '${sectors.length} หมวดที่ติดตาม', trailing: 'คะแนนพื้นฐาน 0–100'),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.78,
                children: [for (final vm in sectors) _SectorTile(vm: vm, settings: settings)],
              ),
              const Disclaimer(),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectorTile extends StatelessWidget {
  const _SectorTile({required this.vm, required this.settings});

  final SectorVM vm;
  final UserSettings settings;

  @override
  Widget build(BuildContext context) {
    final z = vm.latest.zone;
    final color = zoneColor(z);
    final changedToday = vm.previousZone != null && vm.previousZone != z;
    final w = settings.sectorWeights[vm.config.id] ?? 0;
    final buys = vm.recommendations.where((r) => r.cell.allocationPct > 0).map((r) => r.stock.ticker).toList();
    final action = buys.isEmpty ? 'พัก DCA ทั้งหมวด' : 'DCA: ${buys.join(', ')}';
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadius),
        side: BorderSide(color: changedToday ? color.withAlpha(110) : AppColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadius),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SectorScreen(sectorId: vm.config.id))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(sectorIcon(vm.config.icon), size: 18, color: AppColors.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(vm.config.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                  ),
                ],
              ),
              const Spacer(),
              Center(child: Gauge(score: vm.latest.index, color: color, size: 72, animate: false)),
              const Spacer(),
              StatusPill(label: zoneName(z), color: color),
              const SizedBox(height: 6),
              Text(vm.config.stocks.map((s) => s.ticker).join(' · '), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              Text(action, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              Text(w > 0 ? 'ได้งบ ${w.toStringAsFixed(0)}% ของ Tech/AI' : 'ติดตามอย่างเดียว ยังไม่ใส่งบ',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

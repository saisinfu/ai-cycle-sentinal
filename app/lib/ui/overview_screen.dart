import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/engine.dart';
import '../state/providers.dart';
import '../state/settings.dart';
import 'alerts_screen.dart';
import 'sector_screen.dart';
import 'widgets/common.dart';
import 'widgets/gauge.dart';

class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key, required this.onOpenBudget});

  final VoidCallback onOpenBudget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider);
    final settings = ref.watch(settingsProvider);
    final budget = ref.watch(budgetProvider);
    final alerts = ref.watch(allAlertsProvider);
    final sectors = ref.watch(allSectorsProvider).where((vm) => settings.isFollowed(vm.config.id)).toList();
    final latestDate = sectors.isEmpty ? null : sectors.map((s) => s.latest.reading.date).reduce((a, b) => a.compareTo(b) > 0 ? a : b);
    final today = latestDate == null ? const <AlertEvent>[] : alerts.where((a) => a.date == latestDate).toList();

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
                    if (today.isEmpty)
                      const Text('ไม่มีหมวดไหนเปลี่ยนสถานะ และไม่มีสัญญาณพิเศษใหม่', style: TextStyle(fontSize: 14, height: 1.5))
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
                                Text('${baht(budget.total)} บาท',
                                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, fontFeatures: tabular)),
                                const SizedBox(height: 2),
                                Text(
                                  'หลัก ${baht(budget.main)} · Tech/AI ${baht(budget.tech)} · ลดหย่อน ${baht(budget.tax)}',
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
              SectionHeader(title: '${sectors.length} หมวดที่ติดตาม', trailing: 'คะแนน 0–100'),
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

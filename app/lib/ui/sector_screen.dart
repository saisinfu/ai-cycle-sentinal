import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/engine.dart';
import '../state/providers.dart';
import 'method_screen.dart';
import 'widgets/common.dart';
import 'widgets/gauge.dart';
import 'widgets/history_card.dart';
import 'widgets/stock_card.dart';
import 'widgets/waterfall.dart';

class SectorScreen extends ConsumerStatefulWidget {
  const SectorScreen({super.key, required this.sectorId});

  final String sectorId;

  @override
  ConsumerState<SectorScreen> createState() => _SectorScreenState();
}

class _SectorScreenState extends ConsumerState<SectorScreen> {
  int _window = 7;

  void _openMethod() =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => MethodScreen(sectorId: widget.sectorId)));

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(sectorVMProvider(widget.sectorId));
    final vm = async.valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(vm?.config.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [IconButton(tooltip: 'วิธีคำนวณ', onPressed: _openMethod, icon: const Icon(Icons.info_outline))],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.text)),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: ErrorCard(message: '$e', onRetry: () => refreshAll(ref)),
        ),
        data: (vm) {
          if (vm == null) {
            return const Center(child: Text('ยังไม่มีข้อมูลของหมวดนี้', style: TextStyle(color: AppColors.muted)));
          }
          final latest = vm.latest;
          final color = zoneColor(latest.zone);
          final att = vm.attribution[_window];
          final active = activeAlerts(vm.config, latest);
          return RefreshIndicator(
            color: AppColors.text,
            backgroundColor: AppColors.surface,
            onRefresh: () async => refreshAll(ref),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                Text('ข้อมูลจริง · อัปเดต ${thDateLong(latest.reading.date)} · ${confidenceTh(vm.config.confidence)}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                const SizedBox(height: kGap),
                SurfaceCard(
                  borderColor: color.withAlpha(60),
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                  child: Column(
                    children: [
                      const Eyebrow('ดัชนีสุขภาพของหมวด'),
                      const SizedBox(height: 10),
                      Gauge(score: latest.index, color: color, size: 200),
                      const SizedBox(height: 6),
                      Text(zoneLabel(latest.zone),
                          textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(vm.config.summary[latest.zone] ?? '',
                          textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 1.5)),
                      const SizedBox(height: 6),
                      Text('อยู่ในสถานะนี้ตั้งแต่ ${thDate(vm.statusSince)} · ${vm.config.confidenceNote}',
                          textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.4)),
                    ],
                  ),
                ),
                for (final a in active)
                  Padding(
                    padding: const EdgeInsets.only(top: kGap),
                    child: SurfaceCard(
                      borderColor: zoneColor(a.zone).withAlpha(110),
                      color: zoneColor(a.zone).withAlpha(20),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline, color: zoneColor(a.zone), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text.rich(TextSpan(children: [
                              TextSpan(text: a.title, style: TextStyle(color: zoneColor(a.zone), fontWeight: FontWeight.w700)),
                              TextSpan(text: ' · ${fillTemplate(a.message, latest.reading.indicators)}'),
                            ]), style: const TextStyle(fontSize: 13.5, height: 1.4)),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: kGap),
                HistoryCard(key: ValueKey('h-${vm.config.id}-${vm.scored.length}'), scored: vm.scored),
                const SizedBox(height: kGap),
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(child: Eyebrow('ทำไมคะแนนถึงเปลี่ยน')),
                          for (final d in const [7, 30, 90]) ...[
                            const SizedBox(width: 6),
                            ToggleChip(label: '$d วัน', selected: _window == d, onTap: () => setState(() => _window = d)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (att == null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: Text('ต้องมีข้อมูลย้อนหลังอย่างน้อย $_window วันจึงจะเทียบได้',
                                style: const TextStyle(color: AppColors.muted, fontSize: 13.5)),
                          ),
                        )
                      else
                        Waterfall(a: att),
                    ],
                  ),
                ),
                SectionHeader(title: '5 สัญญาณหลัก', trailing: 'คำนวณอย่างไร', onTrailing: _openMethod),
                SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (i, s) in latest.subs.indexed)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            border: i == latest.subs.length - 1 ? null : const Border(bottom: BorderSide(color: AppColors.line)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: Text(s.spec.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                                  const SizedBox(width: 8),
                                  StatusPill(label: levelTh(s.level), color: zoneColor(s.level)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('${s.display} · คะแนน ${s.score.toStringAsFixed(0)} · น้ำหนัก ${(s.spec.weight * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(fontSize: 12.5, color: AppColors.muted, fontFeatures: tabular)),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  SourceTag(s.spec.isEstimate ? Provenance.estimate : Provenance.data),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '${s.spec.source} · ${confidenceTh(latest.reading.confidence[s.spec.key] ?? (s.spec.isEstimate ? 'low' : 'medium'))}',
                                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                                    ),
                                  ),
                                ],
                              ),
                              if (latest.reading.notes[s.spec.key] != null) ...[
                                const SizedBox(height: 6),
                                Text(latest.reading.notes[s.spec.key]!,
                                    style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.45)),
                              ],
                              LinkRow(links: [
                                for (final l in latest.reading.sources.where((l) => l.key == s.spec.key)) (l.label, l.url),
                              ]),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                SectionHeader(
                  title: 'แนวทางจัดพอร์ต',
                  trailing: cashReservePct(vm.config, latest.zone) > 0
                      ? 'เงินสดสำรอง ${cashReservePct(vm.config, latest.zone).toStringAsFixed(0)}%'
                      : 'ลงทุนครบ 100%',
                ),
                for (final r in vm.recommendations)
                  StockCard(key: ValueKey('s-${r.stock.ticker}'), rec: r, vm: vm, onEditRules: _openMethod, onMethod: _openMethod),
                const Disclaimer(),
              ],
            ),
          );
        },
      ),
    );
  }
}

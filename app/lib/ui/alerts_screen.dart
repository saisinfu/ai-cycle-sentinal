import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/budget.dart';
import '../data/config.dart';
import '../data/engine.dart';
import '../data/zone.dart';
import '../state/providers.dart';
import 'method_screen.dart';
import 'sector_screen.dart';
import 'widgets/common.dart';
import 'widgets/waterfall.dart';

class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  String? _filter;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(allAlertsProvider);
    final sectors = ref.watch(allSectorsProvider);
    final list = _filter == null ? all : all.where((a) => a.sector.id == _filter).toList();
    String? lastDate;
    return Scaffold(
      appBar: AppBar(title: const Text('แจ้งเตือน', style: TextStyle(fontWeight: FontWeight.w700))),
      body: RefreshIndicator(
        color: AppColors.text,
        backgroundColor: AppColors.surface,
        onRefresh: () async => refreshAll(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            const Text('การเปลี่ยนสถานะและสัญญาณพิเศษของทุกหมวด แตะเพื่อดูเหตุผลและแหล่งข้อมูล',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ToggleChip(label: 'ทั้งหมด', selected: _filter == null, onTap: () => setState(() => _filter = null)),
                  for (final vm in sectors) ...[
                    const SizedBox(width: 6),
                    ToggleChip(label: vm.config.name, selected: _filter == vm.config.id, onTap: () => setState(() => _filter = vm.config.id)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(
                  child: Text('ยังไม่มีแจ้งเตือน\nจะแสดงเมื่อหมวดเปลี่ยนสถานะหรือมีสัญญาณพิเศษ',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                ),
              ),
            for (final a in list) ...[
              if (a.date != lastDate) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Eyebrow(() {
                    lastDate = a.date;
                    return thDateLong(a.date);
                  }()),
                ),
              ],
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: a.kind == AlertKind.status ? zoneColor(a.zone).withAlpha(90) : AppColors.line),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AlertDetailScreen(event: a))),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(top: 6, right: 10),
                            decoration: BoxDecoration(color: zoneColor(a.zone), shape: BoxShape.circle),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 3),
                                Text(a.message, style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.45)),
                                const SizedBox(height: 4),
                                const Text('ดูเหตุผลและแหล่งข้อมูล ›', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Why an alert fired: threshold, drivers with sources, what the rules say to do.
class AlertDetailScreen extends ConsumerWidget {
  const AlertDetailScreen({super.key, required this.event});

  final AlertEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = event;
    final cfg = e.sector;
    final color = zoneColor(e.zone);
    final drivers = e.drivers;
    final to = e.to;
    final cells = cfg.rules[to.zone] ?? const {};
    final actions = [
      for (final s in cfg.stocks)
        if (cells[s.ticker] != null)
          '${s.ticker}: ${cells[s.ticker]!.action == StockAction.reduceHoldings ? 'ทบทวนลด ${cells[s.ticker]!.trimPct?.toStringAsFixed(0)}% ของที่ถือ' : cells[s.ticker]!.allocationPct > 0 ? '${actionLabel(cells[s.ticker]!.action)} ${cells[s.ticker]!.allocationPct.toStringAsFixed(0)}% ของงบหมวด' : actionLabel(cells[s.ticker]!.action)}',
    ];
    final estimates = cfg.signals.where((s) => s.isEstimate).length;

    return Scaffold(
      appBar: AppBar(title: const Text('รายละเอียดแจ้งเตือน', style: TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          SurfaceCard(
            borderColor: color.withAlpha(100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusPill(label: '${cfg.name} · ${zoneName(to.zone)}', color: color),
                const SizedBox(height: 10),
                Text(e.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.3)),
                const SizedBox(height: 6),
                Text(thDateLong(e.date), style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                const SizedBox(height: 10),
                Text.rich(TextSpan(children: [
                  TextSpan(text: '${e.from.index.toStringAsFixed(1)}  →  ', style: const TextStyle(color: AppColors.muted, fontSize: 15)),
                  TextSpan(text: to.index.toStringAsFixed(1), style: TextStyle(color: zoneColor(to.zone), fontSize: 26, fontWeight: FontWeight.w700)),
                  TextSpan(text: '  (${signed(drivers.change)} แต้ม)', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                ])),
              ],
            ),
          ),
          const SectionHeader(title: 'ทำไมถึงแจ้งเตือน'),
          if (e.kind == AlertKind.status)
            ExplainBlock(
              title: crossingText(e.from.zone, to.zone),
              tags: const [Provenance.calc],
              body: 'สถานะจะเปลี่ยนเมื่อคะแนนผ่านเส้นไปอีก ${hysteresisBand.toStringAsFixed(0)} แต้ม เพื่อไม่ให้แจ้งเตือนซ้ำเมื่อคะแนนแกว่งรอบเส้น '
                  'ครั้งก่อน (${thDate(e.from.reading.date)}) ${e.from.index.toStringAsFixed(1)} → ครั้งนี้ ${to.index.toStringAsFixed(1)}',
            )
          else
            ExplainBlock(
              title: e.rule?.title ?? e.title,
              tags: const [Provenance.data],
              body: '${e.message}\nแจ้งเตือนครั้งเดียวเมื่อค่าเพิ่งผ่านเกณฑ์ และจะเตือนใหม่เมื่อค่ากลับมาแล้วผ่านเกณฑ์อีกครั้ง',
            ),
          const SectionHeader(title: 'อะไรทำให้คะแนนเปลี่ยน'),
          SurfaceCard(child: Waterfall(a: drivers)),
          const SizedBox(height: kGap),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, c) in drivers.contributions.where((c) => c.delta != 0).take(3).indexed)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(c.sub.spec.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                            Text(signed(c.delta, 2),
                                style: TextStyle(fontSize: 13, color: c.delta < 0 ? AppColors.red : AppColors.green, fontFeatures: tabular)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('ตอนนี้ ${c.sub.display}', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                        if (to.reading.notes[c.sub.spec.key] != null) ...[
                          const SizedBox(height: 4),
                          Text(to.reading.notes[c.sub.spec.key]!, style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.45)),
                        ],
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            SourceTag(c.sub.spec.isEstimate ? Provenance.estimate : Provenance.data),
                            const SizedBox(width: 6),
                            Expanded(
                              child: LinkRow(
                                prefix: c.sub.spec.source,
                                links: [for (final l in to.reading.sources.where((l) => l.key == c.sub.spec.key)) (l.label, l.url)],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SectionHeader(title: 'ควรทำอะไร'),
          ExplainBlock(
            title: actions.isEmpty ? 'ไม่มีการเปลี่ยนแปลงตามกฎ' : actions.join('\n'),
            tags: const [Provenance.rule],
            body: '${cfg.rulesFromUser ? 'มาจากกฎจัดพอร์ตที่คุณกำหนด' : 'มาจากกฎร่างตั้งต้นที่ Claude เสนอ'} สำหรับสถานะ "${zoneName(to.zone)}" '
                'แอปไม่ได้ประเมินราคาหุ้นรายตัว',
          ),
          const SizedBox(height: kGap),
          SurfaceCard(
            color: AppColors.background,
            child: Text(
              'ความน่าเชื่อถือของหมวดนี้: ${confidenceTh(cfg.confidence)} · $estimates จาก ${cfg.signals.length} สัญญาณเป็นค่าประมาณ '
              'และเกณฑ์คะแนนยังไม่ได้ทดสอบย้อนหลัง ควรใช้ประกอบการตัดสินใจ ไม่ใช่ทำตามทันที',
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.5),
            ),
          ),
          const SizedBox(height: kGap),
          Row(
            children: [
              ToggleChip(
                label: 'ดูหมวด${cfg.name}',
                selected: true,
                expand: true,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SectorScreen(sectorId: cfg.id))),
              ),
              const SizedBox(width: 8),
              ToggleChip(
                label: 'วิธีคำนวณ',
                selected: false,
                expand: true,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MethodScreen(sectorId: cfg.id))),
              ),
            ],
          ),
          const Disclaimer(),
        ],
      ),
    );
  }
}

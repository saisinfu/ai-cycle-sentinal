import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/backtest.dart';
import '../data/engine.dart';
import '../data/zone.dart';
import '../state/providers.dart';
import 'widgets/common.dart';

/// How well each sector's rules held up on historical data.
class BacktestScreen extends ConsumerStatefulWidget {
  const BacktestScreen({super.key, this.sectorId});

  final String? sectorId;

  @override
  ConsumerState<BacktestScreen> createState() => _BacktestScreenState();
}

class _BacktestScreenState extends ConsumerState<BacktestScreen> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(backtestProvider);
    final config = ref.watch(configProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('ผลทดสอบย้อนหลัง', style: TextStyle(fontWeight: FontWeight.w700))),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.text)),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: ErrorCard(message: '$e', onRetry: () => ref.invalidate(backtestProvider)),
        ),
        data: (summary) {
          if (summary == null || summary.sectors.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text('ยังไม่มีผลทดสอบย้อนหลัง', style: TextStyle(color: AppColors.muted)),
            );
          }
          final ids = [
            for (final s in config?.sectors ?? const []) if (summary.sectors.containsKey(s.id)) s.id,
            for (final id in summary.sectors.keys) if (config?.sector(id) == null) id,
          ];
          final sel = _selected ?? (ids.contains(widget.sectorId) ? widget.sectorId! : ids.first);
          final bt = summary.sectors[sel]!;
          return RefreshIndicator(
            color: AppColors.text,
            onRefresh: () async => ref.invalidate(backtestProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                Row(
                  children: [
                    for (final id in ids) ...[
                      ToggleChip(
                        label: config?.sector(id)?.name ?? id,
                        selected: id == sel,
                        onTap: () => setState(() => _selected = id),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                if (bt.tested) ..._tested(context, bt, summary) else ..._notTested(bt),
                const Disclaimer(),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _notTested(SectorBacktest bt) => [
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StatusPill(label: 'ยังไม่ได้ทดสอบ', color: AppColors.muted),
              const SizedBox(height: 10),
              Text(bt.headline, style: const TextStyle(fontSize: 14.5, height: 1.5)),
              for (final c in bt.caveats) ...[
                const SizedBox(height: 8),
                Text(c, style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5)),
              ],
            ],
          ),
        ),
      ];

  List<Widget> _tested(BuildContext context, SectorBacktest bt, BacktestSummary summary) {
    final (vLabel, vColor) = switch (bt.verdict) {
      'helps' => ('สัญญาณช่วยได้บ้าง', AppColors.green),
      'hurts' => ('สัญญาณสวนทางผลตอบแทน', AppColors.red),
      _ => ('สัญญาณไม่ช่วยจับจังหวะ', AppColors.yellow),
    };
    return [
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusPill(label: vLabel, color: vColor),
            const SizedBox(height: 10),
            Text(bt.headline, style: const TextStyle(fontSize: 14.5, height: 1.5)),
            const SizedBox(height: 8),
            Text('ข้อมูลรายเดือน ${bt.periodFrom} ถึง ${bt.periodTo} (${bt.months} เดือน)',
                style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
          ],
        ),
      ),
      const SectionHeader(title: 'ผลตอบแทนเฉลี่ยต่อปี เมื่อ DCA เท่ากันทุกเดือน'),
      SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, r) in bt.strategies.indexed) ...[
              if (i > 0) const Divider(height: 24, color: AppColors.line),
              Text(r.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              Text('${r.from} ถึง ${r.to}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _cell('DCA ปกติ', r.plainIrr, r.plainDd, null),
                  _cell('กฎเดิม', r.previousIrr, r.previousDd, r.plainIrr),
                  _cell('กฎปัจจุบัน', r.currentIrr, r.currentDd, r.plainIrr),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'กฎเดิม = หยุด DCA และลดหุ้นเมื่อสถานะแย่ลง · กฎปัจจุบัน = DCA ต่อทุกโซน ปรับแค่น้ำหนัก และกันเงินสด 20% ในช่วงย่อยการลงทุน · '
              '"ร่วงสุด" คือมูลค่าพอร์ตที่ลดลงมากที่สุดจากจุดสูงสุด',
              style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.5),
            ),
          ],
        ),
      ),
      if (summary.chartUrl.isNotEmpty) ...[
        const SectionHeader(title: 'กราฟ'),
        SurfaceCard(
          padding: const EdgeInsets.all(8),
          child: InkWell(
            onTap: () => openLink(context, summary.chartUrl),
            child: Image.network(
              summary.chartUrl,
              loadingBuilder: (c, child, p) =>
                  p == null ? child : const SizedBox(height: 160, child: Center(child: CircularProgressIndicator(color: AppColors.text))),
              errorBuilder: (c, e, s) => const Padding(
                padding: EdgeInsets.all(16),
                child: Text('โหลดกราฟไม่ได้ แตะเพื่อเปิดในเบราว์เซอร์', style: TextStyle(color: AppColors.muted, fontSize: 13)),
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: Text('บน: ดัชนีหมวด (เขียว/เหลือง/แดง = โซน) · กลาง: ราคา · ล่าง: มูลค่าพอร์ต DCA ปกติ, กฎเดิม และกฎปัจจุบัน',
              style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.45)),
        ),
      ],
      if (bt.zones.isNotEmpty) ...[
        const SectionHeader(title: 'ผลตอบแทน 12 เดือนถัดไป แยกตามโซน (XLF)'),
        SurfaceCard(
          child: Column(
            children: [
              for (final z in bt.zones)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(zoneName(zoneFromCode(z.zone)),
                            style: TextStyle(color: zoneColor(zoneFromCode(z.zone)), fontWeight: FontWeight.w600, fontSize: 13.5)),
                      ),
                      Text(
                        '${z.months} เดือน · เฉลี่ย ${_pct(z.fwd12Mean)} · ติดลบ ${z.negShare == null ? '-' : '${(z.negShare! * 100).toStringAsFixed(0)}%'}',
                        style: const TextStyle(fontSize: 12.5, fontFeatures: tabular),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              const Text('ถ้าสัญญาณใช้ได้ โซนขยายตัวควรตามด้วยผลตอบแทนสูงกว่าโซนอื่นชัดเจน',
                  style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.45)),
            ],
          ),
        ),
      ],
      if (bt.signals.isNotEmpty) ...[
        const SectionHeader(title: 'แต่ละสัญญาณ'),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in bt.signals)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(_signalIcon(s.ic), size: 18, color: _signalColor(s.ic)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${s.label}${s.ic == null ? '' : ' (${s.ic! >= 0 ? '+' : ''}${s.ic!.toStringAsFixed(2)})'}',
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                            Text(s.verdict, style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.4)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              const Text('ตัวเลขในวงเล็บ = ค่าสหสัมพันธ์กับผลตอบแทน 12 เดือนถัดไป (−1 ถึง +1) ใกล้ 0 = แทบไม่เกี่ยวกัน',
                  style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.45)),
            ],
          ),
        ),
      ],
      if (bt.robustness.isNotEmpty) ...[
        const SectionHeader(title: 'ลองปรับเงื่อนไขแล้ว'),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (label, value) in bt.robustness)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      Text(value, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
      if (bt.caveats.isNotEmpty) ...[
        const SectionHeader(title: 'ข้อจำกัดของการทดสอบ'),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final c in bt.caveats)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('• $c', style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.5)),
                ),
            ],
          ),
        ),
      ],
      const SectionHeader(title: 'แหล่งข้อมูล'),
      SurfaceCard(
        child: LinkRow(links: [
          ...bt.sources,
          if (summary.detailsUrl.isNotEmpty) ('สคริปต์และผลทั้งหมดบน GitHub', summary.detailsUrl),
        ]),
      ),
    ];
  }

  static String _pct(double? v) => v == null ? '-' : '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}%';

  static IconData _signalIcon(double? ic) => ic == null
      ? Icons.remove_circle_outline
      : ic >= 0.07
          ? Icons.check_circle_outline
          : ic <= -0.07
              ? Icons.swap_vert
              : Icons.remove;

  static Color _signalColor(double? ic) => ic == null
      ? AppColors.muted
      : ic >= 0.07
          ? AppColors.green
          : ic <= -0.07
              ? AppColors.red
              : AppColors.yellow;

  Widget _cell(String title, double? irr, double? dd, double? base) {
    final diff = irr != null && base != null ? irr - base : null;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          Text(irr == null ? '-' : '${irr.toStringAsFixed(1)}%',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, fontFeatures: tabular)),
          if (diff != null)
            Text('${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}',
                style: TextStyle(
                    fontSize: 11.5,
                    fontFeatures: tabular,
                    color: diff.abs() < 0.15 ? AppColors.muted : (diff > 0 ? AppColors.green : AppColors.red))),
          Text(dd == null ? '' : 'ร่วงสุด ${dd.toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 11, color: AppColors.muted, fontFeatures: tabular)),
        ],
      ),
    );
  }
}

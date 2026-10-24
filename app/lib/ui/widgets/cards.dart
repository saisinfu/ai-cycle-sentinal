import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../data/engine.dart';
import '../../data/models.dart';
import 'common.dart';

/* ------------------------------ alerts ------------------------------ */

class AlertsList extends StatelessWidget {
  const AlertsList({super.key, required this.vm});

  final DashboardVM vm;

  @override
  Widget build(BuildContext context) {
    if (!vm.live) return const SizedBox.shrink();
    final zone = vm.latest.zone, prev = vm.previousZone, r = vm.latest.reading;
    final items = <(Color, String, String)>[];
    if (prev != null && prev != zone) {
      final msg = switch (zone) {
        Zone.expansion => 'คะแนนกลับเข้าโซนขยายตัว กลับมา DCA ตามปกติ',
        Zone.digestion => 'เข้าสู่ช่วงย่อยการลงทุน ทบทวนการลดสัดส่วนหุ้นชิป',
        Zone.earlyWarning =>
          prev == Zone.expansion ? 'คะแนนหลุดจากโซนขยายตัว พัก DCA ของ KLAC และ AVGO' : 'คะแนนฟื้นออกจากโซนย่อยการลงทุน',
      };
      items.add((zoneColor(zone), 'สถานะเปลี่ยน', msg));
    }
    final gpu = r.ind('gpu_spot_price_change_1m_pct');
    if (gpu < -15) items.add((AppColors.red, 'ราคาเช่า GPU ร่วงแรง', 'ลดลง ${gpu.abs().toStringAsFixed(0)}% ในเดือนนี้'));
    final grid = r.ind('power_grid_stress_level');
    if (grid > 8) items.add((AppColors.green, 'คอขวดไฟฟ้าวิกฤต', 'ระดับ ${grid.toStringAsFixed(1)}/10 เป็นปัจจัยหนุน ETN'));
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final (c, t, m) in items)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: kGap),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.withAlpha(23),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.withAlpha(90)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, color: c, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: t, style: TextStyle(color: c, fontWeight: FontWeight.w700)),
                    TextSpan(text: ' · $m'),
                  ]), style: const TextStyle(fontSize: 13.5)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/* ------------------------------ signals ------------------------------ */

const _icons = {
  'capex_vs_revenue': Icons.account_balance_outlined,
  'chip_lead_time': Icons.memory_outlined,
  'gpu_spot_price': Icons.trending_up,
  'enterprise_adoption': Icons.business_center_outlined,
  'power_grid': Icons.bolt_outlined,
};

class SignalTile extends StatelessWidget {
  const SignalTile({super.key, required this.sub});

  final SubScore sub;

  @override
  Widget build(BuildContext context) {
    final color = zoneColor(sub.level);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                  child: Icon(_icons[sub.spec.key] ?? Icons.insights, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(sub.spec.th, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                      Text(sub.spec.label, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                      const SizedBox(height: 2),
                      Text(sub.display, style: const TextStyle(fontSize: 13, color: AppColors.muted, fontFeatures: tabular)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(label: levelTh(sub.level), color: color),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: sub.score / 100,
                      minHeight: 4,
                      backgroundColor: AppColors.raised,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${sub.score.toStringAsFixed(0)} · ${(sub.spec.weight * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontFeatures: tabular),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/* ------------------------------ actions ------------------------------ */

const _reasons = {
  Zone.expansion: {
    'KLAC': 'ความต้องการเครื่องตรวจสอบการผลิตชิปเพิ่มขึ้นตามการขยายกำลังผลิต',
    'AVGO': 'ความต้องการชิป AI แบบสั่งทำและอุปกรณ์เครือข่ายกำลังขยายตัว',
    'ETN': 'งานระบบไฟฟ้าของดาต้าเซ็นเตอร์เติบโตตามการลงทุน',
  },
  Zone.earlyWarning: {
    'KLAC': 'ระยะรอชิปเริ่มสั้นลง ถือสถานะเดิมไว้',
    'AVGO': 'ราคาเช่า GPU เริ่มอ่อนตัว พักการ DCA ใหม่',
    'ETN': 'ได้ประโยชน์จากคอขวดของโครงข่ายไฟฟ้า',
  },
  Zone.digestion: {
    'KLAC': 'ยอดสั่งเครื่องจักรผลิตชิปมักลดลงก่อนในช่วงย่อยการลงทุน',
    'AVGO': 'ยอดสั่งชิปเสี่ยงลดลงเมื่อผู้ให้บริการคลาวด์ชะลอการขยาย',
    'ETN': 'งานปรับปรุงโครงข่ายไฟฟ้าเป็นโครงการหลายปี ผันผวนน้อยกว่าหุ้นชิป',
  },
};

List<String> _bullets(Recommendation rec, Scored s) {
  final r = s.reading;
  final out = [_reasons[s.zone]![rec.ticker]!, 'ดัชนี ${s.index.toStringAsFixed(1)}/100 (${zoneTh(s.zone)})'];
  switch (rec.ticker) {
    case 'KLAC':
      out.add('ระยะรอชิป ${r.ind('chip_lead_time_weeks').toStringAsFixed(0)} สัปดาห์');
      out.add('CapEx ต่อรายได้คลาวด์ ${r.ind('capex_to_cloud_revenue_ratio').toStringAsFixed(2)} เท่า');
    case 'AVGO':
      out.add('ราคาเช่า GPU \$${r.ind('gpu_spot_price_usd_hr').toStringAsFixed(2)}/ชม. '
          '(${signed(r.ind('gpu_spot_price_change_1m_pct'))}% ใน 1 เดือน)');
      out.add('ธุรกิจขนาดใหญ่ที่จ่ายเงินใช้ AI ${r.ind('enterprise_ai_adoption_pct').toStringAsFixed(1)}%');
    default:
      final g = r.ind('power_grid_stress_level');
      out.add('ความตึงตัวโครงข่ายไฟฟ้า ${g.toStringAsFixed(1)}/10');
      if (g >= 8) out.add('คอขวดไฟฟ้าอยู่ในระดับวิกฤต หนุนความต้องการอุปกรณ์ไฟฟ้า');
  }
  if (rec.trimPct != null) out.add('แนะนำทยอยขาย ${rec.trimPct!.toStringAsFixed(0)}% ของหุ้นที่ถืออยู่');
  return out;
}

class ActionCard extends StatefulWidget {
  const ActionCard({super.key, required this.rec, required this.scored, required this.live});

  final Recommendation rec;
  final Scored scored;
  final bool live;

  @override
  State<ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<ActionCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final rec = widget.rec;
    final color = actionColor(rec.action);
    final trim = rec.action == StockAction.reduceHoldings;
    final big = trim ? '−${rec.trimPct!.toStringAsFixed(0)}%' : '${rec.allocationPct.toStringAsFixed(0)}%';
    final zero = !trim && rec.allocationPct == 0;
    final asOf = widget.scored.reading.pricesAsOf;
    final priceNote = widget.live ? (asOf != null ? 'ราคาอ้างอิง ณ ${thDateLong(asOf)}' : 'ราคาอ้างอิงล่าสุด') : 'ราคาอ้างอิงสมมติ';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadius),
          side: BorderSide(color: Color.lerp(color, AppColors.line, 0.6)!),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(rec.ticker, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1)),
                          const SizedBox(height: 2),
                          Text(rec.name, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                          const SizedBox(height: 10),
                          StatusPill(label: actionTh(rec.action), color: color),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          big,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: zero ? AppColors.muted : color,
                            fontFeatures: tabular,
                          ),
                        ),
                        Text(trim ? 'ของหุ้นที่ถือ' : 'ของเงิน DCA ใหม่',
                            style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                        const SizedBox(height: 6),
                        AnimatedRotation(
                          turns: _open ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: const Icon(Icons.expand_more, color: AppColors.muted),
                        ),
                      ],
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  alignment: Alignment.topCenter,
                  child: !_open
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Divider(height: 1),
                              const SizedBox(height: 12),
                              for (final b in _bullets(rec, widget.scored))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 5),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.only(top: 8, right: 10),
                                        child: CircleAvatar(radius: 2.5, backgroundColor: AppColors.muted),
                                      ),
                                      Expanded(child: Text(b, style: const TextStyle(fontSize: 13.5, height: 1.4))),
                                    ],
                                  ),
                                ),
                              if (rec.referencePrice > 0) ...[
                                const SizedBox(height: 8),
                                const Eyebrow('ช่วงราคา (กรอบตัวอย่าง)'),
                                const SizedBox(height: 6),
                                for (final z in rec.zones)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        Expanded(child: Text(z.label, style: const TextStyle(fontSize: 13))),
                                        Text(
                                          '\$${z.low.toStringAsFixed(0)} – \$${z.high.toStringAsFixed(0)}',
                                          style: const TextStyle(fontSize: 13, fontFeatures: tabular),
                                        ),
                                      ],
                                    ),
                                  ),
                                Text('$priceNote \$${rec.referencePrice.toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                              ],
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ------------------------------ sources ------------------------------ */

const _confTh = {'high': 'ความมั่นใจสูง', 'medium': 'ความมั่นใจปานกลาง', 'low': 'ความมั่นใจต่ำ'};

class SourcesCard extends StatelessWidget {
  const SourcesCard({super.key, required this.reading});

  final Reading reading;

  Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('เปิดลิงก์ไม่ได้')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocks = [
      for (final s in signals) (s.key, s.th),
      ('prices', 'ราคาหุ้นอ้างอิง'),
    ];
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('ที่มาของข้อมูลรอบนี้'),
          const SizedBox(height: 12),
          for (final (i, (key, title)) in blocks.indexed) ...[
            if (i > 0) const Divider(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
                Text(_confTh[reading.confidence[key]] ?? '', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
              ],
            ),
            if (reading.notes[key] != null) ...[
              const SizedBox(height: 4),
              Text(reading.notes[key]!, style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.45)),
            ],
            const SizedBox(height: 4),
            Wrap(
              spacing: 14,
              runSpacing: 2,
              children: [
                for (final s in reading.sources.where((s) => s.key == key))
                  InkWell(
                    onTap: () => _open(context, s.url),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        s.label,
                        style: const TextStyle(
                          fontSize: 12.5,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.muted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

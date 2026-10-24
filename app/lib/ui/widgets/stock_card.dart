import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/budget.dart';
import '../../data/config.dart';
import '../../data/engine.dart';
import '../../data/zone.dart';
import 'common.dart';

/// Expandable recommendation card that explains WHY: status, rule, price zone.
class StockCard extends StatefulWidget {
  const StockCard({super.key, required this.rec, required this.vm, this.onEditRules, this.onMethod});

  final Recommendation rec;
  final SectorVM vm;
  final VoidCallback? onEditRules;
  final VoidCallback? onMethod;

  @override
  State<StockCard> createState() => _StockCardState();
}

class _StockCardState extends State<StockCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final rec = widget.rec;
    final vm = widget.vm;
    final cell = rec.cell;
    final color = actionColor(cell.action);
    final trim = cell.action == StockAction.reduceHoldings;
    final big = trim ? '−${(cell.trimPct ?? 0).toStringAsFixed(0)}%' : '${cell.allocationPct.toStringAsFixed(0)}%';
    final zero = !trim && cell.allocationPct == 0;
    final latest = vm.latest;
    final top = vm.attribution[30]?.contributions.first ?? vm.attribution[7]?.contributions.first;
    final strongest = [...latest.subs]..sort((a, b) => (b.weighted - b.spec.weight * 50).compareTo(a.weighted - a.spec.weight * 50));
    final mainSignal = strongest.first;
    final ruleCells = vm.config.rules[latest.zone] ?? const {};
    final ruleText = vm.config.stocks
        .map((s) {
          final c = ruleCells[s.ticker];
          if (c == null) return '${s.ticker} ถือไว้';
          if (c.action == StockAction.reduceHoldings) return '${s.ticker} ลด ${c.trimPct?.toStringAsFixed(0)}%';
          return c.allocationPct > 0 ? '${s.ticker} ${c.allocationPct.toStringAsFixed(0)}%' : '${s.ticker} ${actionLabel(c.action)}';
        })
        .join(' · ');
    final plan = rec.plan;

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
                          Text(rec.stock.ticker, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1)),
                          const SizedBox(height: 2),
                          Text(rec.stock.name, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                          const SizedBox(height: 10),
                          StatusPill(label: actionLabel(cell.action), color: color),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(big,
                            style: TextStyle(
                                fontSize: 26, fontWeight: FontWeight.w700, color: zero ? AppColors.muted : color, fontFeatures: tabular)),
                        Text(trim ? 'ของหุ้นที่ถือ' : 'ของงบหมวดนี้', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
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
                if (!_open)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('แตะเพื่อดูว่าทำไมถึงแนะนำแบบนี้', style: TextStyle(fontSize: 12, color: AppColors.muted.withAlpha(220))),
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
                              if (rec.reason.isNotEmpty) ...[
                                Text(rec.reason, style: const TextStyle(fontSize: 13.5, height: 1.45)),
                                const SizedBox(height: 12),
                              ],
                              const Eyebrow('ทำไมถึงแนะนำแบบนี้'),
                              const SizedBox(height: 8),
                              ExplainBlock(
                                title: '1. สถานะหมวด: ${zoneName(latest.zone)} (${latest.index.toStringAsFixed(1)})',
                                tags: const [Provenance.calc],
                                body: 'อยู่ในสถานะนี้ตั้งแต่ ${thDate(vm.statusSince)} '
                                    '${vm.previousZone != null && vm.previousZone != latest.zone ? '(${crossingText(vm.previousZone!, latest.zone)}) ' : ''}'
                                    '· สัญญาณที่แข็งแรงที่สุด: ${mainSignal.spec.label} ${mainSignal.display}'
                                    '${top != null ? ' · ตัวที่ขยับคะแนนมากที่สุดช่วงนี้: ${top.sub.spec.label} (${signed(top.delta, 2)} แต้ม)' : ''}',
                              ),
                              const SizedBox(height: 8),
                              ExplainBlock(
                                title: trim
                                    ? '2. ทบทวนลด ${(cell.trimPct ?? 0).toStringAsFixed(0)}% ของหุ้นที่ถือ'
                                    : '2. สัดส่วน ${cell.allocationPct.toStringAsFixed(0)}% ของงบหมวดนี้',
                                tags: const [Provenance.rule],
                                body: '${vm.config.rulesFromUser ? 'มาจากกฎจัดพอร์ตที่คุณกำหนด' : 'มาจากกฎร่างตั้งต้นที่ Claude เสนอ (รอคุณยืนยัน)'}: '
                                    'เมื่อหมวด "${zoneName(latest.zone)}" → $ruleText '
                                    'ไม่ได้มาจากการวิเคราะห์หุ้นรายตัว',
                                action: widget.onEditRules == null
                                    ? null
                                    : TextLinkButton(label: 'ดูกฎทั้งหมด', onTap: widget.onEditRules!),
                              ),
                              const SizedBox(height: 8),
                              if (plan != null)
                                ExplainBlock(
                                  title: '3. โซนราคา · ${zoneMethodName(plan.method)}',
                                  tags: [plan.method == ZoneMethod.fixed ? Provenance.rule : Provenance.calc, Provenance.data],
                                  body: [
                                    for (final z in plan.zones)
                                      '${z.label}: ${money(z.low, plan.currency)} – ${money(z.high, plan.currency)}',
                                    'จุดอ้างอิง: ${plan.anchorText}',
                                    '${plan.position} (ราคาปิด ${money(plan.price, plan.currency)}${plan.priceAsOf != null ? ' ณ ${thDate(plan.priceAsOf!)}' : ''})',
                                    'กรอบ: ${bandText(cell.action)} ของจุดอ้างอิง เป็นค่าคงที่ของแอป ไม่ใช่ราคาเป้าหมาย',
                                    if (plan.fallbackNote != null) plan.fallbackNote!,
                                  ].join('\n'),
                                  links: [if (plan.sourceUrl != null) ('ที่มาของราคา', plan.sourceUrl!)],
                                )
                              else
                                const ExplainBlock(
                                  title: '3. โซนราคา',
                                  tags: [Provenance.data],
                                  body: 'ยังไม่มีข้อมูลราคาของหุ้นตัวนี้',
                                ),
                              if (widget.onMethod != null) ...[
                                const SizedBox(height: 4),
                                TextLinkButton(label: 'วิธีคำนวณและแหล่งข้อมูลทั้งหมด', onTap: widget.onMethod!),
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

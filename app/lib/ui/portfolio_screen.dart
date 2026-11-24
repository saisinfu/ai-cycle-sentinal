import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/holdings.dart';
import '../state/providers.dart';
import '../state/settings.dart';
import 'widgets/common.dart';
import 'widgets/market_pulse.dart';

const _themeColors = <String, Color>{
  'tech': Color(0xFF64B5F6),
  'us': Color(0xFFE0E0E0),
  'gold': Color(0xFFFFCA28),
  'thai': Color(0xFFBA68C8),
  'finance': Color(0xFF4DB6AC),
  'health': Color(0xFFF48FB1),
  'staples': Color(0xFFA1887F),
  'travel': Color(0xFF4FC3F7),
  'space': Color(0xFF9FA8DA),
};

Color themeColor(String t) => _themeColors[t] ?? AppColors.muted;

/// One editable line: a main-port asset, a sector stock, or something already entered.
class _Slot {
  const _Slot(this.key, this.label, this.ticker, this.hint);

  final String key;
  final String label;
  final String? ticker;
  final String hint;
}

class PortfolioScreen extends ConsumerWidget {
  const PortfolioScreen({super.key, required this.onOpenBudget});

  final VoidCallback onOpenBudget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider).valueOrNull;
    final s = ref.watch(settingsProvider);
    final pv = ref.watch(portfolioProvider);
    final targets = ref.watch(targetWeightsProvider);
    final tilt = ref.watch(rebalanceTiltProvider);

    final slots = <_Slot>[];
    if (config != null) {
      for (final a in config.mainPort) {
        slots.add(_Slot('main:${a.key}', a.name, a.proxy, a.isFund ? 'พอร์ตหลัก · กองทุน (ราคาอ้างอิง ${a.proxy})' : 'พอร์ตหลัก · ${a.proxy}'));
      }
      for (final sec in config.sectors) {
        final w = s.sectorWeights[sec.id] ?? 0;
        if (w <= 0 && !sec.funded) continue;
        for (final st in sec.stocks) {
          slots.add(_Slot('${sec.id}:${st.ticker}', st.ticker, st.ticker, '${sec.name} · ${st.isFund ? 'กองทุน' : 'หุ้นรายตัว'}'));
        }
      }
    }
    for (final h in s.holdings) {
      if (!slots.any((x) => x.key == h.key)) slots.add(_Slot(h.key, h.label, h.ticker, 'บันทึกไว้ก่อนหน้า'));
    }
    final byKey = {for (final h in s.holdings) h.key: h};
    final valueOf = {for (final v in pv?.values ?? const <HoldingValue>[]) v.holding.key: v};
    final planTotal = (pv?.values ?? const <HoldingValue>[]).where((v) => targets.containsKey(v.holding.key)).fold(0.0, (a, b) => a + b.valueThb);

    return Scaffold(
      appBar: AppBar(title: const Text('พอร์ตของฉัน', style: TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          const Text('บันทึกสิ่งที่ถืออยู่จริง (เก็บในเครื่องนี้เท่านั้น) เพื่อดูมูลค่าเป็นบาท ความเสี่ยงรวม และให้งบเดือนนี้ช่วยเติมส่วนที่ต่ำกว่าเป้า',
              style: TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.45)),
          const SizedBox(height: kGap),
          if (pv == null || pv.isEmpty)
            const SurfaceCard(
              child: Text('ยังไม่มีข้อมูลพอร์ต · แตะรายการด้านล่างเพื่อกรอกจำนวนหน่วยหรือมูลค่าปัจจุบัน', style: TextStyle(fontSize: 14, height: 1.5)),
            )
          else ...[
            _SummaryCard(pv: pv),
            const SizedBox(height: kGap),
            _RiskCard(pv: pv),
            const SizedBox(height: kGap),
            _AllocationCard(pv: pv),
          ],
          SectionHeader(title: 'รายการที่ถือ', trailing: targets.isEmpty ? null : 'เทียบกับเป้าตามแผน'),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Column(
              children: [
                for (final (i, slot) in slots.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 12, endIndent: 12),
                  _HoldingRow(
                    slot: slot,
                    value: valueOf[slot.key],
                    target: targets[slot.key],
                    actual: planTotal > 0 && targets.containsKey(slot.key) ? (valueOf[slot.key]?.valueThb ?? 0) / planTotal : null,
                    onTap: () => _edit(context, ref, slot, byKey[slot.key]),
                  ),
                ],
              ],
            ),
          ),
          const SectionHeader(title: 'ปรับสมดุลด้วยเงินใหม่'),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: s.rebalance,
                  onChanged: (v) => ref.read(settingsProvider.notifier).update((x) => x.copyWith(rebalance: v)),
                  title: const Text('ให้งบเดือนนี้เติมส่วนที่ต่ำกว่าเป้า', style: TextStyle(fontSize: 14.5)),
                  subtitle: const Text('ไม่ขายของเดิม แค่ใส่เงินใหม่ในส่วนที่ต่ำกว่าเป้ามากขึ้น (สูงสุด 2 เท่า) และส่วนที่เกินเป้าน้อยลง (ต่ำสุดครึ่งหนึ่ง)',
                      style: TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.45)),
                ),
                if (s.rebalance && tilt.isNotEmpty) ...[
                  const Divider(height: 16),
                  for (final e in (tilt.entries.where((e) => (e.value - 1).abs() > 0.05).toList()..sort((a, b) => b.value.compareTo(a.value))).take(5))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Expanded(child: Text(slots.where((x) => x.key == e.key).firstOrNull?.label ?? e.key, style: const TextStyle(fontSize: 13.5))),
                        Text(e.value > 1 ? 'เติมมากขึ้น ×${e.value.toStringAsFixed(1)}' : 'ลดลง ×${e.value.toStringAsFixed(1)}',
                            style: TextStyle(fontSize: 13, color: e.value > 1 ? AppColors.buy : AppColors.muted, fontFeatures: tabular)),
                      ]),
                    ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: onOpenBudget,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text('ดูผลในงบเดือนนี้ →', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ] else if (s.rebalance)
                  const Text('จะเริ่มทำงานเมื่อบันทึกรายการที่อยู่ในแผนอย่างน้อย 1 รายการ', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
              ],
            ),
          ),
          const Disclaimer(),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, _Slot slot, Holding? h) async {
    final result = await showModalBottomSheet<Holding?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditSheet(slot: slot, initial: h),
    );
    if (result == null) return;
    await ref.read(settingsProvider.notifier).update((x) {
      final list = [for (final y in x.holdings) if (y.key != slot.key) y];
      if (!result.isEmpty) list.add(result);
      return x.copyWith(holdings: list);
    });
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.pv});

  final PortfolioView pv;

  @override
  Widget build(BuildContext context) {
    final unpriced = pv.values.where((v) => !v.priced).length;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('มูลค่ารวมโดยประมาณ'),
          const SizedBox(height: 6),
          Text('${baht(pv.total)} บาท', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, fontFeatures: tabular)),
          const SizedBox(height: 4),
          if (pv.cost > 0)
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'กำไร/ขาดทุน  ', style: TextStyle(color: AppColors.muted)),
              TextSpan(text: '${pv.pnl >= 0 ? '+' : '−'}${baht(pv.pnl.abs())} บาท  ${pct(pv.pnlPct)}', style: TextStyle(color: pctColor(pv.pnlPct), fontFeatures: tabular)),
              TextSpan(text: '  · ต้นทุน ${baht(pv.cost)}', style: const TextStyle(color: AppColors.muted)),
            ]), style: const TextStyle(fontSize: 13.5)),
          const SizedBox(height: 4),
          Text('ใช้ค่าเงิน ${pv.fx.toStringAsFixed(2)} บาท/ดอลลาร์ · สินทรัพย์ดอลลาร์ ${(pv.usdShare * 100).toStringAsFixed(0)}% ของพอร์ต'
              '${unpriced > 0 ? ' · $unpriced รายการไม่มีราคา ใช้ต้นทุนแทน' : ''}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.45)),
        ],
      ),
    );
  }
}

class _RiskCard extends StatelessWidget {
  const _RiskCard({required this.pv});

  final PortfolioView pv;

  @override
  Widget build(BuildContext context) {
    final share = pv.total > 0 ? pv.worstCaseThb / pv.total * 100 : 0.0;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('ถ้าตลาดแย่มาก'),
          const SizedBox(height: 6),
          Text('อาจลดลงราว ${baht(pv.worstCaseThb)} บาท (${share.toStringAsFixed(0)}%)',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, fontFeatures: tabular)),
          const SizedBox(height: 6),
          const Text('ถามตัวเองว่าถ้าเห็นตัวเลขนี้จริง จะยังลงทุนต่อตามแผนได้ไหม ถ้าไม่ไหว ควรลดส่วนหุ้นรายตัวหรือเพิ่มเงินฉุกเฉิน',
              style: TextStyle(fontSize: 13.5, height: 1.5)),
          const SizedBox(height: 6),
          const Text(worstCaseNote, style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.45)),
        ],
      ),
    );
  }
}

class _AllocationCard extends StatelessWidget {
  const _AllocationCard({required this.pv});

  final PortfolioView pv;

  @override
  Widget build(BuildContext context) {
    final themes = pv.byTheme.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    final main = pv.byBucket['main'] ?? 0, tech = pv.byBucket['tech'] ?? 0;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('กระจายตัวตามธีม (มองทะลุกองทุน)'),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 110,
                height: 110,
                child: CustomPaint(painter: _Donut([for (final e in themes) (e.value, themeColor(e.key))])),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    for (final e in themes)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          Container(width: 10, height: 10, decoration: BoxDecoration(color: themeColor(e.key), borderRadius: BorderRadius.circular(3))),
                          const SizedBox(width: 8),
                          Expanded(child: Text(themeTh(e.key), style: const TextStyle(fontSize: 13.5))),
                          Text('${(e.value / pv.total * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, fontFeatures: tabular)),
                        ]),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 22),
          Row(children: [
            Expanded(child: Text('พอร์ตหลัก ${(main / pv.total * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 13, color: AppColors.bucketMain))),
            Text('หุ้นรายตัว/หมวด ${(tech / pv.total * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 13, color: AppColors.bucketStocks)),
          ]),
          if ((pv.byTheme['tech'] ?? 0) / pv.total > 0.5)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('เทค/AI เกินครึ่งพอร์ต (รวม NASDAQ และหุ้น AI) ถ้าธีมนี้ลงแรง พอร์ตจะลงตามมาก',
                  style: TextStyle(fontSize: 12.5, color: AppColors.yellow, height: 1.45)),
            ),
        ],
      ),
    );
  }
}

class _Donut extends CustomPainter {
  _Donut(this.parts);

  final List<(double, Color)> parts;

  @override
  void paint(Canvas canvas, Size size) {
    final total = parts.fold(0.0, (a, b) => a + b.$1);
    if (total <= 0) return;
    final rect = Rect.fromLTWH(9, 9, size.width - 18, size.height - 18);
    var start = -math.pi / 2;
    for (final (v, c) in parts) {
      final sweep = v / total * 2 * math.pi;
      canvas.drawArc(
          rect,
          start,
          math.max(0.0, sweep - (parts.length > 1 ? 0.03 : 0)),
          false,
          Paint()
            ..color = c
            ..style = PaintingStyle.stroke
            ..strokeWidth = 18);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_Donut old) => true;
}

class _HoldingRow extends StatelessWidget {
  const _HoldingRow({required this.slot, required this.value, required this.target, required this.actual, required this.onTap});

  final _Slot slot;
  final HoldingValue? value;
  final double? target;
  final double? actual;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(slot.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    target == null
                        ? slot.hint
                        : 'เป้า ${(target! * 100).toStringAsFixed(0)}% · ตอนนี้ ${((actual ?? 0) * 100).toStringAsFixed(0)}%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.muted, fontFeatures: tabular),
                  ),
                ],
              ),
            ),
            if (v == null)
              const Text('แตะเพื่อกรอก', style: TextStyle(fontSize: 12.5, color: AppColors.muted))
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${baht(v.valueThb)} ฿', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, fontFeatures: tabular)),
                  if (v.pnlPct != null) Text(pct(v.pnlPct), style: TextStyle(fontSize: 12, color: pctColor(v.pnlPct), fontFeatures: tabular)),
                ],
              ),
            const SizedBox(width: 4),
            const Icon(Icons.edit_outlined, size: 16, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.slot, this.initial});

  final _Slot slot;
  final Holding? initial;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final _units = TextEditingController(text: _fmt(widget.initial?.units));
  late final _cost = TextEditingController(text: _fmt(widget.initial?.costThb));
  late final _manual = TextEditingController(text: _fmt(widget.initial?.manualValueThb));

  static String _fmt(double? v) => v == null || v == 0 ? '' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString());

  static double? _num(String s) => double.tryParse(s.replaceAll(',', '').trim());

  @override
  void dispose() {
    _units.dispose();
    _cost.dispose();
    _manual.dispose();
    super.dispose();
  }

  Widget _field(String label, TextEditingController c, String? suffix) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, suffixText: suffix, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(slot.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(slot.hint, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
          const SizedBox(height: 16),
          if (slot.ticker != null) _field('จำนวนหน่วยของ ${slot.ticker}', _units, 'หน่วย'),
          _field('ต้นทุนรวมที่จ่ายไป', _cost, '฿'),
          _field('มูลค่าปัจจุบัน (ไม่บังคับ)', _manual, '฿'),
          const Text('ถ้าถือกองทุนไทยหรือทองแท่ง ให้กรอกมูลค่าปัจจุบันจากแอปธนาคาร/ร้านทองแทน (จะใช้ค่านี้ก่อนราคาตลาด)',
              style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.45)),
          const SizedBox(height: 16),
          Row(children: [
            if (widget.initial != null)
              TextButton(
                onPressed: () => Navigator.of(context).pop(Holding(key: slot.key, label: slot.label, ticker: slot.ticker)),
                child: const Text('ลบรายการนี้'),
              ),
            const Spacer(),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ยกเลิก')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(Holding(
                key: slot.key,
                label: slot.label,
                ticker: slot.ticker,
                units: _num(_units.text) ?? 0,
                costThb: _num(_cost.text) ?? 0,
                manualValueThb: _num(_manual.text),
              )),
              child: const Text('บันทึก'),
            ),
          ]),
        ],
      ),
    );
  }
}

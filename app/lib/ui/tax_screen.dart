import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/budget.dart';
import '../state/providers.dart';
import '../state/settings.dart';
import 'widgets/common.dart';
import 'widgets/number_field.dart';

/// Estimates how much ThaiESG / RMF to buy so net income stays under a target.
class TaxScreen extends ConsumerWidget {
  const TaxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final t = ref.watch(taxProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final yearTax = ref.watch(budgetProvider)?.tax ?? 0;

    Widget row(String label, double v, {bool minus = true, bool strong = false, String? note}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(label, style: TextStyle(fontSize: 13.5, fontWeight: strong ? FontWeight.w700 : FontWeight.w400))),
                  Text('${minus && v > 0 ? '−' : ''}${baht(v)}',
                      style: TextStyle(fontSize: 13.5, fontWeight: strong ? FontWeight.w700 : FontWeight.w500, fontFeatures: tabular)),
                ],
              ),
              if (note != null) Text(note, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('วางแผนภาษี', style: TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          SurfaceCard(
            borderColor: t.needed > 0 ? AppColors.yellow.withAlpha(90) : AppColors.green.withAlpha(90),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('ผลลัพธ์ (ประมาณ)'),
                const SizedBox(height: 8),
                if (t.needed > 0) ...[
                  Text('ซื้อกองทุนลดหย่อนเพิ่มราว ${baht(t.suggestEsg + t.suggestRmf)} บาท',
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.35)),
                  const SizedBox(height: 6),
                  if (t.suggestEsg > 0) Text('ThaiESG ${baht(t.suggestEsg)} บาท (ซื้อได้อีก ${baht(t.esgRoom)})', style: const TextStyle(fontSize: 13.5)),
                  if (t.suggestRmf > 0) Text('RMF ${baht(t.suggestRmf)} บาท (ซื้อได้อีก ${baht(t.rmfRoom)})', style: const TextStyle(fontSize: 13.5)),
                  if (t.uncovered > 0)
                    Text('ยังเกินเป้าอีก ${baht(t.uncovered)} บาท เพราะเต็มวงเงินกองทุนแล้ว',
                        style: const TextStyle(fontSize: 13, color: AppColors.yellow)),
                  const SizedBox(height: 6),
                  Text('ภาษีลดจาก ${baht(t.tax)} เหลือ ${baht(t.taxAfter)} บาท (ประหยัดราว ${baht(t.saved)} บาท)',
                      style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                ] else
                  Text('เงินได้สุทธิ ${baht(t.net)} บาท ไม่เกินเป้า ${baht(s.targetNet)} แล้ว ไม่ต้องซื้อเพิ่ม',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.35)),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SourceTag(Provenance.calc),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'งบลดหย่อนที่แอปกันไว้ทั้งปี ${baht(yearTax * 12)} บาท · ซื้อ ThaiESG ต้องถือ 5 ปี · RMF ต้องถือ 5 ปีและถึงอายุ 55 และซื้อต่อเนื่อง (เว้นได้ไม่เกิน 1 ปีติด)',
                        style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'เป้าหมาย'),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ให้เงินได้สุทธิไม่เกิน', style: TextStyle(fontSize: 13.5)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ToggleChip(
                      label: '300,000\nพ้นขั้น 10%',
                      selected: s.targetNet == 300000,
                      expand: true,
                      onTap: () => notifier.update((x) => x.copyWith(targetNet: 300000)),
                    ),
                    const SizedBox(width: 6),
                    ToggleChip(
                      label: '500,000\nพ้นขั้น 15%',
                      selected: s.targetNet == 500000,
                      expand: true,
                      onTap: () => notifier.update((x) => x.copyWith(targetNet: 500000)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('ตอนนี้เงินได้สุทธิอยู่ในขั้นภาษี ${(marginalRate(t.net) * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
              ],
            ),
          ),
          const SectionHeader(title: 'ข้อมูลของคุณ (ปีนี้)'),
          SurfaceCard(
            child: Column(
              children: [
                NumberField(label: 'เงินเดือนฐาน (บาท/เดือน)', value: s.salary, onSaved: (v) => notifier.update((x) => x.copyWith(salary: v))),
                NumberField(label: 'โบนัสคาดว่าได้ (เดือน)', value: s.bonusMonths, decimals: 1, onSaved: (v) => notifier.update((x) => x.copyWith(bonusMonths: v))),
                NumberField(label: 'เบี้ยประกันชีวิตทั้งปี', value: s.lifeInsurance, onSaved: (v) => notifier.update((x) => x.copyWith(lifeInsurance: v))),
                NumberField(label: 'เบี้ยประกันสุขภาพตัวเองทั้งปี', value: s.healthInsurance, onSaved: (v) => notifier.update((x) => x.copyWith(healthInsurance: v))),
                NumberField(label: 'กองทุนสำรองเลี้ยงชีพ (ส่วนของคุณ) ทั้งปี', value: s.providentFund, onSaved: (v) => notifier.update((x) => x.copyWith(providentFund: v))),
                NumberField(label: 'ลดหย่อนอื่นๆ ทั้งปี (เช่น บิดามารดา ดอกเบี้ยบ้าน)', value: s.otherDeductions, onSaved: (v) => notifier.update((x) => x.copyWith(otherDeductions: v))),
                NumberField(label: 'ThaiESG ที่ซื้อแล้วปีนี้', value: s.esgBought, onSaved: (v) => notifier.update((x) => x.copyWith(esgBought: v))),
                NumberField(label: 'RMF ที่ซื้อแล้วปีนี้', value: s.rmfBought, onSaved: (v) => notifier.update((x) => x.copyWith(rmfBought: v))),
              ],
            ),
          ),
          const SectionHeader(title: 'วิธีคิด'),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                row('เงินได้ทั้งปี (เงินเดือน × ${(12 + s.bonusMonths).toStringAsFixed(1)} เดือน)', t.income, minus: false, strong: true),
                row('หักค่าใช้จ่าย 50% สูงสุด 100,000', t.expense),
                row('ลดหย่อนส่วนตัว', t.personal),
                row('ประกันสังคม', t.sso, note: '5% ของค่าจ้างสูงสุด 17,500 บาท/เดือน = สูงสุด 10,500 บาท/ปี (ปี 2569)'),
                row('ประกันชีวิต + สุขภาพ', t.insurance, note: 'รวมไม่เกิน 100,000 (สุขภาพไม่เกิน 25,000)'),
                row('ลดหย่อนอื่น + กองทุนสำรองเลี้ยงชีพ', t.otherDeductions),
                row('กองทุนที่ซื้อแล้ว', t.fundsBought),
                const Divider(height: 16),
                row('เงินได้สุทธิ', t.net, minus: false, strong: true),
                row('ภาษีที่ต้องจ่ายก่อนซื้อเพิ่ม', t.tax, minus: false),
                const SizedBox(height: 8),
                const Text(
                  'อัตราภาษี: 0–150,000 ยกเว้น · 150,001–300,000 = 5% · 300,001–500,000 = 10% · 500,001–750,000 = 15% · 750,001–1 ล้าน = 20% · สูงกว่านั้น 25–35%\n'
                  'ThaiESG ลดหย่อนได้ 30% ของเงินได้ ไม่เกิน 300,000 · RMF 30% ไม่เกิน 500,000 (รวมกับกองทุนสำรองเลี้ยงชีพ ประกันบำนาญ ฯลฯ ไม่เกิน 500,000)',
                  style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.5),
                ),
                const SizedBox(height: 6),
                const LinkRow(prefix: 'ที่มา:', links: [
                  ('อัตราภาษี ปี 2569 (Prudential)', 'https://www.prudential.co.th/th/knowledge-corner/growing-wealth/calculate-personal-income-tax/'),
                  ('ThaiESG / RMF 2569 (Krungsri)', 'https://www.keptbykrungsri.com/kept-tips/investment/taxsavingfund2026'),
                  ('ประกันสังคม 2569 (Krungsri)', 'https://www.krungsri.com/th/krungsri-the-coach/life/good-life/sso-section-33-rate-increase'),
                ]),
                const SizedBox(height: 6),
                const Text('เป็นการประมาณเบื้องต้น ไม่รวมกรณีพิเศษ ควรตรวจกับกรมสรรพากรก่อนยื่นจริง ไม่ใช่คำแนะนำด้านภาษี',
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

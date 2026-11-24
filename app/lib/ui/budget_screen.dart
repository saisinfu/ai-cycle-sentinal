import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/budget.dart';
import '../data/config.dart';
import '../data/engine.dart';
import '../data/flex.dart';
import '../state/providers.dart';
import '../state/settings.dart';
import 'sector_screen.dart';
import 'tax_screen.dart';
import 'widgets/common.dart';

/// "งบเดือนนี้": where this month's DCA money goes, in baht, with reasons.
class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final plan = ref.watch(budgetProvider);
    final config = ref.watch(configProvider).valueOrNull;
    final market = ref.watch(marketProvider).valueOrNull;
    final tax = ref.watch(taxProvider);
    final flex = ref.watch(flexProvider);
    final n = ref.read(settingsProvider.notifier);
    final month = DateTime.now().month;

    Widget line(BudgetLine l, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(l.label, style: TextStyle(fontSize: 14, fontWeight: strong ? FontWeight.w700 : FontWeight.w600))),
                  Text('${baht(l.amount)} ฿',
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: l.amount > 0 ? AppColors.text : AppColors.muted,
                          fontFeatures: tabular)),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SourceTag(SourceTag.fromKey(l.tag)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(l.note, style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.4))),
                ],
              ),
            ],
          ),
        );

    /// A budget line with the flexible-budget multiplier applied.
    Widget flexLine(BudgetLine l, String key) {
      final f = flex?.line(key);
      if (f == null || flex!.mode == FlexMode.off || l.amount <= 0) return line(l);
      final m = f.multiplier;
      final dd = f.drawdown;
      final why = dd == null
          ? 'ไม่มีราคาล่าสุด ลงเท่างบฐาน'
          : 'ห่างจุดสูงสุด 52 สัปดาห์ ${dd.toStringAsFixed(0)}% → ×${m.toStringAsFixed(1)}'
              '${!f.isFund && m >= singleStockMaxMultiplier ? ' (หุ้นรายตัวสูงสุด ×1.5)' : ''}'
              '${f.capped ? ' · ถึงเพดานต่อหุ้น ${flex.stockCapPct.toStringAsFixed(0)}%' : ''}'
              '${(f.planned - f.base * m).abs() > 1 && m > 1 && !f.capped ? ' · เงินสำรองที่ใช้ได้เดือนนี้ไม่พอ ลดเหลือ ${baht(f.planned)}' : ''}'
              '${(f.tilt - 1).abs() > 0.02 ? ' · ปรับสัดส่วนเข้าหาเป้า ×${f.tilt.toStringAsFixed(2)}' : ''}';
      return line(BudgetLine(
        label: l.label,
        amount: f.planned,
        note: '${l.note}\nงบฐาน ${baht(f.base)} · $why',
        tag: l.tag,
      ));
    }

    if (plan == null || config == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('งบเดือนนี้')),
        body: const Center(child: CircularProgressIndicator(color: AppColors.text)),
      );
    }

    final aiShare = (s.buckets['tech'] ?? 0) * (s.sectorWeights['ai'] ?? 0) / 100 +
        (s.buckets['main'] ?? 0) * (s.mainSplit['nasdaq'] ?? 0) / 100;

    return Scaffold(
      appBar: AppBar(
        title: Text('งบเดือน${thMonthYear(DateTime.now())}', style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [IconButton(tooltip: 'ปรับงบ', onPressed: onOpenSettings, icon: const Icon(Icons.tune))],
      ),
      bottomNavigationBar: _RecordBar(flex: flex),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          _BuyList(plan: plan, flex: flex, config: config),
          const SizedBox(height: kGap),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('งบฐานต่อเดือน'),
                const SizedBox(height: 6),
                Text('${baht(plan.total)} บาท', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, fontFeatures: tabular)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const SourceTag(Provenance.rule),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('เงินเดือนฐาน ${baht(s.salary)} × ${s.dcaPct.toStringAsFixed(0)}% (ไม่รวมโบนัส)',
                          style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 10,
                    child: Row(
                      children: [
                        for (final (k, c) in const [('main', AppColors.bucketMain), ('tech', AppColors.bucketStocks), ('tax', AppColors.bucketTax)])
                          if ((s.buckets[k] ?? 0) > 0)
                            Expanded(
                              flex: ((s.buckets[k] ?? 0) * 10).round(),
                              child: Container(margin: const EdgeInsets.only(right: 2), color: c),
                            ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                for (final (k, label, c, amount) in [
                  ('main', 'พอร์ตหลัก', AppColors.bucketMain, plan.main),
                  ('tech', 'หุ้นรายตัว (หมวดต่างๆ)', AppColors.bucketStocks, plan.tech),
                  ('tax', 'กองทุนลดหย่อนภาษี', AppColors.bucketTax, plan.tax),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(width: 10, height: 10, margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
                        Expanded(child: Text('$label ${(s.buckets[k] ?? 0).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 13.5))),
                        Text('${baht(amount)} ฿', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, fontFeatures: tabular)),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          if (flex != null && flex.mode != FlexMode.off) ...[
            const SizedBox(height: kGap),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Expanded(child: Eyebrow('เงินสำรองสำหรับซื้อตอนย่อ')),
                    InkWell(
                      onTap: onOpenSettings,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                        child: Text(flexModeName(flex.mode), style: const TextStyle(fontSize: 12, decoration: TextDecoration.underline)),
                      ),
                    ),
                  ]),
                  for (final (label, v, c) in [
                    ('ต้นเดือน', flex.reserveBefore, AppColors.text),
                    ('+ เก็บเพิ่ม (ตัวที่ใกล้จุดสูงสุด / เงินสดตามกฎหมวด)', flex.saved, AppColors.muted),
                    ('− ใช้ซื้อเพิ่มตัวที่ราคาย่อ', flex.used, AppColors.buy),
                    ('คงเหลือหลังเดือนนี้', flex.reserveAfter, AppColors.text),
                  ])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Expanded(child: Text(label, style: TextStyle(fontSize: 13.5, color: c, height: 1.4))),
                        Text('${baht(v)} ฿', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c, fontFeatures: tabular)),
                      ]),
                    ),
                  if (flex.monthsLeft != null && flex.reserveAfter > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('ถ้าราคายังย่อแบบนี้ เงินสำรองพอซื้อเพิ่มได้อีกราว ${flex.monthsLeft!.toStringAsFixed(0)} เดือน',
                          style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.45)),
                    ),
                  if (flex.emergencyBlocked)
                    const _Warn('ยังไม่ใช้เงินสำรอง เพราะเงินฉุกเฉินยังไม่ถึงเป้าที่ตั้งไว้ (ตั้งค่า → เงินฉุกเฉิน) เงินฉุกเฉินต้องมาก่อนการลงทุนเพิ่ม'),
                  if (!s.emergencySet)
                    const _Warn('ยังไม่ได้ตั้งเป้าเงินฉุกเฉิน (แนะนำ 6 เท่าของค่าใช้จ่ายต่อเดือน) เงินสำรองซื้อตอนย่อไม่ควรเป็นเงินก้อนเดียวกับเงินฉุกเฉิน'),
                  if (flex.paceLimited)
                    const _Warn('ใช้เงินสำรองได้ไม่เกิน 1/6 ต่อเดือน เพื่อให้มีเงินซื้อต่อได้ถ้าตลาดลงนานหลายเดือน'),
                  if (flex.shortfall > 1 && !flex.paceLimited && !flex.emergencyBlocked)
                    _Warn('ราคาย่อหลายตัว แผนอยากซื้อเพิ่มอีก ${baht(flex.shortfall)} บาทแต่เงินสำรองไม่พอ'
                        '${flex.reserveBefore <= 0 ? ' ถ้ามีเงินเก็บแยกจากเงินฉุกเฉิน ใส่ยอดในหน้าตั้งค่าได้' : ''}'),
                  if (flex.capAmount.isFinite && flex.reserveAfter >= flex.capAmount - 1)
                    Text('เงินสำรองเต็มเพดาน ${baht(flex.capAmount)} บาท ส่วนเกินลงทุนเลย', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  const SizedBox(height: 6),
                  const Text(
                    'ทดสอบย้อนหลัง: "ซื้อเพิ่มเมื่อย่อ" ได้ผลใกล้ DCA ปกติมาก (ราว −0.04% ต่อปี) ข้อดีคือมีเงินพร้อมซื้อตอนตลาดร่วง ไม่ได้ทำให้กำไรมากขึ้น',
                    style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.45),
                  ),
                ],
              ),
            ),
          ],

          SectionHeader(title: 'พอร์ตหลัก · ${baht(plan.main)} บาท', trailing: 'ปรับสัดส่วน', onTrailing: onOpenSettings),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, l) in plan.mainLines.indexed) ...[
                  flexLine(l, 'main:${config.mainPort[i].key}'),
                  () {
                    final asset = config.mainPort[i];
                    final q = market?.quotes[asset.proxy];
                    if (q == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: LinkRow(
                        prefix: '${asset.proxy} ${money(q.price, q.currency)}${q.asOf != null ? ' (${thDate(q.asOf!)})' : ''}'
                            '${q.ma200 != null ? ' · ${q.price >= q.ma200! ? 'เหนือ' : 'ใต้'}เส้น 200 วัน' : ''}',
                        links: [if (q.sourceUrl != null) ('ที่มา', q.sourceUrl!)],
                      ),
                    );
                  }(),
                  if (i < plan.mainLines.length - 1) const Divider(height: 8),
                ],
                if (!s.mainSplitSet) ...[
                  const SizedBox(height: 8),
                  const Text('ยังไม่ได้ตั้งสัดส่วนพอร์ตหลัก ตอนนี้แบ่งเท่ากันไปก่อน แตะ "ปรับสัดส่วน" เพื่อตั้งเอง',
                      style: TextStyle(fontSize: 12.5, color: AppColors.yellow)),
                ],
                const SizedBox(height: 6),
                const Text('พอร์ตหลักไม่ปรับตามคะแนนวัฏจักร แต่ปรับตามราคาตามแผนงบยืดหยุ่น (ถ้าเปิดไว้)',
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),

          SectionHeader(title: 'หุ้นรายตัว · งบฐาน ${baht(plan.tech)} บาท', trailing: 'ปรับน้ำหนักหมวด', onTrailing: onOpenSettings),
          for (final sb in plan.sectors) ...[
            SurfaceCard(
              borderColor: AppColors.line,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SectorScreen(sectorId: sb.vm.config.id))),
                    child: Row(
                      children: [
                        Icon(sectorIcon(sb.vm.config.icon), size: 18, color: AppColors.muted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('${sb.vm.config.name} · ${sb.weightPct.toStringAsFixed(0)}%',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                        StatusPill(label: zoneName(sb.vm.latest.zone), color: zoneColor(sb.vm.latest.zone)),
                        const Icon(Icons.chevron_right, color: AppColors.muted, size: 18),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('งบหมวดนี้ ${baht(sb.amount)} บาท (${baht(plan.tech)} × ${sb.weightPct.toStringAsFixed(0)}%)',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                  if (sb.vm.config.isDraft)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('กฎของหมวดนี้เป็นร่างที่ Claude ตั้งต้น ยังไม่ได้ทดสอบ ถือเป็นตัวอย่าง ไม่ใช่แผนที่ยืนยันแล้ว',
                          style: TextStyle(fontSize: 12.5, color: AppColors.yellow, height: 1.45)),
                    ),
                  const Divider(height: 18),
                  for (final l in sb.lines) flexLine(l, '${sb.vm.config.id}:${l.label}'),
                  if (sb.cash > 0)
                    line(BudgetLine(
                      label: 'เก็บเป็นเงินสดสำรอง',
                      amount: sb.cash,
                      note: 'ส่วนที่กฎไม่ได้จัดสรรในสถานะ${zoneName(sb.vm.latest.zone)} รอใช้เมื่อหมวดกลับมาขยายตัว',
                      tag: 'calc',
                    )),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (plan.unassignedTech > 0)
            SurfaceCard(
              child: line(BudgetLine(
                label: 'ยังไม่ได้แบ่งให้หมวดใด',
                amount: plan.unassignedTech,
                note: 'น้ำหนักหมวดรวมกันยังไม่ถึง 100% เก็บเป็นเงินสดไว้ก่อน',
                tag: 'calc',
              )),
            ),
          if (plan.sectors.isEmpty && plan.unassignedTech == 0)
            const SurfaceCard(child: Text('ยังไม่ได้ใส่น้ำหนักให้หมวดใด', style: TextStyle(color: AppColors.muted))),

          SectionHeader(title: 'กองทุนลดหย่อนภาษี · ${baht(plan.tax)} บาท/เดือน', trailing: 'วางแผนภาษี', onTrailing: () {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TaxScreen()));
          }),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                line(BudgetLine(
                  label: 'กันไว้แล้วปีนี้ (ถึงเดือนนี้)',
                  amount: plan.tax * month,
                  note: '${baht(plan.tax)} × $month เดือน · ทั้งปีจะได้ราว ${baht(plan.tax * 12)} บาท',
                  tag: 'calc',
                )),
                const Divider(height: 12),
                line(BudgetLine(
                  label: tax.needed > 0 ? 'ต้องซื้อเพิ่มเพื่อให้เงินได้สุทธิไม่เกิน ${baht(s.targetNet)}' : 'ลดหย่อนพอแล้วตามเป้า',
                  amount: tax.suggestEsg + tax.suggestRmf,
                  note: tax.needed > 0
                      ? 'ประมาณจากข้อมูลในหน้าวางแผนภาษี · ประหยัดภาษีได้ราว ${baht(tax.saved)} บาท'
                      : 'เงินได้สุทธิประมาณ ${baht(tax.net)} บาท ต่ำกว่าเป้าแล้ว',
                  tag: 'calc',
                )),
                if (tax.needed > plan.tax * 12)
                  Text(
                    'งบที่กันไว้ทั้งปี (${baht(plan.tax * 12)}) น้อยกว่าที่ต้องซื้อ ${baht(tax.needed - plan.tax * 12)} บาท '
                    'อาจต้องใช้เงินโบนัสหรือปรับเป้าในหน้าวางแผนภาษี',
                    style: const TextStyle(fontSize: 12.5, color: AppColors.yellow, height: 1.45),
                  ),
                TextLinkButton(label: 'เปิดหน้าวางแผนภาษี', onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TaxScreen()));
                }),
              ],
            ),
          ),

          const SizedBox(height: kGap),
          SurfaceCard(
            color: AppColors.background,
            child: Text(
              'เงินที่ผูกกับธีมเทค/AI โดยตรงราว ${aiShare.toStringAsFixed(0)}% ของงบ DCA '
              '(หุ้นรายตัวหมวด AI ${((s.buckets['tech'] ?? 0) * (s.sectorWeights['ai'] ?? 0) / 100).toStringAsFixed(0)}% + กองทุน NASDAQ ${((s.buckets['main'] ?? 0) * (s.mainSplit['nasdaq'] ?? 0) / 100).toStringAsFixed(0)}%) '
              'ถ้าวัฏจักร AI ชะลอ ทั้งสองส่วนมักได้รับผลพร้อมกัน',
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.5),
            ),
          ),
          const Disclaimer(),
        ],
      ),
    );
  }
}

class _Warn extends StatelessWidget {
  const _Warn(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.info_outline, size: 15, color: AppColors.yellow)),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, color: AppColors.text, height: 1.45))),
          ],
        ),
      );
}

/// One row per thing to buy this month, with a tick box kept on the phone.
class _BuyList extends ConsumerWidget {
  const _BuyList({required this.plan, required this.flex, required this.config});

  final BudgetPlan plan;
  final FlexPlan? flex;
  final AppConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final done = s.doneThisMonth;
    final rows = <(String key, String label, String sub, double amount, double mult)>[];
    if (flex != null) {
      for (final f in flex!.lines.values) {
        if (f.planned < 1) continue;
        final main = f.key.startsWith('main:');
        rows.add((f.key, main ? f.label : f.ticker ?? f.label, main ? (f.ticker ?? '') : (f.isFund ? 'กองทุน' : 'หุ้นรายตัว'), f.planned, f.multiplier));
      }
    } else {
      for (final (i, l) in plan.mainLines.indexed) {
        if (l.amount >= 1 && i < config.mainPort.length) rows.add(('main:${config.mainPort[i].key}', l.label, config.mainPort[i].proxy, l.amount, 1));
      }
      for (final sb in plan.sectors) {
        for (final l in sb.lines) {
          if (l.amount >= 1) rows.add(('${sb.vm.config.id}:${l.label}', l.label, 'หุ้นรายตัว', l.amount, 1));
        }
      }
    }
    rows.sort((a, b) => b.$4.compareTo(a.$4));
    if (plan.tax >= 1) rows.add(('tax', 'กองทุนลดหย่อนภาษี', 'ThaiESG / RMF', plan.tax, 1));
    final total = rows.fold(0.0, (a, b) => a + b.$4);
    final ticked = rows.where((r) => done.contains(r.$1)).length;

    void toggle(String key) {
      final now = UserSettings.monthKey(DateTime.now());
      final cur = [...s.doneThisMonth];
      cur.contains(key) ? cur.remove(key) : cur.add(key);
      n.update((x) => x.copyWith(checklistMonth: now, checklistDone: cur));
    }

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Eyebrow('รายการซื้อเดือนนี้')),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('ซื้อแล้ว $ticked/${rows.length}', style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
            ),
          ]),
          const SizedBox(height: 4),
          Text('${baht(total)} บาท', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, fontFeatures: tabular)),
          const SizedBox(height: 6),
          for (final r in rows)
            InkWell(
              onTap: () => toggle(r.$1),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.$2,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                decoration: done.contains(r.$1) ? TextDecoration.lineThrough : null,
                                color: done.contains(r.$1) ? AppColors.muted : AppColors.text)),
                        if (r.$3.isNotEmpty) Text(r.$3, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      ]),
                    ),
                    if ((r.$5 - 1).abs() > 0.01)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: r.$5 > 1 ? AppColors.buy : AppColors.line),
                        ),
                        child: Text('×${r.$5.toStringAsFixed(1)}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: r.$5 > 1 ? AppColors.buy : AppColors.muted)),
                      ),
                    Text('${baht(r.$4)} ฿', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: tabular)),
                    Checkbox(
                      value: done.contains(r.$1),
                      onChanged: (_) => toggle(r.$1),
                      activeColor: AppColors.buy,
                      checkColor: AppColors.background,
                    ),
                  ],
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(0, 4, 8, 4),
            child: Text('×1.5 / ×2.5 = ซื้อเพิ่มเพราะราคาห่างจุดสูงสุด (ใช้เงินสำรอง) · ×0.9 = ราคาใกล้จุดสูงสุด กันไว้ 10% · รายละเอียดอยู่ด้านล่าง',
                style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

/// Sticky bar: confirm the month (updates the reserve) or undo.
class _RecordBar extends ConsumerWidget {
  const _RecordBar({required this.flex});

  final FlexPlan? flex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final f = flex;
    if (f == null) return const SizedBox.shrink();
    return Container(
      decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.line))),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SafeArea(
        top: false,
        child: s.recordedThisMonth
            ? Row(children: [
                const Icon(Icons.check_circle, color: AppColors.buy, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('บันทึกเดือนนี้แล้ว · เงินสำรอง ${baht(s.reserve)} บาท', style: const TextStyle(fontSize: 13.5))),
                TextButton(
                  onPressed: () => n.update((x) => x.copyWith(reserve: x.recordedReserveBefore, lastRecordedMonth: '')),
                  child: const Text('ยกเลิก'),
                ),
              ])
            : SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.text, foregroundColor: AppColors.background),
                  onPressed: () {
                    n.update((x) => x.copyWith(
                          recordedReserveBefore: x.reserve,
                          reserve: f.reserveAfter,
                          lastRecordedMonth: UserSettings.monthKey(DateTime.now()),
                        ));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('บันทึกแล้ว เงินสำรองตอนนี้ ${baht(f.reserveAfter)} บาท')));
                  },
                  child: const Text('ลงทุนตามนี้แล้ว · บันทึกเงินสำรอง', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
      ),
    );
  }
}

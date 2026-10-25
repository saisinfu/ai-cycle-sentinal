import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/budget.dart';
import '../data/config.dart';
import '../data/engine.dart';
import '../data/zone.dart';
import '../state/providers.dart';
import 'backtest_screen.dart';
import 'widgets/common.dart';

/// Everything about how one sector's numbers are produced.
class MethodScreen extends ConsumerWidget {
  const MethodScreen({super.key, required this.sectorId});

  final String sectorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.watch(sectorVMProvider(sectorId)).valueOrNull;
    final cfg = vm?.config ?? ref.watch(configProvider).valueOrNull?.sector(sectorId);
    if (cfg == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator(color: AppColors.text)));
    }
    final latest = vm?.latest;
    final formula = latest == null
        ? ''
        : '${latest.subs.map((s) => '${s.score.toStringAsFixed(0)}×${(s.spec.weight * 100).toStringAsFixed(0)}%').join(' + ')} = ${latest.index.toStringAsFixed(1)}';

    Widget step(int n, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.raised, shape: BoxShape.circle),
                child: Text('$n', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(body, style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.5)),
                  ],
                ),
              ),
            ],
          ),
        );

    String cellText(RuleCell? c) {
      if (c == null) return 'ถือ';
      return switch (c.action) {
        StockAction.reduceHoldings => 'ลด ${c.trimPct?.toStringAsFixed(0)}%',
        StockAction.pauseDca => 'พัก',
        StockAction.hold => 'ถือ',
        _ => 'DCA ${c.allocationPct.toStringAsFixed(0)}%',
      };
    }

    return Scaffold(
      appBar: AppBar(title: Text('วิธีคำนวณ · ${cfg.name}', style: const TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('ป้ายที่มาของตัวเลข'),
                const SizedBox(height: 10),
                for (final (tag, text) in const [
                  (Provenance.data, 'ตัวเลขจากแหล่งภายนอก มีชื่อแหล่งและวันที่'),
                  (Provenance.calc, 'คิดจากสูตรของแอป ตรวจสอบย้อนได้'),
                  (Provenance.rule, 'ค่าที่กำหนดไว้ล่วงหน้า (กฎของคุณ หรือค่าคงที่ของแอป)'),
                  (Provenance.estimate, 'Claude ประเมินจากข่าว ความมั่นใจต่ำกว่า'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      SizedBox(width: 64, child: Align(alignment: Alignment.centerLeft, child: SourceTag(tag))),
                      Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.muted))),
                    ]),
                  ),
              ],
            ),
          ),
          const SectionHeader(title: 'จากข้อมูลถึงคำแนะนำ'),
          SurfaceCard(
            child: Column(
              children: [
                step(1, 'เก็บข้อมูล 5 สัญญาณ', 'Claude ดึงตัวเลขจากแหล่งในรายการด้านล่างทุกเช้า 08:00 น. ตัวเลขรายไตรมาสหรือรายเดือนจะยกค่าเดิมมาใช้จนกว่าจะมีตัวใหม่'),
                step(2, 'แปลงเป็นคะแนน 0–100', 'เทียบค่าจริงกับช่วง "แย่สุด → ดีสุด" ของแต่ละสัญญาณ ค่าที่เลยช่วงจะถูกจำกัดไว้ที่ 0 หรือ 100'),
                step(3, 'รวมเป็นดัชนีด้วยน้ำหนัก', formula.isEmpty ? 'คะแนน × น้ำหนัก แล้วรวมกัน' : formula),
                step(4, 'ตัดสินสถานะ', '70 ขึ้นไป = ขยายตัว · 40–70 = เตือนล่วงหน้า · ต่ำกว่า 40 = ย่อยการลงทุน '
                    'การเปลี่ยนสถานะต้องผ่านเส้นไปอีก ${hysteresisBand.toStringAsFixed(0)} แต้ม กันการแจ้งเตือนซ้ำเมื่อคะแนนแกว่ง'),
                step(5, 'ใช้กฎจัดพอร์ต', 'สถานะไปจับคู่กับตารางกฎด้านล่าง ได้ออกมาเป็นสัดส่วน DCA แล้วคำนวณโซนราคาตามวิธีที่คุณเลือกในตั้งค่า'),
              ],
            ),
          ),
          const SectionHeader(title: 'แหล่งข้อมูลของ 5 สัญญาณ'),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, s) in cfg.signals.indexed)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      border: i == cfg.signals.length - 1 ? null : const Border(bottom: BorderSide(color: AppColors.line)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(s.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                            Text('${(s.weight * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('ทำไม: ${s.why}', style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.45)),
                        const SizedBox(height: 4),
                        Text('ช่วงคะแนน: ${s.range} · อัปเดต${s.frequency}', style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            SourceTag(s.isEstimate ? Provenance.estimate : Provenance.data),
                            const SizedBox(width: 6),
                            Expanded(
                              child: s.sourceUrl == null
                                  ? Text(s.source, style: const TextStyle(fontSize: 12.5))
                                  : LinkRow(links: [(s.source, s.sourceUrl!)]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SectionHeader(title: 'กฎจัดพอร์ต (${cfg.rulesFromUser ? 'ของคุณ' : 'ร่างตั้งต้น'})'),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Table(
                  columnWidths: const {0: FlexColumnWidth(1.5)},
                  children: [
                    TableRow(children: [
                      const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('สถานะ', style: TextStyle(color: AppColors.muted, fontSize: 12.5))),
                      for (final s in cfg.stocks)
                        Text(s.ticker, textAlign: TextAlign.right, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                    ]),
                    for (final z in Zone.values)
                      TableRow(children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(zoneName(z), style: TextStyle(color: zoneColor(z), fontWeight: FontWeight.w600, fontSize: 12.5)),
                        ),
                        for (final s in cfg.stocks)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Text(cellText(cfg.rules[z]?[s.ticker]), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5)),
                          ),
                      ]),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SourceTag(Provenance.rule),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        cfg.rulesFromUser
                            ? 'กฎที่คุณกำหนด แอปไม่ได้คิดตัวเลขเหล่านี้จากข้อมูลตลาด ถ้าอยากเปลี่ยน บอก Claude ได้เลย (ไม่ต้องติดตั้งแอปใหม่)'
                            : 'ร่างตั้งต้นที่ Claude เสนอ รอคุณยืนยันหรือแก้ บอก Claude ได้เลย (ไม่ต้องติดตั้งแอปใหม่)',
                        style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.45),
                      ),
                    ),
                  ],
                ),
                if (cfg.rulesNote.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(cfg.rulesNote, style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.5)),
                ],
                TextLinkButton(
                  label: 'ดูผลทดสอบย้อนหลัง',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BacktestScreen(sectorId: cfg.id))),
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'โซนราคาคิดอย่างไร'),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final m in ZoneMethod.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: '${zoneMethodName(m)}: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                      TextSpan(
                        text: switch (m) {
                          ZoneMethod.fixed => 'จุดอ้างอิง = ราคาปิดล่าสุด',
                          ZoneMethod.ma200 => 'จุดอ้างอิง = ราคาเฉลี่ย 200 วันทำการ ใช้ดูว่าราคาตอนนี้แพงหรือถูกเทียบแนวโน้มระยะยาว',
                          ZoneMethod.pe => 'จุดอ้างอิง = กำไรต่อหุ้น 12 เดือนล่าสุด × P/E เฉลี่ย 5 ปี คือราคาที่หุ้นจะซื้อขายถ้า P/E กลับไปเท่าค่าเฉลี่ย',
                        },
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ]), style: const TextStyle(fontSize: 13, height: 1.45)),
                  ),
                const SizedBox(height: 4),
                for (final a in StockAction.values)
                  Text('${actionLabel(a)}: ${bandText(a)}', style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.6)),
                const SizedBox(height: 8),
                const Text('ราคาจาก stockanalysis.com · P/E ย้อนหลังจาก fullratio.com · เลือกวิธีได้ในหน้าตั้งค่า',
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
              ],
            ),
          ),
          const SizedBox(height: kGap),
          SurfaceCard(
            color: AppColors.background,
            child: Text(
              'ข้อจำกัด: ช่วง "แย่สุด → ดีสุด" และน้ำหนักเป็นร่างแรก ยังไม่ได้ทดสอบกับวัฏจักรในอดีต · ${cfg.confidenceNote} '
              '· ผลลัพธ์เป็นการอ่านค่าตามกฎ ไม่ใช่คำทำนาย และไม่ใช่คำแนะนำการลงทุน',
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

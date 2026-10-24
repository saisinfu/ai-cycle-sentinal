import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/engine.dart';
import '../state/providers.dart';
import '../state/settings.dart';
import 'tax_screen.dart';
import 'widgets/common.dart';
import 'widgets/number_field.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final config = ref.watch(configProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('ตั้งค่า', style: TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          const SectionHeader(title: 'งบ DCA ต่อเดือน'),
          SurfaceCard(
            child: Column(
              children: [
                NumberField(label: 'เงินเดือนฐาน (ไม่รวมโบนัส)', value: s.salary, suffix: '฿', onSaved: (v) => n.update((x) => x.copyWith(salary: v))),
                NumberField(
                  label: 'แบ่งมาลงทุน (% ของเงินเดือน)',
                  value: s.dcaPct,
                  suffix: '%',
                  onSaved: (v) => n.update((x) => x.copyWith(dcaPct: v.clamp(0, 100).toDouble())),
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'แบ่งงบเป็น 3 ส่วน'),
          PercentGroupEditor(
            key: ValueKey('b-${s.buckets}'),
            items: const [('main', 'พอร์ตหลัก'), ('tech', 'หุ้นรายตัว Tech/AI'), ('tax', 'กองทุนลดหย่อนภาษี')],
            values: s.buckets,
            mustEqual100: true,
            onSave: (v) => n.update((x) => x.copyWith(buckets: v)),
          ),
          if (config != null) ...[
            const SectionHeader(title: 'สัดส่วนในพอร์ตหลัก'),
            PercentGroupEditor(
              key: ValueKey('m-${s.mainSplit}'),
              items: [for (final a in config.mainPort) (a.key, a.name)],
              values: s.mainSplit,
              mustEqual100: true,
              hint: s.mainSplitSet ? null : 'ยังไม่ได้ตั้ง ตอนนี้แบ่งเท่ากันไปก่อน',
              onSave: (v) => n.update((x) => x.copyWith(mainSplit: v, mainSplitSet: true)),
            ),
            const SectionHeader(title: 'น้ำหนักแต่ละหมวดในส่วน Tech/AI'),
            PercentGroupEditor(
              key: ValueKey('w-${s.sectorWeights}'),
              items: [for (final sc in config.sectors) (sc.id, sc.name)],
              values: s.sectorWeights,
              mustEqual100: false,
              hint: 'รวมไม่เกิน 100% ส่วนที่ไม่ได้แบ่งจะเก็บเป็นเงินสด · หมวดที่ใส่ 0% คือติดตามอย่างเดียว',
              onSave: (v) => n.update((x) => x.copyWith(sectorWeights: v)),
            ),
            const SectionHeader(title: 'หมวดที่แสดงในหน้าภาพรวม'),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final sc in config.sectors)
                    SwitchListTile(
                      value: s.isFollowed(sc.id),
                      onChanged: (v) => n.update((x) => x.copyWith(followed: {...x.followed, sc.id: v})),
                      title: Text(sc.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                      subtitle: Text(sc.stocks.map((e) => e.ticker).join(' · '), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      activeColor: AppColors.background,
                      activeTrackColor: AppColors.green,
                    ),
                ],
              ),
            ),
          ],
          const SectionHeader(title: 'วิธีคิดโซนราคา'),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final m in ZoneMethod.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        ToggleChip(
                          label: zoneMethodName(m),
                          selected: s.zoneMethod == m,
                          expand: true,
                          onTap: () => n.update((x) => x.copyWith(zoneMethod: m)),
                        ),
                      ],
                    ),
                  ),
                Text(
                  switch (s.zoneMethod) {
                    ZoneMethod.fixed => 'ใช้ราคาปิดล่าสุดเป็นจุดอ้างอิง แล้วคูณกรอบ % คงที่ ง่ายที่สุดแต่ไม่บอกว่าหุ้นแพงหรือถูก',
                    ZoneMethod.ma200 => 'ใช้ราคาเฉลี่ย 200 วันเป็นจุดอ้างอิง ถ้าราคาตอนนี้สูงกว่าเส้นมาก โซนซื้อจะอยู่ต่ำกว่าราคาปัจจุบัน',
                    ZoneMethod.pe => 'ใช้กำไรต่อหุ้น × P/E เฉลี่ย 5 ปี เป็นจุดอ้างอิง ถ้า P/E ตอนนี้สูงกว่าค่าเฉลี่ย โซนซื้อจะต่ำกว่าราคาปัจจุบัน',
                  },
                  style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.45),
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'ภาษี'),
          SurfaceCard(
            child: TextLinkButton(
              label: 'เปิดหน้าวางแผนภาษี',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TaxScreen())),
            ),
          ),
          const SectionHeader(title: 'ข้อมูลและกฎ'),
          const SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Claude ค้นข้อมูลใหม่ทุกเช้า 08:00 น. แล้วบันทึกลง GitHub แอปดึงข้อมูลทุกครั้งที่เปิดหรือดึงหน้าจอลง '
                  'กฎจัดพอร์ต หุ้นในแต่ละหมวด และเกณฑ์คะแนน ปรับได้โดยบอก Claude ไม่ต้องติดตั้งแอปใหม่ '
                  'ส่วนตั้งค่าในหน้านี้เก็บไว้ในมือถือของคุณเท่านั้น',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.5),
                ),
                SizedBox(height: 6),
                LinkRow(links: [('ไฟล์ข้อมูลบน GitHub', 'https://github.com/saisinfu/ai-cycle-sentinal/tree/main/data')]),
              ],
            ),
          ),
          const Disclaimer(),
        ],
      ),
    );
  }
}

/// Edits a set of percentages; saves only when the total is valid.
class PercentGroupEditor extends StatefulWidget {
  const PercentGroupEditor({
    super.key,
    required this.items,
    required this.values,
    required this.mustEqual100,
    required this.onSave,
    this.hint,
  });

  final List<(String, String)> items;
  final Map<String, double> values;
  final bool mustEqual100;
  final ValueChanged<Map<String, double>> onSave;
  final String? hint;

  @override
  State<PercentGroupEditor> createState() => _PercentGroupEditorState();
}

class _PercentGroupEditorState extends State<PercentGroupEditor> {
  late Map<String, double> _v = {for (final (k, _) in widget.items) k: widget.values[k] ?? 0};

  double get _sum => _v.values.fold(0, (a, b) => a + b);
  bool get _valid => widget.mustEqual100 ? (_sum - 100).abs() < 0.01 : _sum <= 100.01;
  bool get _dirty => widget.items.any((e) => (widget.values[e.$1] ?? 0) != _v[e.$1]);

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.hint != null) ...[
            Text(widget.hint!, style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.4)),
            const SizedBox(height: 4),
          ],
          for (final (k, label) in widget.items)
            NumberField(
              key: ValueKey('$k-${_v[k]}'),
              label: label,
              value: _v[k] ?? 0,
              suffix: '%',
              onSaved: (x) => setState(() => _v = {..._v, k: x}),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'รวม ${_sum.toStringAsFixed(0)}%${_valid ? '' : widget.mustEqual100 ? ' · ต้องรวมกันได้ 100%' : ' · ต้องไม่เกิน 100%'}',
                  style: TextStyle(fontSize: 13, color: _valid ? AppColors.muted : AppColors.red, fontWeight: FontWeight.w600),
                ),
              ),
              if (_dirty)
                SizedBox(
                  width: 110,
                  child: Row(
                    children: [
                      ToggleChip(
                        label: 'บันทึก',
                        selected: _valid,
                        expand: true,
                        onTap: () {
                          if (_valid) {
                            widget.onSave(Map.of(_v));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('บันทึกแล้ว')));
                          }
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/engine.dart';
import '../data/models.dart';
import '../state/providers.dart';
import 'widgets/attribution_card.dart';
import 'widgets/cards.dart';
import 'widgets/common.dart';
import 'widgets/health_card.dart';
import 'widgets/history_card.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _scroll = ScrollController();
  final _signalsKey = GlobalKey();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toSignals() {
    final ctx = _signalsKey.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveModeProvider);
    final scenario = ref.watch(scenarioProvider);
    final readings = ref.watch(readingsProvider);

    // Decide what to show and the note under the mode switch.
    DashboardVM? vm;
    String note;
    ReadingsResult? result;
    if (!live) {
      vm = ref.watch(sampleVMProvider(scenario));
      note = 'ข้อมูลตัวอย่าง (จำลอง) ไม่ใช่ข้อมูลตลาดจริง ลองกดเปลี่ยนสถานการณ์เพื่อดูว่าแอปตอบสนองอย่างไร';
    } else {
      result = readings.valueOrNull;
      if (result != null && result.readings.isNotEmpty) {
        vm = DashboardVM(live: true, scored: scoreAll(result.readings));
        note = 'ข้อมูลจริง อัปเดตล่าสุด ${thDateLong(vm.latest.reading.date)} · Claude ค้นข้อมูลใหม่ทุกวัน'
            '${result.fromCache ? '\nออฟไลน์อยู่ แสดงข้อมูลที่บันทึกไว้ล่าสุด' : ''}';
      } else if (readings.isLoading) {
        note = 'กำลังโหลดข้อมูลจริง…';
      } else if (readings.hasError) {
        note = '${readings.error}';
      } else {
        note = 'ยังไม่มีข้อมูลจริง';
      }
    }

    final alerts = vm == null ? 0 : vm.latest.subs.where((s) => s.level != Zone.expansion).length;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AI-CYCLE SENTINEL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 2)),
            Text('ติดตามวัฏจักรการลงทุน AI', style: TextStyle(fontSize: 11, color: AppColors.muted)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'สัญญาณที่ต้องจับตา',
            onPressed: _toSignals,
            icon: Badge(
              isLabelVisible: alerts > 0,
              backgroundColor: AppColors.red,
              label: Text('$alerts'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.green,
        backgroundColor: AppColors.surface,
        onRefresh: () => ref.refresh(readingsProvider.future).then((_) {}, onError: (_) {}),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                _ModeBar(live: live, scenario: scenario, note: note),
                const SizedBox(height: kGap),
                if (vm == null)
                  _LiveEmpty(loading: live && readings.isLoading, error: live && readings.hasError)
                else ...[
                  HealthCard(score: vm.latest.index, zone: vm.latest.zone),
                  AlertsList(vm: vm),
                  const SizedBox(height: kGap),
                  HistoryCard(key: ValueKey('h-${vm.live}-$scenario-${vm.scored.length}'), scored: vm.scored, live: vm.live),
                  const SizedBox(height: kGap),
                  AttributionCard(vm: vm),
                  SectionHeader(key: _signalsKey, title: '5 สัญญาณหลัก', trailing: 'คะแนน · น้ำหนัก'),
                  for (final s in vm.latest.subs) SignalTile(sub: s),
                  SectionHeader(
                    title: 'แนวทางจัดพอร์ต',
                    trailing: vm.actions.cashReservePct > 0
                        ? 'เงินสดสำรอง ${vm.actions.cashReservePct.toStringAsFixed(0)}%'
                        : 'ลงทุนครบ 100%',
                  ),
                  for (final r in vm.actions.recommendations)
                    ActionCard(key: ValueKey('a-${r.ticker}'), rec: r, scored: vm.latest, live: vm.live),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                    child: Text(
                      vm.actions.cashReservePct > 0
                          ? 'เงิน DCA ใหม่อีก ${vm.actions.cashReservePct.toStringAsFixed(0)}% ที่ไม่ได้จัดสรร ให้เก็บเป็นเงินสดสำรองไว้ก่อน'
                          : 'เงิน DCA ใหม่ถูกจัดสรรครบทั้ง 3 หุ้น',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                    ),
                  ),
                  if (vm.live) ...[
                    const SizedBox(height: kGap),
                    SourcesCard(reading: vm.latest.reading),
                  ],
                ],
                const SizedBox(height: 20),
                const Text(
                  'ผลลัพธ์มาจากกฎที่ตั้งไว้ล่วงหน้า เป็นเครื่องมือเพื่อการศึกษา ไม่ใช่คำแนะนำการลงทุน '
                  'ช่วงราคาเป็นเพียงกรอบตัวอย่างรอบราคาอ้างอิง ไม่ใช่ราคาเป้าหมาย ตัวเลขบางตัวเป็นค่าประมาณ '
                  'ดูระดับความมั่นใจในส่วนที่มาของข้อมูล ดึงหน้าจอลงเพื่อโหลดข้อมูลใหม่',
                  style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeBar extends ConsumerWidget {
  const _ModeBar({required this.live, required this.scenario, required this.note});

  final bool live;
  final String scenario;
  final String note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const scenarios = [('expansion', 'ขยายตัว'), ('early_warning', 'เตือนล่วงหน้า'), ('digestion', 'ย่อยการลงทุน')];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ToggleChip(
                label: 'ข้อมูลจริง',
                selected: live,
                expand: true,
                onTap: () => ref.read(liveModeProvider.notifier).state = true,
              ),
              const SizedBox(width: 6),
              ToggleChip(
                label: 'ตัวอย่างจำลอง',
                selected: !live,
                expand: true,
                onTap: () => ref.read(liveModeProvider.notifier).state = false,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (live)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(top: 6, right: 8),
                  decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle),
                ),
              Expanded(child: Text(note, style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.45))),
            ],
          ),
          if (!live) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (final (i, (key, label)) in scenarios.indexed) ...[
                  if (i > 0) const SizedBox(width: 6),
                  ToggleChip(
                    label: label,
                    selected: key == scenario,
                    expand: true,
                    onTap: () => ref.read(scenarioProvider.notifier).state = key,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LiveEmpty extends ConsumerWidget {
  const _LiveEmpty({required this.loading, required this.error});

  final bool loading;
  final bool error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator(color: AppColors.green)),
      );
    }
    return SurfaceCard(
      child: Column(
        children: [
          Icon(error ? Icons.cloud_off_rounded : Icons.hourglass_empty, color: AppColors.muted, size: 36),
          const SizedBox(height: 10),
          Text(
            error ? 'โหลดข้อมูลจริงไม่ได้' : 'ยังไม่มีข้อมูลจริง',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              ToggleChip(label: 'ลองใหม่', selected: true, expand: true, onTap: () => ref.invalidate(readingsProvider)),
              const SizedBox(width: 6),
              ToggleChip(
                label: 'ดูตัวอย่างจำลอง',
                selected: false,
                expand: true,
                onTap: () => ref.read(liveModeProvider.notifier).state = false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

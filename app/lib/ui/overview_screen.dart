import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/engine.dart';
import '../data/feed.dart';
import '../data/flex.dart';
import '../data/models.dart';
import '../state/providers.dart';
import '../state/settings.dart';
import 'briefs_screen.dart';
import 'news_screen.dart';
import 'sector_screen.dart';
import 'widgets/common.dart';
import 'widgets/market_pulse.dart';

enum _Verdict { normal, watch, volatile }

class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key, required this.onOpenBudget, required this.onOpenAlerts, required this.onOpenPortfolio});

  final VoidCallback onOpenBudget;
  final VoidCallback onOpenAlerts;
  final VoidCallback onOpenPortfolio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider);
    final settings = ref.watch(settingsProvider);
    final status = ref.watch(dataStatusProvider);
    final mine = ref.watch(myTargetsProvider);
    final sectors = ref.watch(allSectorsProvider).where((vm) => settings.isFollowed(vm.config.id)).toList()
      ..sort((a, b) => (b.config.funded ? 1 : 0).compareTo(a.config.funded ? 1 : 0));
    final latestDate = status.newestSectorDate;
    final statusChanges = latestDate == null
        ? const <AlertEvent>[]
        : ref.watch(allAlertsProvider).where((a) => a.kind == AlertKind.status && a.date == latestDate).toList();
    final market = ref.watch(marketProvider).valueOrNull;
    final flex = ref.watch(flexProvider);
    final budget = ref.watch(budgetProvider);
    final portfolio = ref.watch(portfolioProvider);
    final lastTrading = market?.quotes['SPY']?.asOf;
    final drops = lastTrading == null
        ? const <PriceEvent>[]
        : ref.watch(followedPriceEventsProvider).where((e) => e.date.compareTo(lastTrading) >= 0 && mine.contains(e.ticker)).toList();
    final briefs = ref.watch(briefsProvider).valueOrNull ?? const <Brief>[];
    final allNews = ref.watch(newsProvider).valueOrNull ?? const <NewsItem>[];
    final recent2 = isoDate(DateTime.now().subtract(const Duration(days: 2)));
    final highNews = allNews.where((n) => n.level == 'high' && n.date.compareTo(recent2) >= 0).toList();
    final cutoff = isoDate(DateTime.now().subtract(const Duration(days: 7)));
    final myNews = allNews.where((n) => n.level != 'low' && n.date.compareTo(cutoff) >= 0 && newsTouches(n, mine)).take(3).toList();

    final vix = market?.quotes['^VIX']?.price;
    final verdict = (vix != null && vix >= 30) || drops.length >= 3
        ? _Verdict.volatile
        : highNews.isNotEmpty || drops.isNotEmpty || statusChanges.isNotEmpty || (vix != null && vix >= 22)
            ? _Verdict.watch
            : _Verdict.normal;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI-CYCLE SENTINEL', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 2)),
            Text(thDateLong(isoDate(DateTime.now())), style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          ],
        ),
        actions: [
          if (latestDate != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: NeutralPill(
                label: status.stale ? 'ข้อมูลเก่า' : 'ข้อมูล ${thDate(latestDate)}',
                color: status.stale ? AppColors.yellow : AppColors.muted,
                icon: status.stale ? Icons.history : Icons.check,
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.text,
        backgroundColor: AppColors.surface,
        onRefresh: () async => refreshAll(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (status.offline || status.stale) ...[
              _FreshnessBanner(status: status),
              const SizedBox(height: kGap),
            ],
            if (config.hasError && sectors.isEmpty)
              ErrorCard(message: '${config.error}', onRetry: () => refreshAll(ref))
            else if (sectors.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: Center(child: CircularProgressIndicator(color: AppColors.text)),
              )
            else ...[
              _VerdictCard(
                verdict: verdict,
                vix: vix,
                news: highNews.length,
                drops: drops,
                changes: statusChanges.length,
                onTap: onOpenAlerts,
              ),
              if (budget != null) ...[
                const SizedBox(height: kGap),
                _MonthCard(flex: flex, tax: budget.tax, fallbackTotal: budget.main + budget.tech, done: settings.doneThisMonth, recorded: settings.recordedThisMonth, onTap: onOpenBudget),
              ],
              const SizedBox(height: kGap),
              _PortfolioStrip(total: portfolio?.isEmpty ?? true ? null : portfolio!.total, pnlPct: portfolio?.pnlPct, onTap: onOpenPortfolio),
              if (briefs.isNotEmpty) ...[
                const SectionHeader(title: 'สรุปล่าสุดจาก Claude'),
                BriefCard(
                  brief: briefs.first,
                  onMore: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BriefsScreen())),
                ),
              ],
              if (myNews.isNotEmpty) ...[
                SectionHeader(title: 'ข่าวที่กระทบพอร์ตคุณ', trailing: 'ดูทั้งหมด', onTrailing: onOpenAlerts),
                for (final n in myNews) Padding(padding: const EdgeInsets.only(bottom: 8), child: NewsTile(item: n, compact: true)),
              ],
              SectionHeader(title: 'หมวดที่ติดตาม (${sectors.length})', trailing: 'คะแนนพื้นฐาน 0–100'),
              SurfaceCard(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Column(
                  children: [
                    for (final (i, vm) in sectors.indexed) ...[
                      if (i > 0) const Divider(height: 1, indent: 12, endIndent: 12),
                      _SectorRow(vm: vm, market: market),
                    ],
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text('คะแนนบอกสภาพพื้นฐานของหมวด ไม่ได้พยากรณ์ผลตอบแทน (ทดสอบย้อนหลังแล้วแทบไม่มีพลังทำนาย) จึงใช้แค่ปรับน้ำหนัก ไม่ใช้หยุดซื้อ',
                    style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.45)),
              ),
              if (market != null && market.quotes.isNotEmpty) ...[
                const SizedBox(height: kGap),
                MarketPulseCard(
                  market: market,
                  sectors: [for (final vm in sectors) vm.config],
                  onSector: (id) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SectorScreen(sectorId: id))),
                ),
              ],
              const Disclaimer(),
            ],
          ],
        ),
      ),
    );
  }
}

class _FreshnessBanner extends StatelessWidget {
  const _FreshnessBanner({required this.status});

  final DataStatus status;

  @override
  Widget build(BuildContext context) {
    final age = status.sectorAgeHours;
    final text = status.offline
        ? 'ออฟไลน์หรือโหลดไม่สำเร็จ: กำลังแสดงข้อมูลที่บันทึกไว้ในเครื่อง ดึงลงเพื่อลองใหม่'
        : 'ข้อมูลหมวดล่าสุด ${status.oldestSectorDate == null ? '' : thDate(status.oldestSectorDate!)}'
            '${age == null ? '' : ' (${(age / 24).toStringAsFixed(0)} วันก่อน)'} อาจยังไม่ได้อัปเดต ตัวเลขด้านล่างอาจไม่ตรงกับวันนี้';
    return SurfaceCard(
      borderColor: AppColors.yellow.withAlpha(110),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(status.offline ? Icons.cloud_off_outlined : Icons.history, size: 18, color: AppColors.yellow),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.45))),
      ]),
    );
  }
}

class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.verdict, required this.vix, required this.news, required this.drops, required this.changes, required this.onTap});

  final _Verdict verdict;
  final double? vix;
  final int news;
  final List<PriceEvent> drops;
  final int changes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (title, body, color, icon) = switch (verdict) {
      _Verdict.normal => ('วันนี้: ปกติ', 'ไม่มีเรื่องต้องทำ ลงทุนตามแผนเดือนนี้ได้ตามปกติ', AppColors.text, Icons.check_circle_outline),
      _Verdict.watch => ('วันนี้: มีเรื่องควรอ่าน', 'แผนไม่เปลี่ยน: ไม่หยุดซื้อ ไม่ขายตามข่าว อ่านรายละเอียดได้ในแจ้งเตือน', AppColors.yellow, Icons.visibility_outlined),
      _Verdict.volatile => (
          'วันนี้: ตลาดผันผวน',
          'ราคาที่ย่อลงทำให้แผนซื้อเพิ่มจากเงินสำรองเอง (มีเพดานกันไว้) ไม่ต้องตัดสินใจอะไรเพิ่ม',
          AppColors.yellow,
          Icons.waves
        ),
    };
    Widget count(String label, String value) => Expanded(
          child: Column(children: [
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, fontFeatures: tabular)),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
          ]),
        );
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadius),
        side: BorderSide(color: verdict == _Verdict.normal ? AppColors.line : color.withAlpha(110)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700))),
                const Icon(Icons.chevron_right, color: AppColors.muted),
              ]),
              const SizedBox(height: 6),
              Text(body, style: const TextStyle(fontSize: 14, height: 1.5)),
              if (drops.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('ราคาร่วงแรง: ${drops.map((e) => e.ticker).toSet().join(', ')}',
                    style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.45)),
              ],
              const Divider(height: 22),
              Row(children: [
                count('ข่าวสำคัญ', '$news'),
                count('ราคาร่วงแรง\nในพอร์ต', '${drops.length}'),
                count('หมวดเปลี่ยน\nสถานะ', '$changes'),
                count('ดัชนีความกลัว\n(VIX)', vix == null ? '–' : vix!.toStringAsFixed(0)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.flex, required this.tax, required this.fallbackTotal, required this.done, required this.recorded, required this.onTap});

  final FlexPlan? flex;
  final double tax;
  final double fallbackTotal;
  final List<String> done;
  final bool recorded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final f = flex;
    final lines = f == null ? const <FlexLine>[] : (f.lines.values.where((l) => l.planned >= 1).toList()..sort((a, b) => b.planned.compareTo(a.planned)));
    final total = (f?.plannedTotal ?? fallbackTotal) + tax;
    final ticked = lines.where((l) => done.contains(l.key)).length;
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius), side: const BorderSide(color: AppColors.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Eyebrow('เดือน${thMonthYear(DateTime.now())}')),
                if (recorded)
                  const NeutralPill(label: 'บันทึกแล้ว', icon: Icons.check)
                else if (lines.isNotEmpty)
                  NeutralPill(label: 'ซื้อแล้ว $ticked/${lines.length}', color: ticked == lines.length ? AppColors.text : AppColors.muted),
              ]),
              const SizedBox(height: 6),
              Text('ลงทุน ${baht(total)} บาท', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, fontFeatures: tabular)),
              const SizedBox(height: 8),
              for (final l in lines.take(3))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Icon(done.contains(l.key) ? Icons.check_box : Icons.check_box_outline_blank, size: 16, color: AppColors.muted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(l.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14))),
                    if (l.multiplier > 1.01)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text('×${l.multiplier.toStringAsFixed(1)}', style: const TextStyle(fontSize: 12.5, color: AppColors.buy, fontWeight: FontWeight.w700)),
                      ),
                    Text(baht(l.planned), style: const TextStyle(fontSize: 14, fontFeatures: tabular)),
                  ]),
                ),
              if (lines.length > 3)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('และอีก ${lines.length - 3} รายการ · ดูรายการซื้อทั้งหมด', style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PortfolioStrip extends StatelessWidget {
  const _PortfolioStrip({required this.total, required this.pnlPct, required this.onTap});

  final double? total;
  final double? pnlPct;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius), side: const BorderSide(color: AppColors.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadius),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            const Icon(Icons.pie_chart_outline, size: 20, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: total == null
                  ? const Text('บันทึกพอร์ตจริงเพื่อดูความเสี่ยงรวมและให้แผนช่วยปรับสมดุล', style: TextStyle(fontSize: 13.5, height: 1.4))
                  : Text.rich(TextSpan(children: [
                      const TextSpan(text: 'พอร์ตของคุณ  ', style: TextStyle(fontSize: 13, color: AppColors.muted)),
                      TextSpan(text: '${baht(total!)} บาท', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, fontFeatures: tabular)),
                      if (pnlPct != null)
                        TextSpan(text: '  ${pct(pnlPct)}', style: TextStyle(fontSize: 13, color: pctColor(pnlPct), fontFeatures: tabular)),
                    ])),
            ),
            const Icon(Icons.chevron_right, color: AppColors.muted),
          ]),
        ),
      ),
    );
  }
}

class _SectorRow extends StatelessWidget {
  const _SectorRow({required this.vm, required this.market});

  final SectorVM vm;
  final MarketData? market;

  @override
  Widget build(BuildContext context) {
    final z = vm.latest.zone;
    final color = zoneColor(z);
    final changed = vm.previousZone != null && vm.previousZone != z;
    final hist = vm.scored.length > 30 ? vm.scored.sublist(vm.scored.length - 30) : vm.scored;
    final dd = market == null ? null : sectorDrawdown(vm.config, market!);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SectorScreen(sectorId: vm.config.id))),
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(sectorIcon(vm.config.icon), size: 20, color: AppColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(vm.config.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    NeutralPill(label: levelTh(z), color: color, icon: zoneIcon(z)),
                    if (changed) const Text('เปลี่ยนวันนี้', style: TextStyle(fontSize: 11.5, color: AppColors.yellow)),
                    Text(vm.config.funded ? 'ลงเงินจริง' : 'ดูอย่างเดียว', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                    if (dd != null) Text('ราคา ${dd.toStringAsFixed(0)}% จากยอด', style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontFeatures: tabular)),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 54, height: 26, child: CustomPaint(painter: _Spark([for (final s in hist) s.index], color))),
            const SizedBox(width: 10),
            SizedBox(
              width: 34,
              child: Text(vm.latest.index.round().toString(),
                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, fontFeatures: tabular)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Spark extends CustomPainter {
  _Spark(this.values, this.color);

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var lo = values.reduce((a, b) => a < b ? a : b), hi = values.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 5) {
      final mid = (hi + lo) / 2;
      lo = mid - 2.5;
      hi = mid + 2.5;
    }
    final path = Path();
    for (final (i, v) in values.indexed) {
      final x = i / (values.length - 1) * size.width;
      final y = size.height - (v - lo) / (hi - lo) * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color.withAlpha(200)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_Spark old) => old.values != values || old.color != color;
}

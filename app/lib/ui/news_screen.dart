import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/feed.dart';
import '../data/flex.dart';
import '../state/providers.dart';
import '../state/settings.dart';
import 'sector_screen.dart';
import 'widgets/common.dart';
import 'widgets/market_pulse.dart';

Color newsLevelColor(String level) => switch (level) { 'high' => AppColors.red, 'medium' => AppColors.yellow, _ => AppColors.muted };

String newsLevelTh(String level) => switch (level) { 'high' => 'สำคัญมาก', 'medium' => 'ควรรู้', _ => 'ทั่วไป' };

String newsCategoryTh(String c) => switch (c) {
      'fed' => 'Fed / ดอกเบี้ย',
      'rates' => 'ดอกเบี้ย',
      'inflation' => 'เงินเฟ้อ',
      'jobs' => 'ตลาดแรงงาน',
      'geopolitics' => 'ภูมิรัฐศาสตร์',
      'war' => 'สงคราม',
      'crisis' => 'วิกฤต',
      'policy' => 'นโยบาย',
      'election' => 'การเมือง',
      'earnings' => 'งบบริษัท',
      'sector' => 'อุตสาหกรรม',
      'thailand' => 'ไทย',
      _ => 'ตลาด',
    };

IconData directionIcon(String d) => switch (d) { 'negative' => Icons.south_east, 'positive' => Icons.north_east, _ => Icons.swap_vert };

Color directionColor(String d) => switch (d) { 'negative' => AppColors.red, 'positive' => AppColors.green, _ => AppColors.yellow };

class NewsTile extends StatelessWidget {
  const NewsTile({super.key, required this.item, this.compact = false});

  final NewsItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = newsLevelColor(item.level);
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: item.level == 'high' ? c.withAlpha(110) : AppColors.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NewsDetailScreen(item: item))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusPill(label: newsLevelTh(item.level), color: c),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('${newsCategoryTh(item.category)} · ${thDate(item.date)}',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(item.title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.35)),
              if (!compact) ...[
                const SizedBox(height: 4),
                Text(item.summary, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.45)),
              ],
              if (item.impacts.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final i in item.impacts.take(compact ? 3 : 6))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: AppColors.sunken, borderRadius: BorderRadius.circular(8)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(directionIcon(i.direction), size: 13, color: directionColor(i.direction)),
                          const SizedBox(width: 4),
                          Text(i.label, style: const TextStyle(fontSize: 11.5)),
                        ]),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class NewsDetailScreen extends ConsumerWidget {
  const NewsDetailScreen({super.key, required this.item});

  final NewsItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider).valueOrNull;
    final c = newsLevelColor(item.level);
    String? sectorOf(String target) => config?.sector(target) != null ? target : null;
    return Scaffold(
      appBar: AppBar(title: const Text('ข่าวและผลกระทบ', style: TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          SurfaceCard(
            borderColor: c.withAlpha(100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  StatusPill(label: newsLevelTh(item.level), color: c),
                  const SizedBox(width: 6),
                  Text('${newsCategoryTh(item.category)} · ${thDateLong(item.date)}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ]),
                const SizedBox(height: 10),
                Text(item.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.3)),
                const SizedBox(height: 10),
                Text(item.summary, style: const TextStyle(fontSize: 14.5, height: 1.55)),
              ],
            ),
          ),
          if (item.impacts.isNotEmpty) ...[
            const SectionHeader(title: 'กระทบพอร์ตอย่างไร'),
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, imp) in item.impacts.indexed)
                    InkWell(
                      onTap: sectorOf(imp.target) == null
                          ? null
                          : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SectorScreen(sectorId: imp.target))),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(directionIcon(imp.direction), size: 20, color: directionColor(imp.direction)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Expanded(child: Text(imp.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                                    Text(
                                      '${imp.direction == 'negative' ? 'ลบ' : imp.direction == 'positive' ? 'บวก' : 'ผสม'} · ${imp.strength == 'high' ? 'แรง' : imp.strength == 'low' ? 'เล็กน้อย' : 'ปานกลาง'}',
                                      style: TextStyle(fontSize: 12, color: directionColor(imp.direction)),
                                    ),
                                  ]),
                                  if (imp.reason.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(imp.reason, style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.45)),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (item.whatToDo.isNotEmpty) ...[
            const SectionHeader(title: 'ควรทำอะไร'),
            ExplainBlock(title: item.whatToDo, tags: const [Provenance.estimate], body: 'Claude วิเคราะห์ตามกฎของแอป: ไม่หยุดซื้อหรือขายตามข่าว ใช้งบยืดหยุ่นซื้อเพิ่มเมื่อราคาย่อ'),
          ],
          if (item.watchNext.isNotEmpty) ...[
            const SectionHeader(title: 'สิ่งที่ต้องติดตามต่อ'),
            SurfaceCard(child: Text(item.watchNext, style: const TextStyle(fontSize: 13.5, height: 1.5))),
          ],
          if (item.sources.isNotEmpty) ...[
            const SectionHeader(title: 'แหล่งข่าว'),
            SurfaceCard(child: LinkRow(links: item.sources)),
          ],
          const SizedBox(height: kGap),
          const Text('สรุปและวิเคราะห์โดย Claude จากแหล่งข่าวข้างบน อาจคลาดเคลื่อนได้ ควรเปิดอ่านต้นฉบับประกอบ',
              style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.45)),
          const Disclaimer(),
        ],
      ),
    );
  }
}

class PriceEventTile extends StatelessWidget {
  const PriceEventTile({super.key, required this.event});

  final PriceEvent event;

  @override
  Widget build(BuildContext context) {
    final c = event.kind == 'day_drop' ? AppColors.red : AppColors.yellow;
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.withAlpha(90))),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PriceEventScreen(event: event))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(event.kind == 'day_drop' ? Icons.trending_down : Icons.south, color: c, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.title.isNotEmpty ? event.title : event.ticker, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text('${event.name} · ${event.detail}', style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.45)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PriceEventScreen extends ConsumerWidget {
  const PriceEventScreen({super.key, required this.event});

  final PriceEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = event;
    final config = ref.watch(configProvider).valueOrNull;
    final market = ref.watch(marketProvider).valueOrNull;
    final s = ref.watch(settingsProvider);
    final news = ref.watch(newsProvider).valueOrNull ?? const [];
    final q = market?.quotes[e.ticker];
    final sector = config?.sectors.where((x) => x.stocks.any((st) => st.ticker == e.ticker)).firstOrNull;
    final related = news.where((n) => n.impacts.any((i) => i.target == e.ticker || i.target == sector?.id) || n.title.contains(e.ticker)).take(3).toList();
    final m = flexMultiplier(s.flexMode, q?.drawdownPct ?? e.drawdown);
    return Scaffold(
      appBar: AppBar(title: Text(e.ticker, style: const TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.3)),
                const SizedBox(height: 6),
                Text('${e.name} · ${thDateLong(e.date)}', style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                const SizedBox(height: 8),
                Text(e.detail, style: const TextStyle(fontSize: 14, height: 1.5)),
                if (q != null) ...[
                  const Divider(height: 20),
                  Text('ล่าสุด ${money(q.price, q.currency)} (${pct(q.change1d)} วันนี้) · ห่างจุดสูงสุด ${q.drawdownPct?.toStringAsFixed(1) ?? '–'}%'
                      '${q.vsMa200 != null ? ' · ${q.vsMa200! >= 0 ? 'เหนือ' : 'ใต้'}เส้น 200 วัน ${q.vsMa200!.abs().toStringAsFixed(0)}%' : ''}',
                      style: const TextStyle(fontSize: 13, color: AppColors.muted, height: 1.45)),
                ],
              ],
            ),
          ),
          const SectionHeader(title: 'แผนว่าอย่างไร'),
          ExplainBlock(
            title: s.flexMode == FlexMode.off
                ? 'งบแบบคงที่: ลงตามปกติ ไม่หยุด ไม่ขาย'
                : 'งบยืดหยุ่น: เดือนนี้ลง ${e.ticker} ×${m.toStringAsFixed(1)} ของงบฐาน',
            tags: const [Provenance.rule],
            body: 'ทดสอบย้อนหลังพบว่าการหยุดซื้อหรือขายตอนราคาร่วงมักทำให้พลาดช่วงฟื้น แผนจึงใช้เงินสำรองซื้อเพิ่มเมื่อราคาห่างจุดสูงสุดมาก '
                'ถ้าราคาร่วงเพราะพื้นฐานบริษัทเปลี่ยน (ไม่ใช่แค่ตลาดตื่นตระหนก) ควรอ่านข่าวที่เกี่ยวข้องก่อนตัดสินใจ',
          ),
          if (related.isNotEmpty) ...[
            const SectionHeader(title: 'ข่าวที่เกี่ยวข้อง'),
            for (final n in related) Padding(padding: const EdgeInsets.only(bottom: 8), child: NewsTile(item: n, compact: true)),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('ยังไม่มีข่าวอธิบายเหตุการณ์นี้ Claude จะค้นหาสาเหตุในรอบเช้าหรือค่ำถัดไป',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
            ),
          if (sector != null) ...[
            const SizedBox(height: kGap),
            Row(children: [
              ToggleChip(
                label: 'ดูหมวด${sector.name}',
                selected: true,
                expand: true,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SectorScreen(sectorId: sector.id))),
              ),
            ]),
          ],
          const SizedBox(height: kGap),
          LinkRow(prefix: 'ราคาจาก Yahoo Finance', links: [('เปิดกราฟ', 'https://finance.yahoo.com/quote/${Uri.encodeComponent(e.ticker)}')]),
          const Disclaimer(),
        ],
      ),
    );
  }
}

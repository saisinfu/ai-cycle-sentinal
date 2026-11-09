import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../data/feed.dart';
import '../state/providers.dart';
import 'news_screen.dart';
import 'widgets/common.dart';

String briefTime(Brief b) {
  final t = DateTime.tryParse(b.time);
  if (t == null) return '${b.runTh} · ${thDate(b.date)}';
  final l = t.toLocal();
  return '${b.runTh} · ${thDate(b.date)} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')} น.';
}

/// Card with one run summary; [expanded] shows the full text and linked news.
class BriefCard extends ConsumerWidget {
  const BriefCard({super.key, required this.brief, this.expanded = false, this.onMore});

  final Brief brief;
  final bool expanded;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = brief;
    final c = newsLevelColor(b.level);
    final news = expanded ? (ref.watch(newsProvider).valueOrNull ?? const <NewsItem>[]) : const <NewsItem>[];
    final linked = [for (final id in b.newsIds) ...news.where((n) => n.id == id)];
    return SurfaceCard(
      borderColor: b.level == 'high' ? c.withAlpha(100) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(b.run == 'evening' ? Icons.nights_stay_outlined : Icons.wb_sunny_outlined, size: 16, color: AppColors.muted),
              const SizedBox(width: 6),
              Expanded(child: Text(briefTime(b), style: const TextStyle(fontSize: 12, color: AppColors.muted))),
              if (b.level == 'high') StatusPill(label: newsLevelTh(b.level), color: c),
            ],
          ),
          const SizedBox(height: 8),
          if (b.headline.isNotEmpty) Text(b.headline, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.35)),
          if (b.text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              b.text,
              maxLines: expanded ? null : 6,
              overflow: expanded ? null : TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, height: 1.55),
            ),
          ],
          if (b.reconstructed)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('สรุปย้อนหลังจากข่าวที่บันทึกไว้ (ก่อนเริ่มเก็บข้อความแจ้งเตือนต้นฉบับ)',
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ),
          if (onMore != null) ...[
            const SizedBox(height: 6),
            TextLinkButton(label: 'ดูสรุปทั้งหมด', onTap: onMore!),
          ],
          if (linked.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final n in linked) Padding(padding: const EdgeInsets.only(bottom: 8), child: NewsTile(item: n, compact: true)),
          ],
        ],
      ),
    );
  }
}

class BriefsScreen extends ConsumerWidget {
  const BriefsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(briefsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('สรุปจาก Claude', style: TextStyle(fontWeight: FontWeight.w700))),
      body: RefreshIndicator(
        color: AppColors.text,
        backgroundColor: AppColors.surface,
        onRefresh: () async => refreshAll(ref),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.text)),
          error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(16), child: ErrorCard(message: '$e', onRetry: () => refreshAll(ref)))]),
          data: (briefs) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              const Text('ข้อความเดียวกับที่ Claude ส่งแจ้งเตือนเข้ามือถือ รอบเช้า ~08:00 และรอบค่ำ ~21:00 น.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.4)),
              const SizedBox(height: kGap),
              if (briefs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: Text('ยังไม่มีสรุป', style: TextStyle(color: AppColors.muted))),
                ),
              for (final b in briefs) Padding(padding: const EdgeInsets.only(bottom: kGap), child: BriefCard(brief: b, expanded: true)),
              const Disclaimer(),
            ],
          ),
        ),
      ),
    );
  }
}

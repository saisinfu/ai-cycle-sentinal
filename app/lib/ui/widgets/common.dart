import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';

const double kGap = 12;
const double kRadius = 16;
const tabular = [FontFeature.tabularFigures()];

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.borderColor, this.color});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: borderColor ?? AppColors.line),
      ),
      child: child,
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(36),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(115)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

enum Provenance { data, calc, rule, estimate }

/// Small label that says where a number comes from.
class SourceTag extends StatelessWidget {
  const SourceTag(this.kind, {super.key});

  final Provenance kind;

  static Provenance fromKey(String k) => switch (k) {
        'data' => Provenance.data,
        'calc' => Provenance.calc,
        'estimate' => Provenance.estimate,
        _ => Provenance.rule,
      };

  @override
  Widget build(BuildContext context) {
    final (label, color, dashed) = switch (kind) {
      Provenance.data => ('ข้อมูล', AppColors.tagData, false),
      Provenance.calc => ('คำนวณ', AppColors.tagCalc, false),
      Provenance.rule => ('กฎ', AppColors.text, false),
      Provenance.estimate => ('ประมาณ', AppColors.muted, true),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: dashed ? AppColors.muted : color.withAlpha(110), style: BorderStyle.solid),
        color: dashed ? AppColors.raised : Colors.transparent,
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing, this.onTrailing});

  final String title;
  final String? trailing;
  final VoidCallback? onTrailing;

  @override
  Widget build(BuildContext context) {
    final t = trailing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Expanded(child: Eyebrow(title)),
          if (t != null)
            onTrailing == null
                ? Text(t, style: const TextStyle(color: AppColors.muted, fontSize: 12))
                : InkWell(
                    onTap: onTrailing,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        t,
                        style: const TextStyle(fontSize: 12.5, decoration: TextDecoration.underline, decorationColor: AppColors.muted),
                      ),
                    ),
                  ),
        ],
      ),
    );
  }
}

class ToggleChip extends StatelessWidget {
  const ToggleChip({super.key, required this.label, required this.selected, required this.onTap, this.expand = false});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final chip = Material(
      color: selected ? AppColors.raised : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? AppColors.muted : AppColors.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40, minWidth: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: selected ? AppColors.text : AppColors.muted),
          ),
        ),
      ),
    );
    return expand ? Expanded(child: chip) : chip;
  }
}

/// Shaded explanation block: title, tags, body text and optional source links.
class ExplainBlock extends StatelessWidget {
  const ExplainBlock({super.key, required this.title, required this.tags, required this.body, this.links = const [], this.action});

  final String title;
  final List<Provenance> tags;
  final String body;
  final List<(String, String)> links;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.sunken, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
              for (final t in tags) ...[const SizedBox(width: 4), SourceTag(t)],
            ],
          ),
          const SizedBox(height: 4),
          Text(body, style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.5)),
          if (links.isNotEmpty) ...[const SizedBox(height: 2), LinkRow(links: links)],
          if (action != null) action!,
        ],
      ),
    );
  }
}

Future<void> openLink(BuildContext context, String url) async {
  bool ok;
  try {
    ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('เปิดลิงก์ไม่ได้')));
  }
}

class LinkRow extends StatelessWidget {
  const LinkRow({super.key, required this.links, this.prefix});

  final List<(String, String)> links;
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (prefix != null) Text(prefix!, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        for (final (label, url) in links)
          InkWell(
            onTap: () => openLink(context, url),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                label,
                style: const TextStyle(fontSize: 12.5, decoration: TextDecoration.underline, decorationColor: AppColors.muted),
              ),
            ),
          ),
      ],
    );
  }
}

class TextLinkButton extends StatelessWidget {
  const TextLinkButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class Disclaimer extends StatelessWidget {
  const Disclaimer({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(4, 20, 4, 0),
      child: Text(
        'ผลลัพธ์มาจากกฎที่ตั้งไว้ล่วงหน้า เป็นเครื่องมือเพื่อการศึกษา ไม่ใช่คำแนะนำการลงทุน '
        'ตัวเลขบางตัวเป็นค่าประมาณ ดูป้ายที่มาและความมั่นใจประกอบ ดึงหน้าจอลงเพื่อโหลดข้อมูลใหม่',
        style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45),
      ),
    );
  }
}

class ErrorCard extends StatelessWidget {
  const ErrorCard({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.muted, size: 32),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 12),
          Row(children: [ToggleChip(label: 'ลองใหม่', selected: true, expand: true, onTap: onRetry)]),
        ],
      ),
    );
  }
}

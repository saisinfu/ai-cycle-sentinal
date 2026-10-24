import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/engine.dart';
import 'common.dart';

/// Index line over status zones, with the ±3 dead-band drawn as grey stripes,
/// ticks on days the status changed, and touch-and-drag readout.
class HistoryCard extends StatefulWidget {
  const HistoryCard({super.key, required this.scored, required this.live});

  final List<Scored> scored;
  final bool live;

  @override
  State<HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<HistoryCard> {
  int? _selected;

  static const _height = 180.0;
  static const _padRight = 30.0;

  void _pick(double dx, double width) {
    final n = widget.scored.length;
    final i = ((dx / (width - _padRight)) * (n - 1)).round().clamp(0, n - 1);
    if (i != _selected) setState(() => _selected = i);
  }

  void _clear() {
    if (_selected != null) setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.scored;
    final last = pts.last;
    final title = widget.live ? 'ประวัติดัชนี (ข้อมูลจริง)' : 'ประวัติดัชนี 90 วัน (จำลอง)';
    if (pts.length < 2) {
      return SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Eyebrow(title),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'มีข้อมูล 1 ครั้ง (${thDateLong(last.reading.date)})\nกราฟจะแสดงหลังการอัปเดตครั้งถัดไป',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 13.5),
              ),
            ),
          ],
        ),
      );
    }
    final shown = pts[_selected ?? pts.length - 1];
    var changes = 0;
    for (var i = 1; i < pts.length; i++) {
      if (pts[i].zone != pts[i - 1].zone) changes++;
    }
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Eyebrow(title)),
              Text(
                '${pts.first.index.toStringAsFixed(0)} → ${last.index.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 13, fontFeatures: tabular),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  _selected == null ? 'ล่าสุด' : thDate(shown.reading.date),
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ),
              Text(
                shown.index.toStringAsFixed(1),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, fontFeatures: tabular),
              ),
              const SizedBox(width: 10),
              StatusPill(label: zoneTh(shown.zone), color: zoneColor(shown.zone)),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _pick(d.localPosition.dx, c.maxWidth),
              onTapUp: (_) => _clear(),
              onHorizontalDragStart: (d) => _pick(d.localPosition.dx, c.maxWidth),
              onHorizontalDragUpdate: (d) => _pick(d.localPosition.dx, c.maxWidth),
              onHorizontalDragEnd: (_) => _clear(),
              onHorizontalDragCancel: _clear,
              child: CustomPaint(
                size: Size(c.maxWidth, _height),
                painter: _HistoryPainter(scored: pts, selected: _selected, dots: widget.live && pts.length <= 40),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'แถบสีเทา = ช่วงกันชน ±${hysteresisBand.toStringAsFixed(0)} แต้ม สถานะจะเปลี่ยนเมื่อเส้นหลุดออกจากแถบเท่านั้น '
            '(เปลี่ยน $changes ครั้ง) แตะค้างแล้วลากบนกราฟเพื่อดูค่าแต่ละวัน',
            style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _HistoryPainter extends CustomPainter {
  _HistoryPainter({required this.scored, required this.selected, required this.dots});

  final List<Scored> scored;
  final int? selected;
  final bool dots;

  @override
  void paint(Canvas canvas, Size size) {
    const padR = 30.0, padT = 8.0, padB = 22.0;
    final plot = Rect.fromLTRB(0, padT, size.width - padR, size.height - padB);
    final scores = scored.map((s) => s.index).toList();
    final lo = math.max(0.0, ((math.min(scores.reduce(math.min), digestionThreshold + 10) - 5) / 10).floor() * 10.0);
    final hi = math.min(100.0, ((math.max(scores.reduce(math.max), expansionThreshold) + 5) / 10).ceil() * 10.0);
    double y(double v) => plot.bottom - (v - lo) / (hi - lo) * plot.height;
    double x(int i) => plot.left + i / (scored.length - 1) * plot.width;

    canvas.save();
    canvas.clipRect(plot);
    void band(double top, double bottom, Color c, int alpha) {
      canvas.drawRect(Rect.fromLTRB(plot.left, y(top), plot.right, y(bottom)), Paint()..color = c.withAlpha(alpha));
    }

    band(hi, expansionThreshold, AppColors.green, 16);
    band(expansionThreshold, digestionThreshold, AppColors.yellow, 16);
    band(digestionThreshold, lo, AppColors.red, 16);
    for (final t in const [expansionThreshold, digestionThreshold]) {
      band(t + hysteresisBand, t - hysteresisBand, AppColors.muted, 34);
      final dash = Paint()
        ..color = AppColors.muted.withAlpha(150)
        ..strokeWidth = 1;
      for (var dx = plot.left; dx < plot.right; dx += 6) {
        canvas.drawLine(Offset(dx, y(t)), Offset(math.min(dx + 3, plot.right), y(t)), dash);
      }
    }
    final path = Path()..moveTo(x(0), y(scores[0]));
    for (var i = 1; i < scores.length; i++) {
      path.lineTo(x(i), y(scores[i]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = AppColors.text,
    );
    if (dots) {
      for (var i = 0; i < scores.length; i++) {
        canvas.drawCircle(Offset(x(i), y(scores[i])), 2.5, Paint()..color = AppColors.text);
      }
    }
    canvas.restore();

    for (var i = 1; i < scored.length; i++) {
      if (scored[i].zone != scored[i - 1].zone) {
        canvas.drawLine(
          Offset(x(i), plot.bottom + 3),
          Offset(x(i), plot.bottom + 9),
          Paint()
            ..color = zoneColor(scored[i].zone)
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    final sel = selected;
    if (sel != null) {
      canvas.drawLine(Offset(x(sel), plot.top), Offset(x(sel), plot.bottom), Paint()..color = AppColors.muted);
    }
    final i = sel ?? scored.length - 1;
    final p = Offset(x(i), y(scores[i]));
    canvas.drawCircle(p, 6.5, Paint()..color = AppColors.surface);
    canvas.drawCircle(p, 4.5, Paint()..color = zoneColor(scored[i].zone));

    void label(String text, Offset at, {bool right = false}) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: const TextStyle(color: AppColors.muted, fontSize: 10.5)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, right ? at - Offset(tp.width, 0) : at);
    }

    for (final t in const [expansionThreshold, digestionThreshold]) {
      if (t > lo && t < hi) label(t.toStringAsFixed(0), Offset(plot.right + 6, y(t) - 7));
    }
    label(thDate(scored.first.reading.date), Offset(plot.left, plot.bottom + 8));
    label(thDate(scored.last.reading.date), Offset(plot.right, plot.bottom + 8), right: true);
  }

  @override
  bool shouldRepaint(_HistoryPainter old) => old.scored != scored || old.selected != selected;
}

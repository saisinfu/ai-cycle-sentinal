import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/engine.dart';
import '../../data/zone.dart';
import 'common.dart';

/// Index line over status zones with the ±3 dead-band, status-change ticks,
/// a range selector and touch-and-drag readout.
class HistoryCard extends StatefulWidget {
  const HistoryCard({super.key, required this.scored});

  final List<Scored> scored;

  @override
  State<HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<HistoryCard> {
  int? _selected;
  int _days = 30;

  static const _height = 170.0;
  static const _padRight = 30.0;

  List<Scored> get _points {
    final all = widget.scored;
    if (all.isEmpty) return all;
    final cutoff = parseDate(all.last.reading.date).subtract(Duration(days: _days));
    final list = all.where((s) => !parseDate(s.reading.date).isBefore(cutoff)).toList();
    return list.length >= 2 ? list : all;
  }

  void _pick(double dx, double width, int n) {
    final i = ((dx / (width - _padRight)) * (n - 1)).round().clamp(0, n - 1);
    if (i != _selected) setState(() => _selected = i);
  }

  void _clear() {
    if (_selected != null) setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final pts = _points;
    final last = pts.last;
    if (pts.length < 2) {
      return SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Eyebrow('ประวัติดัชนี'),
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
    final sel = _selected != null && _selected! < pts.length ? _selected : null;
    final shown = pts[sel ?? pts.length - 1];
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
              const Expanded(child: Eyebrow('ประวัติดัชนี')),
              Text('${pts.first.index.toStringAsFixed(0)} → ${last.index.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 13, fontFeatures: tabular)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final (i, (d, label)) in const [(7, '7D'), (30, '30D'), (90, '90D'), (365, '1Y')].indexed) ...[
                if (i > 0) const SizedBox(width: 6),
                ToggleChip(label: label, selected: _days == d, onTap: () => setState(() {
                      _days = d;
                      _selected = null;
                    })),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(sel == null ? 'ล่าสุด' : thDate(shown.reading.date),
                    style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ),
              Text(shown.index.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, fontFeatures: tabular)),
              const SizedBox(width: 10),
              StatusPill(label: zoneName(shown.zone), color: zoneColor(shown.zone)),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _pick(d.localPosition.dx, c.maxWidth, pts.length),
              onTapUp: (_) => _clear(),
              onHorizontalDragStart: (d) => _pick(d.localPosition.dx, c.maxWidth, pts.length),
              onHorizontalDragUpdate: (d) => _pick(d.localPosition.dx, c.maxWidth, pts.length),
              onHorizontalDragEnd: (_) => _clear(),
              onHorizontalDragCancel: _clear,
              child: CustomPaint(
                size: Size(c.maxWidth, _height),
                painter: _HistoryPainter(scored: pts, selected: sel),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'แถบเทา = ช่วงกันชน ±${hysteresisBand.toStringAsFixed(0)} แต้ม สถานะเปลี่ยนเมื่อเส้นหลุดออกจากแถบเท่านั้น '
            '(เปลี่ยน $changes ครั้งในช่วงนี้) · ขีดสีใต้กราฟ = วันที่สถานะเปลี่ยน · แตะค้างแล้วลากเพื่อดูค่าแต่ละวัน',
            style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _HistoryPainter extends CustomPainter {
  _HistoryPainter({required this.scored, required this.selected});

  final List<Scored> scored;
  final int? selected;

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
    void band(double top, double bottom, Color c, int alpha) =>
        canvas.drawRect(Rect.fromLTRB(plot.left, y(top), plot.right, y(bottom)), Paint()..color = c.withAlpha(alpha));
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
    if (scores.length <= 40) {
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
    if (sel != null) canvas.drawLine(Offset(x(sel), plot.top), Offset(x(sel), plot.bottom), Paint()..color = AppColors.muted);
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

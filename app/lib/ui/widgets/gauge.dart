import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'common.dart';

/// 240° arc gauge. [size] 64 for cards, ~200 for the sector header.
class Gauge extends StatelessWidget {
  const Gauge({super.key, required this.score, required this.color, this.size = 200, this.animate = true});

  final double score;
  final Color color;
  final double size;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final big = size >= 120;
    Widget body(double v) => SizedBox(
          width: size,
          height: size * (big ? 1 : 0.9),
          child: CustomPaint(
            painter: _GaugePainter(value: v, color: color, stroke: big ? 15 : 6, ticks: big),
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(top: size * 0.08),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      v.toStringAsFixed(0),
                      style: TextStyle(fontSize: big ? size * 0.27 : 20, fontWeight: FontWeight.w700, height: 1, fontFeatures: tabular),
                    ),
                    if (big) ...[
                      const SizedBox(height: 4),
                      const Text('/ 100', style: TextStyle(color: AppColors.muted, fontSize: 12, letterSpacing: 1)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
    return Semantics(
      label: 'คะแนน ${score.toStringAsFixed(0)} จาก 100',
      child: animate
          ? TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: score),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => body(v),
            )
          : body(score),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.value, required this.color, required this.stroke, required this.ticks});

  final double value;
  final Color color;
  final double stroke;
  final bool ticks;

  static const _start = 150 * math.pi / 180;
  static const _sweep = 240 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.width - stroke) / 2;
    final c = Offset(size.width / 2, size.width / 2);
    final rect = Rect.fromCircle(center: c, radius: r);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep, false, p..color = AppColors.raised);
    if (value > 0) canvas.drawArc(rect, _start, _sweep * (value.clamp(0, 100) / 100), false, p..color = color);
    if (!ticks) return;
    final tick = Paint()
      ..color = AppColors.surface
      ..strokeWidth = 3;
    for (final t in const [40.0, 70.0]) {
      final a = _start + _sweep * t / 100;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * (r - stroke / 2 - 1), c + dir * (r + stroke / 2 + 1), tick);
      final tp = TextPainter(
        text: TextSpan(text: t.toStringAsFixed(0), style: const TextStyle(color: AppColors.muted, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c + dir * (r - 24) - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value || old.color != color;
}

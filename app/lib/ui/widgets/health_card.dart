import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/engine.dart';
import 'common.dart';

class HealthCard extends StatelessWidget {
  const HealthCard({super.key, required this.score, required this.zone});

  final double score;
  final Zone zone;

  @override
  Widget build(BuildContext context) {
    final color = zoneColor(zone);
    final copy = statusCopy[zone]!;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Column(
        children: [
          const Eyebrow('AI Cycle Health Index'),
          const SizedBox(height: 12),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: score),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => SizedBox(
              width: 210,
              height: 210,
              child: CustomPaint(
                painter: _GaugePainter(value: v, color: color),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          v.toStringAsFixed(0),
                          style: const TextStyle(fontSize: 58, fontWeight: FontWeight.w700, height: 1, fontFeatures: tabular),
                        ),
                        const SizedBox(height: 4),
                        const Text('/ 100', style: TextStyle(color: AppColors.muted, fontSize: 12, letterSpacing: 1)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            zoneLabel(zone),
            textAlign: TextAlign.center,
            style: TextStyle(color: color, fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(copy.$1, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14.5, height: 1.5)),
          const SizedBox(height: 6),
          Text(copy.$2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.45)),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.value, required this.color});

  final double value;
  final Color color;

  static const _start = 150 * math.pi / 180;
  static const _sweep = 240 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 15.0;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: (size.width - stroke) / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep, false, base..color = AppColors.raised);
    if (value > 0) canvas.drawArc(rect, _start, _sweep * (value / 100), false, base..color = color);
    final tick = Paint()
      ..color = AppColors.surface
      ..strokeWidth = 3;
    final c = rect.center, r = rect.width / 2;
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

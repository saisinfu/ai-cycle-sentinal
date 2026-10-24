import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/engine.dart';
import 'common.dart';

/// Bridge from one reading to another: start dot, one floating bar per signal, end dot.
class Waterfall extends StatelessWidget {
  const Waterfall({super.key, required this.a, this.showSources = false});

  final Attribution a;
  final bool showSources;

  @override
  Widget build(BuildContext context) {
    final rows = <_Row>[_Row.total(thDate(a.from.reading.date), a.from.index)];
    var run = a.from.index;
    for (final c in a.contributions) {
      rows.add(_Row.change(c.sub.spec.short, run, c.delta));
      run += c.delta;
    }
    rows.add(_Row.total(thDate(a.to.reading.date), a.to.index));
    final values = rows.expand((r) => [r.start, r.end]);
    final mn = values.reduce(math.min), mx = values.reduce(math.max);
    final pad = math.max(0.5, (mx - mn) * 0.15);
    final lo = mn - pad, hi = mx + pad;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(TextSpan(children: [
          TextSpan(
            text: '${a.from.index.toStringAsFixed(1)} → ${a.to.index.toStringAsFixed(1)}  ',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFeatures: tabular),
          ),
          TextSpan(text: '(${signed(a.change)} แต้ม)', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
        ])),
        const SizedBox(height: 10),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    r.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: r.delta == null ? FontWeight.w700 : FontWeight.w400,
                      color: r.delta == null ? AppColors.text : AppColors.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 6,
                  child: CustomPaint(
                    size: const Size(double.infinity, 18),
                    painter: _BarPainter(row: r, lo: lo, hi: hi, guides: (a.from.index, a.to.index)),
                  ),
                ),
                SizedBox(
                  width: 54,
                  child: Text(
                    r.delta == null ? r.end.toStringAsFixed(1) : signed(r.delta!, 2),
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12.5, fontWeight: r.delta == null ? FontWeight.w700 : FontWeight.w500, fontFeatures: tabular),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        const Text('แท่งเขียวดันคะแนนขึ้น แท่งแดงดึงคะแนนลง (หน่วยเป็นแต้มของดัชนี)',
            style: TextStyle(color: AppColors.muted, fontSize: 12)),
      ],
    );
  }
}

class _Row {
  _Row.total(this.label, double v)
      : start = v,
        end = v,
        delta = null;
  _Row.change(this.label, this.start, double d)
      : delta = d,
        end = start + d;

  final String label;
  final double start;
  final double end;
  final double? delta;
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.row, required this.lo, required this.hi, required this.guides});

  final _Row row;
  final double lo;
  final double hi;
  final (double, double) guides;

  @override
  void paint(Canvas canvas, Size size) {
    double x(double v) => (v - lo) / (hi - lo) * size.width;
    final mid = size.height / 2;
    final guide = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    for (final g in [guides.$1, guides.$2]) {
      canvas.drawLine(Offset(x(g), 0), Offset(x(g), size.height), guide);
    }
    final d = row.delta;
    if (d == null) {
      canvas.drawCircle(Offset(x(row.end), mid), 6.5, Paint()..color = AppColors.surface);
      canvas.drawCircle(Offset(x(row.end), mid), 4.5, Paint()..color = AppColors.text);
      return;
    }
    final left = x(math.min(row.start, row.end));
    final width = math.max(2.0, (x(row.end) - x(row.start)).abs());
    final color = d > 0 ? AppColors.green : (d < 0 ? AppColors.red : AppColors.muted);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left, mid - 6, width, 12), const Radius.circular(4)), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.row != row || old.lo != lo || old.hi != hi;
}

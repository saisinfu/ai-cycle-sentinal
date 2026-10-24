import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/engine.dart';
import '../../state/providers.dart';
import 'common.dart';

/// "Why the score changed" — a horizontal waterfall from the earlier reading
/// to the latest one, one floating bar per signal.
class AttributionCard extends ConsumerWidget {
  const AttributionCard({super.key, required this.vm});

  final DashboardVM vm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = ref.watch(attributionDaysProvider);
    final a = vm.attribution[days];
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Eyebrow('ทำไมคะแนนถึงเปลี่ยน')),
              for (final d in const [7, 30]) ...[
                const SizedBox(width: 6),
                ToggleChip(
                  label: '$d วัน',
                  selected: d == days,
                  onTap: () => ref.read(attributionDaysProvider.notifier).state = d,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (a == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  'ต้องมีข้อมูลย้อนหลังอย่างน้อย $days วันจึงจะเทียบได้\nส่วนนี้จะแสดงเองเมื่อข้อมูลครบ',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, fontSize: 13.5),
                ),
              ),
            )
          else
            _Waterfall(a: a, live: vm.live, days: days),
        ],
      ),
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

class _Waterfall extends StatelessWidget {
  const _Waterfall({required this.a, required this.live, required this.days});

  final Attribution a;
  final bool live;
  final int days;

  @override
  Widget build(BuildContext context) {
    final rows = <_Row>[_Row.total(live ? thDate(a.fromDate) : '$days วันก่อน', a.fromScore)];
    var run = a.fromScore;
    for (final c in a.contributions) {
      rows.add(_Row.change(c.spec.short, run, c.delta));
      run += c.delta;
    }
    rows.add(_Row.total('ล่าสุด', a.toScore));
    final values = rows.expand((r) => [r.start, r.end]);
    final mn = values.reduce(math.min), mx = values.reduce(math.max);
    final pad = math.max(0.5, (mx - mn) * 0.15);
    final lo = mn - pad, hi = mx + pad;
    final top = a.contributions.reduce((p, c) => c.delta.abs() > p.delta.abs() ? c : p);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(TextSpan(children: [
          TextSpan(
            text: '${a.fromScore.toStringAsFixed(1)} → ${a.toScore.toStringAsFixed(1)}  ',
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
                    painter: _BarPainter(row: r, lo: lo, hi: hi, guides: (a.fromScore, a.toScore)),
                  ),
                ),
                SizedBox(
                  width: 54,
                  child: Text(
                    r.delta == null ? r.end.toStringAsFixed(1) : signed(r.delta!, 2),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: r.delta == null ? FontWeight.w700 : FontWeight.w500,
                      fontFeatures: tabular,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'ปัจจัยที่ขยับคะแนนมากที่สุด: ${top.spec.th} (${signed(top.delta, 2)} แต้ม) แท่งเขียวดันคะแนนขึ้น แท่งแดงดึงคะแนนลง',
          style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }
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
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(left, mid - 6, width, 12), const Radius.circular(4)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.row != row || old.lo != lo || old.hi != hi;
}

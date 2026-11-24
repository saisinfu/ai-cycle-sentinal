import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/config.dart';
import '../../data/flex.dart';
import '../../data/models.dart';
import 'common.dart';

/// Distance from the 52-week high, worded from the plan's side (a deeper fall = buy more),
/// in neutral/buy colours so it never reads as a red "danger" signal.
(String, Color) pressureLabel(double? dd) {
  if (dd == null) return ('ไม่มีข้อมูล', AppColors.muted);
  if (dd > -5) return ('ใกล้จุดสูงสุด', AppColors.muted);
  if (dd > -10) return ('ย่อเล็กน้อย', AppColors.text);
  if (dd > -20) return ('ปรับฐาน · ซื้อเพิ่ม', AppColors.buy);
  return ('ย่อลึก · ซื้อเพิ่ม', AppColors.buy);
}

(String, Color) vixLabel(double v) {
  if (v < 15) return ('ตลาดสงบ', AppColors.muted);
  if (v < 20) return ('ปกติ', AppColors.text);
  if (v < 30) return ('ตลาดกังวล', AppColors.yellow);
  return ('ตลาดกลัวมาก', AppColors.yellow);
}

String pct(double? v, [int d = 1]) => v == null ? '–' : '${v >= 0 ? '+' : ''}${v.toStringAsFixed(d)}%';

/// Red/green only ever mean price direction.
Color pctColor(double? v) => v == null || v.abs() < 0.05 ? AppColors.muted : (v > 0 ? AppColors.green : AppColors.red);

double? sectorDrawdown(SectorConfig cfg, MarketData m) {
  final dds = [for (final s in cfg.stocks) if (m.quotes[s.ticker]?.drawdownPct case final double d) d];
  return dds.isEmpty ? null : dds.reduce((a, b) => a + b) / dds.length;
}

/// Overview card: fear gauge and main indexes; expands to rates, oil, baht and sectors.
class MarketPulseCard extends StatefulWidget {
  const MarketPulseCard({super.key, required this.market, required this.sectors, this.onSector});

  final MarketData market;
  final List<SectorConfig> sectors;
  final ValueChanged<String>? onSector;

  @override
  State<MarketPulseCard> createState() => _MarketPulseCardState();
}

class _MarketPulseCardState extends State<MarketPulseCard> {
  bool _open = false;

  Widget _row(String label, Quote x, String value, {bool showDd = true}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFeatures: tabular, color: x.stale ? AppColors.muted : AppColors.text)),
            SizedBox(
              width: 64,
              child: Text(pct(x.change1d), textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: pctColor(x.change1d), fontFeatures: tabular)),
            ),
            SizedBox(
              width: 70,
              child: Text(!showDd || x.drawdownPct == null ? '' : '${x.drawdownPct!.toStringAsFixed(0)}% จากยอด',
                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: AppColors.muted, fontFeatures: tabular)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final q = widget.market.quotes;
    final vix = q['^VIX'];
    final asOf = q['SPY']?.asOf;
    final tnx = q['^TNX'];
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Eyebrow('ภาวะตลาด')),
            if (asOf != null) Text('ราคาปิด ${thDate(asOf)}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ]),
          const SizedBox(height: 8),
          if (vix != null) ...[
            Row(children: [
              const Expanded(child: Text('ดัชนีความกลัว (VIX)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
              Text(vix.price.toStringAsFixed(1), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFeatures: tabular)),
              const SizedBox(width: 8),
              NeutralPill(label: vixLabel(vix.price).$1, color: vixLabel(vix.price).$2),
            ]),
            const Divider(height: 18),
          ],
          if (q['SPY'] case final x?) _row('S&P 500 (SPY)', x, money(x.price, x.currency)),
          if (q['QQQ'] case final x?) _row('NASDAQ 100 (QQQ)', x, money(x.price, x.currency)),
          if (q['GLD'] case final x?) _row('ทองคำ (GLD)', x, money(x.price, x.currency)),
          if (_open) ...[
            if (tnx != null) _row('ดอกเบี้ยพันธบัตรสหรัฐ 10 ปี', tnx, '${(tnx.price > 20 ? tnx.price / 10 : tnx.price).toStringAsFixed(2)}%', showDd: false),
            if (q['CL=F'] case final x?) _row('น้ำมันดิบ WTI', x, '\$${x.price.toStringAsFixed(1)}'),
            if (q['THB=X'] case final x?) _row('เงินบาทต่อดอลลาร์', x, x.price.toStringAsFixed(2), showDd: false),
            if (widget.sectors.isNotEmpty) ...[
              const Divider(height: 18),
              const Text('ราคาหุ้นแต่ละหมวด (เฉลี่ยห่างจากจุดสูงสุด 52 สัปดาห์)', style: TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.45)),
              const SizedBox(height: 4),
              for (final s in widget.sectors)
                InkWell(
                  onTap: widget.onSector == null ? null : () => widget.onSector!(s.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Icon(sectorIcon(s.icon), size: 16, color: AppColors.muted),
                      const SizedBox(width: 8),
                      Expanded(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14))),
                      () {
                        final dd = sectorDrawdown(s, widget.market);
                        final (l, c) = pressureLabel(dd);
                        return Text('${dd == null ? '–' : '${dd.toStringAsFixed(0)}%'} · $l',
                            style: TextStyle(fontSize: 13, color: c, fontWeight: FontWeight.w600, fontFeatures: tabular));
                      }(),
                    ]),
                  ),
                ),
            ],
          ],
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                Text(_open ? 'ย่อ' : 'ดูดอกเบี้ย น้ำมัน ค่าเงิน และแต่ละหมวด', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: AppColors.muted),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// 52-week range: low … high, with the 200-day average (tick) and today (dot).
class RangeBar extends StatelessWidget {
  const RangeBar({super.key, required this.low, required this.high, required this.price, this.ma200});

  final double low;
  final double high;
  final double price;
  final double? ma200;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 14,
      child: CustomPaint(painter: _RangePainter(low, high, price, ma200), size: Size.infinite),
    );
  }
}

class _RangePainter extends CustomPainter {
  _RangePainter(this.low, this.high, this.price, this.ma200);

  final double low, high, price;
  final double? ma200;

  @override
  void paint(Canvas canvas, Size size) {
    if (high <= low) return;
    double x(double v) => ((v - low) / (high - low)).clamp(0.0, 1.0) * size.width;
    final y = size.height / 2;
    final track = Paint()
      ..color = AppColors.line
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), track);
    canvas.drawLine(Offset(0, y), Offset(x(price), y), track..color = AppColors.raised);
    if (ma200 != null) {
      canvas.drawLine(Offset(x(ma200!), y - 6), Offset(x(ma200!), y + 6), Paint()
        ..color = AppColors.muted
        ..strokeWidth = 2);
    }
    canvas.drawCircle(Offset(x(price), y), 5, Paint()..color = AppColors.text);
  }

  @override
  bool shouldRepaint(_RangePainter old) => old.price != price || old.low != low || old.high != high || old.ma200 != ma200;
}

/// Sector page: each stock's price, daily move, place in its 52-week range, and the
/// flexible-budget multiplier that follows from it.
class StockPriceCard extends StatelessWidget {
  const StockPriceCard({super.key, required this.cfg, required this.market, required this.mode});

  final SectorConfig cfg;
  final MarketData market;
  final FlexMode mode;

  @override
  Widget build(BuildContext context) {
    final dd = sectorDrawdown(cfg, market);
    final (label, color) = pressureLabel(dd);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Eyebrow('ราคาหุ้นตอนนี้')),
            NeutralPill(label: label, color: color),
          ]),
          const SizedBox(height: 6),
          for (final s in cfg.stocks)
            () {
              final q = market.quotes[s.ticker];
              final m = flexMultiplier(mode, q?.drawdownPct, isFund: s.isFund);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(s.ticker, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(s.isFund ? 'กองทุน' : 'หุ้นรายตัว',
                            style: const TextStyle(fontSize: 12, color: AppColors.muted), overflow: TextOverflow.ellipsis),
                      ),
                      Text(q == null ? '–' : '${money(q.price, q.currency)}${q.stale ? ' (ราคาเก่า)' : ''}',
                          style: TextStyle(fontSize: 14, fontFeatures: tabular, color: q?.stale ?? false ? AppColors.muted : AppColors.text)),
                      SizedBox(
                        width: 62,
                        child: Text(pct(q?.change1d), textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: pctColor(q?.change1d), fontFeatures: tabular)),
                      ),
                    ]),
                    if (q != null && q.high52w != null && q.low52w != null) ...[
                      const SizedBox(height: 6),
                      RangeBar(low: q.low52w!, high: q.high52w!, price: q.price, ma200: q.ma200),
                      const SizedBox(height: 3),
                      Row(children: [
                        Text('ต่ำสุด ${q.low52w!.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontFeatures: tabular)),
                        const Spacer(),
                        Text('ห่างจุดสูงสุด ${q.drawdownPct?.toStringAsFixed(0) ?? '–'}%',
                            style: const TextStyle(fontSize: 12, color: AppColors.text, fontFeatures: tabular)),
                        const Spacer(),
                        Text('สูงสุด ${q.high52w!.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontFeatures: tabular)),
                      ]),
                    ] else if (q?.drawdownPct != null)
                      Text('ห่างจุดสูงสุด 52 สัปดาห์ ${q!.drawdownPct!.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
                    const SizedBox(height: 4),
                    Text(
                      mode == FlexMode.off
                          ? 'งบคงที่: ลงตามงบฐาน'
                          : 'งบยืดหยุ่นเดือนนี้: ×${m.toStringAsFixed(1)}${!s.isFund && m >= singleStockMaxMultiplier ? ' (หุ้นรายตัวสูงสุด ×1.5)' : ''}',
                      style: TextStyle(fontSize: 12.5, color: m > 1 ? AppColors.buy : AppColors.muted, fontWeight: m > 1 ? FontWeight.w600 : FontWeight.w400),
                    ),
                  ],
                ),
              );
            }(),
          const SizedBox(height: 2),
          const Text('แถบ = ช่วงราคา 52 สัปดาห์ · จุด = ราคาวันนี้ · ขีด = เส้นเฉลี่ย 200 วัน',
              style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.4)),
          if (market.quotes[cfg.stocks.firstOrNull?.ticker ?? '']?.asOf case final String d)
            Text('ราคาปิด ${thDate(d)} · Yahoo Finance', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
      ),
    );
  }
}

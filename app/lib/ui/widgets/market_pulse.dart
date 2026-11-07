import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/config.dart';
import '../../data/flex.dart';
import '../../data/models.dart';
import 'common.dart';

/// How stretched or beaten-down a price is, from its distance to the 52-week high.
(String, Color) pressureLabel(double? dd) {
  if (dd == null) return ('ไม่มีข้อมูล', AppColors.muted);
  if (dd > -5) return ('ใกล้จุดสูงสุด', AppColors.green);
  if (dd > -10) return ('ย่อเล็กน้อย', AppColors.text);
  if (dd > -20) return ('ปรับฐาน', AppColors.yellow);
  return ('ขาลงแรง', AppColors.red);
}

(String, Color) vixLabel(double v) {
  if (v < 15) return ('ตลาดสงบ', AppColors.green);
  if (v < 20) return ('ปกติ', AppColors.text);
  if (v < 30) return ('ตลาดกังวล', AppColors.yellow);
  return ('ตลาดกลัวมาก', AppColors.red);
}

String pct(double? v, [int d = 1]) => v == null ? '–' : '${v >= 0 ? '+' : ''}${v.toStringAsFixed(d)}%';

Color pctColor(double? v) => v == null || v.abs() < 0.05 ? AppColors.muted : (v > 0 ? AppColors.green : AppColors.red);

double? sectorDrawdown(SectorConfig cfg, MarketData m) {
  final dds = [for (final s in cfg.stocks) if (m.quotes[s.ticker]?.drawdownPct case final double d) d];
  return dds.isEmpty ? null : dds.reduce((a, b) => a + b) / dds.length;
}

/// Overview card: fear gauge, indexes, rates, oil, gold and each followed sector's price pressure.
class MarketPulseCard extends StatelessWidget {
  const MarketPulseCard({super.key, required this.market, required this.sectors, this.onSector});

  final MarketData market;
  final List<SectorConfig> sectors;
  final ValueChanged<String>? onSector;

  @override
  Widget build(BuildContext context) {
    final q = market.quotes;
    final vix = q['^VIX'];
    final rows = <(String, Quote?, String Function(Quote))>[
      ('S&P 500 (SPY)', q['SPY'], (x) => money(x.price, x.currency)),
      ('NASDAQ 100 (QQQ)', q['QQQ'], (x) => money(x.price, x.currency)),
      ('ทองคำ (GLD)', q['GLD'], (x) => money(x.price, x.currency)),
      ('ดอกเบี้ยพันธบัตรสหรัฐ 10 ปี', q['^TNX'], (x) => '${(x.price > 20 ? x.price / 10 : x.price).toStringAsFixed(2)}%'),
      ('น้ำมันดิบ WTI', q['CL=F'], (x) => '\$${x.price.toStringAsFixed(1)}'),
    ];
    final asOf = q['SPY']?.asOf;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Eyebrow('ภาวะตลาดตอนนี้')),
              if (asOf != null) Text('ราคาปิด ${thDate(asOf)}', style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
            ],
          ),
          const SizedBox(height: 10),
          if (vix != null) ...[
            Row(
              children: [
                const Expanded(child: Text('ดัชนีความกลัว (VIX)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                Text(vix.price.toStringAsFixed(1), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFeatures: tabular)),
                const SizedBox(width: 8),
                StatusPill(label: vixLabel(vix.price).$1, color: vixLabel(vix.price).$2),
              ],
            ),
            const SizedBox(height: 2),
            const Text('ต่ำกว่า 20 = ปกติ · 20–30 = กังวล · เกิน 30 = กลัวมาก (มักเป็นช่วงที่ของถูก)',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted)),
            const Divider(height: 18),
          ],
          for (final (label, x, fmt) in rows)
            if (x != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5))),
                    Text(fmt(x), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, fontFeatures: tabular)),
                    SizedBox(
                      width: 62,
                      child: Text(pct(x.change1d), textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 12.5, color: pctColor(x.change1d), fontFeatures: tabular)),
                    ),
                    SizedBox(
                      width: 66,
                      child: Text(x.drawdownPct == null || label.contains('ดอกเบี้ย') ? '' : '${x.drawdownPct!.toStringAsFixed(0)}% จากยอด',
                          textAlign: TextAlign.right, style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontFeatures: tabular)),
                    ),
                  ],
                ),
              ),
          if (sectors.isNotEmpty) ...[
            const Divider(height: 18),
            const Text('ราคาหุ้นแต่ละหมวด (เฉลี่ยห่างจากจุดสูงสุด 52 สัปดาห์)', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
            const SizedBox(height: 6),
            for (final s in sectors)
              InkWell(
                onTap: onSector == null ? null : () => onSector!(s.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Icon(sectorIcon(s.icon), size: 16, color: AppColors.muted),
                      const SizedBox(width: 8),
                      Expanded(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5))),
                      () {
                        final dd = sectorDrawdown(s, market);
                        final (l, c) = pressureLabel(dd);
                        return Row(children: [
                          Text(dd == null ? '–' : '${dd.toStringAsFixed(0)}%',
                              style: TextStyle(fontSize: 13, color: c, fontWeight: FontWeight.w600, fontFeatures: tabular)),
                          const SizedBox(width: 8),
                          SizedBox(width: 84, child: StatusPill(label: l, color: c)),
                        ]);
                      }(),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 6),
          const Text('คะแนนหมวดวัดพื้นฐานธุรกิจ ส่วนการ์ดนี้วัดราคาจริง ใช้กำหนดว่าเดือนนี้ควรลงมากหรือน้อย',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.4)),
        ],
      ),
    );
  }
}

/// Sector page: each stock's price, daily move, distance from high and 200-day line,
/// and the flexible-budget multiplier that follows from it.
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
          Row(
            children: [
              const Expanded(child: Eyebrow('ราคาหุ้นตอนนี้')),
              StatusPill(label: label, color: color),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Expanded(flex: 3, child: Text('หุ้น', style: TextStyle(fontSize: 11.5, color: AppColors.muted))),
              Expanded(flex: 3, child: Text('ราคา / วันนี้', textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, color: AppColors.muted))),
              Expanded(flex: 3, child: Text('จากจุดสูงสุด', textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, color: AppColors.muted))),
              Expanded(flex: 2, child: Text('ลงทุน', textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, color: AppColors.muted))),
            ],
          ),
          const Divider(height: 12),
          for (final s in cfg.stocks)
            () {
              final q = market.quotes[s.ticker];
              final m = flexMultiplier(mode, q?.drawdownPct);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.ticker, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        if (q?.vsMa200 != null)
                          Text('${q!.vsMa200! >= 0 ? 'เหนือ' : 'ใต้'}เส้น 200 วัน ${q.vsMa200!.abs().toStringAsFixed(0)}%',
                              style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                      ]),
                    ),
                    Expanded(
                      flex: 3,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(q == null ? '–' : money(q.price, q.currency), style: const TextStyle(fontSize: 13.5, fontFeatures: tabular)),
                        Text(pct(q?.change1d), style: TextStyle(fontSize: 12, color: pctColor(q?.change1d), fontFeatures: tabular)),
                      ]),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(q?.drawdownPct == null ? '–' : '${q!.drawdownPct!.toStringAsFixed(1)}%',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 13.5, color: pressureLabel(q?.drawdownPct).$2, fontFeatures: tabular)),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(mode == FlexMode.off ? '×1' : '×${m.toStringAsFixed(m == m.roundToDouble() ? 0 : 1)}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: m > 1 ? AppColors.green : (m < 1 ? AppColors.muted : AppColors.text),
                              fontFeatures: tabular)),
                    ),
                  ],
                ),
              );
            }(),
          const SizedBox(height: 4),
          Text(
            mode == FlexMode.off
                ? 'ตั้งงบแบบคงที่อยู่ ลงเท่ากันทุกเดือน เปลี่ยนได้ในหน้าตั้งค่า'
                : '"ลงทุน" = ตัวคูณงบเดือนนี้ตามแผนงบยืดหยุ่น (${flexModeName(mode)}) ยิ่งราคาห่างจุดสูงสุดมาก ยิ่งลงมาก โดยใช้เงินสำรอง',
            style: const TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.4),
          ),
          if (market.quotes[cfg.stocks.firstOrNull?.ticker ?? '']?.asOf case final String d)
            Text('ราคาปิด ${thDate(d)} · Yahoo Finance', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        ],
      ),
    );
  }
}

/// Number and date formatting (no intl dependency).
library;

DateTime parseDate(String d) =>
    DateTime.utc(int.parse(d.substring(0, 4)), int.parse(d.substring(5, 7)), int.parse(d.substring(8, 10)));

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const _monthsShort = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
const _monthsLong = [
  'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
  'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
];

/// "16 ต.ค."
String thDate(String iso) {
  final d = parseDate(iso);
  return '${d.day} ${_monthsShort[d.month - 1]}';
}

/// "16 ตุลาคม 2569"
String thDateLong(String iso) {
  final d = parseDate(iso);
  return '${d.day} ${_monthsLong[d.month - 1]} ${d.year + 543}';
}

String thMonthYear(DateTime d) => '${_monthsLong[d.month - 1]} ${d.year + 543}';

/// "+1.6" / "−2.0" / "0.0" with a true minus sign.
String signed(double v, [int digits = 1]) {
  final s = v.abs().toStringAsFixed(digits);
  if (double.parse(s) == 0) return s;
  return v > 0 ? '+$s' : '−$s';
}

String fixed(double v, int digits) => v < 0 ? '−${v.abs().toStringAsFixed(digits)}' : v.toStringAsFixed(digits);

/// 12345.6 -> "12,346"
String baht(double v) {
  final n = v.round();
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return n < 0 ? '−$buf' : buf.toString();
}

String money(double v, String currency) =>
    currency == 'THB' ? '฿${v.toStringAsFixed(2)}' : '\$${v.toStringAsFixed(2)}';

final _tpl = RegExp(r'\{(\w+)(?::(\+?)(\d))?\}');

/// Fills "{field:2}" (2 decimals) and "{field:+1}" (signed, 1 decimal) from [values].
String fillTemplate(String template, Map<String, double> values) {
  return template.replaceAllMapped(_tpl, (m) {
    final v = values[m.group(1)!];
    if (v == null) return '–';
    final digits = int.tryParse(m.group(3) ?? '') ?? 1;
    return m.group(2) == '+' ? signed(v, digits) : fixed(v, digits);
  });
}

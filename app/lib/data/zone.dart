/// Cycle status bands with a ±3 dead-band (hysteresis).
library;

enum Zone { expansion, earlyWarning, digestion }

const double expansionThreshold = 70;
const double digestionThreshold = 40;
const double hysteresisBand = 3;

Zone zoneFromCode(String code) => switch (code) {
      'X' => Zone.expansion,
      'D' => Zone.digestion,
      _ => Zone.earlyWarning,
    };

Zone classify(double x) => x >= expansionThreshold
    ? Zone.expansion
    : x >= digestionThreshold
        ? Zone.earlyWarning
        : Zone.digestion;

Zone classifyWithHysteresis(double x, Zone? prev) {
  if (prev == null) return classify(x);
  final upper = prev == Zone.expansion ? expansionThreshold - hysteresisBand : expansionThreshold + hysteresisBand;
  final lower = prev == Zone.digestion ? digestionThreshold + hysteresisBand : digestionThreshold - hysteresisBand;
  if (x >= upper) return Zone.expansion;
  if (x < lower) return Zone.digestion;
  return Zone.earlyWarning;
}

/// The threshold that had to be crossed to move from [from] to [to], as text.
String crossingText(Zone from, Zone to) {
  final up = expansionThreshold + hysteresisBand, downX = expansionThreshold - hysteresisBand;
  final downD = digestionThreshold - hysteresisBand, upD = digestionThreshold + hysteresisBand;
  return switch ((from, to)) {
    (_, Zone.expansion) => 'ผ่านเกณฑ์ ${up.toStringAsFixed(0)} ขึ้นไป (70 + ช่วงกันชน 3)',
    (_, Zone.digestion) => 'ต่ำกว่าเกณฑ์ ${downD.toStringAsFixed(0)} (40 − ช่วงกันชน 3)',
    (Zone.expansion, Zone.earlyWarning) => 'ต่ำกว่าเกณฑ์ ${downX.toStringAsFixed(0)} (70 − ช่วงกันชน 3)',
    _ => 'กลับขึ้นมาถึง ${upD.toStringAsFixed(0)} (40 + ช่วงกันชน 3)',
  };
}

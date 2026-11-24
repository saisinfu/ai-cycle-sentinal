import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/engine.dart';
import '../data/flex.dart';
import '../data/holdings.dart';

/// Everything the user can change in the app. Stored on the phone only.
class UserSettings {
  const UserSettings({
    this.salary = 30000.0,
    this.dcaPct = 15.0,
    this.buckets = const {'main': 40.0, 'tech': 40.0, 'tax': 20.0},
    this.mainSplit = const {'gold': 25.0, 'sp500': 25.0, 'nasdaq': 25.0, 'kkp': 25.0},
    this.mainSplitSet = false,
    this.sectorWeights = const {'ai': 100.0, 'finance': 0.0},
    this.followed = const {'ai': true, 'finance': true},
    this.zoneMethod = ZoneMethod.ma200,
    this.bonusMonths = 7.0,
    this.lifeInsurance = 0.0,
    this.healthInsurance = 0.0,
    this.providentFund = 0.0,
    this.otherDeductions = 0.0,
    this.esgBought = 0.0,
    this.rmfBought = 0.0,
    this.targetNet = 300000.0,
    this.flexMode = FlexMode.dipOnly,
    this.reserve = 0.0,
    this.reserveCapMonths = 6.0,
    this.lastRecordedMonth = '',
    this.recordedReserveBefore = 0.0,
    this.emergencyTarget = 0.0,
    this.emergencyHave = 0.0,
    this.stockCapPct = 15.0,
    this.rebalance = true,
    this.holdings = const [],
    this.checklistMonth = '',
    this.checklistDone = const [],
    this.alertsSeenAt = '',
    this.calmPush = true,
    this.portfolioCurrency = 'THB',
  });

  /// Emergency fund the owner wants before any reserve money is used (0 = not set).
  final double emergencyTarget;
  final double emergencyHave;

  /// Max % of the month's investable budget for one company.
  final double stockCapPct;

  /// Tilt the monthly base toward lines below their target weight (needs holdings).
  final bool rebalance;
  final List<Holding> holdings;

  /// Ticked buy-list lines for [checklistMonth].
  final String checklistMonth;
  final List<String> checklistDone;

  /// ISO time the alerts tab was last opened (for "new" markers and the badge).
  final String alertsSeenAt;

  /// Show only actionable alerts in the badge.
  final bool calmPush;

  /// Currency for portfolio totals: 'THB' or 'USD'.
  final String portfolioCurrency;

  bool get emergencyOk => emergencyTarget <= 0 || emergencyHave >= emergencyTarget;
  bool get emergencySet => emergencyTarget > 0;
  List<String> get doneThisMonth => checklistMonth == monthKey(DateTime.now()) ? checklistDone : const [];

  /// Reserve before the confirmation of [lastRecordedMonth] (to show and undo that month's plan).
  final double recordedReserveBefore;

  static String monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  bool get recordedThisMonth => lastRecordedMonth == monthKey(DateTime.now());

  /// Reserve the current month's plan starts from.
  double get planReserve => recordedThisMonth ? recordedReserveBefore : reserve;

  final FlexMode flexMode;

  /// Cash reserve for buying dips (baht), kept by the user.
  final double reserve;

  /// Reserve above this many months of base budget is invested right away (0 = no cap).
  final double reserveCapMonths;

  /// 'YYYY-MM' of the last month the user confirmed the plan.
  final String lastRecordedMonth;

  final double salary;
  final double dcaPct;
  final Map<String, double> buckets;
  final Map<String, double> mainSplit;

  /// False until the user saves the main-port split once (shown as a hint).
  final bool mainSplitSet;
  final Map<String, double> sectorWeights;
  final Map<String, bool> followed;
  final ZoneMethod zoneMethod;
  final double bonusMonths;
  final double lifeInsurance;
  final double healthInsurance;
  final double providentFund;
  final double otherDeductions;
  final double esgBought;
  final double rmfBought;
  final double targetNet;

  bool isFollowed(String id) => followed[id] ?? true;

  UserSettings copyWith({
    double? salary,
    double? dcaPct,
    Map<String, double>? buckets,
    Map<String, double>? mainSplit,
    bool? mainSplitSet,
    Map<String, double>? sectorWeights,
    Map<String, bool>? followed,
    ZoneMethod? zoneMethod,
    double? bonusMonths,
    double? lifeInsurance,
    double? healthInsurance,
    double? providentFund,
    double? otherDeductions,
    double? esgBought,
    double? rmfBought,
    double? targetNet,
    FlexMode? flexMode,
    double? reserve,
    double? reserveCapMonths,
    String? lastRecordedMonth,
    double? recordedReserveBefore,
    double? emergencyTarget,
    double? emergencyHave,
    double? stockCapPct,
    bool? rebalance,
    List<Holding>? holdings,
    String? checklistMonth,
    List<String>? checklistDone,
    String? alertsSeenAt,
    bool? calmPush,
    String? portfolioCurrency,
  }) =>
      UserSettings(
        salary: salary ?? this.salary,
        dcaPct: dcaPct ?? this.dcaPct,
        buckets: buckets ?? this.buckets,
        mainSplit: mainSplit ?? this.mainSplit,
        mainSplitSet: mainSplitSet ?? this.mainSplitSet,
        sectorWeights: sectorWeights ?? this.sectorWeights,
        followed: followed ?? this.followed,
        zoneMethod: zoneMethod ?? this.zoneMethod,
        bonusMonths: bonusMonths ?? this.bonusMonths,
        lifeInsurance: lifeInsurance ?? this.lifeInsurance,
        healthInsurance: healthInsurance ?? this.healthInsurance,
        providentFund: providentFund ?? this.providentFund,
        otherDeductions: otherDeductions ?? this.otherDeductions,
        esgBought: esgBought ?? this.esgBought,
        rmfBought: rmfBought ?? this.rmfBought,
        targetNet: targetNet ?? this.targetNet,
        flexMode: flexMode ?? this.flexMode,
        reserve: reserve ?? this.reserve,
        reserveCapMonths: reserveCapMonths ?? this.reserveCapMonths,
        lastRecordedMonth: lastRecordedMonth ?? this.lastRecordedMonth,
        recordedReserveBefore: recordedReserveBefore ?? this.recordedReserveBefore,
        emergencyTarget: emergencyTarget ?? this.emergencyTarget,
        emergencyHave: emergencyHave ?? this.emergencyHave,
        stockCapPct: stockCapPct ?? this.stockCapPct,
        rebalance: rebalance ?? this.rebalance,
        holdings: holdings ?? this.holdings,
        checklistMonth: checklistMonth ?? this.checklistMonth,
        checklistDone: checklistDone ?? this.checklistDone,
        alertsSeenAt: alertsSeenAt ?? this.alertsSeenAt,
        calmPush: calmPush ?? this.calmPush,
        portfolioCurrency: portfolioCurrency ?? this.portfolioCurrency,
      );

  Map<String, Object> toJson() => {
        'salary': salary,
        'dcaPct': dcaPct,
        'buckets': buckets,
        'mainSplit': mainSplit,
        'mainSplitSet': mainSplitSet,
        'sectorWeights': sectorWeights,
        'followed': followed,
        'zoneMethod': zoneMethodKey(zoneMethod),
        'bonusMonths': bonusMonths,
        'lifeInsurance': lifeInsurance,
        'healthInsurance': healthInsurance,
        'providentFund': providentFund,
        'otherDeductions': otherDeductions,
        'esgBought': esgBought,
        'rmfBought': rmfBought,
        'targetNet': targetNet,
        'flexMode': flexModeKey(flexMode),
        'reserve': reserve,
        'reserveCapMonths': reserveCapMonths,
        'lastRecordedMonth': lastRecordedMonth,
        'recordedReserveBefore': recordedReserveBefore,
        'emergencyTarget': emergencyTarget,
        'emergencyHave': emergencyHave,
        'stockCapPct': stockCapPct,
        'rebalance': rebalance,
        'holdings': [for (final h in holdings) h.toJson()],
        'checklistMonth': checklistMonth,
        'checklistDone': checklistDone,
        'alertsSeenAt': alertsSeenAt,
        'calmPush': calmPush,
        'portfolioCurrency': portfolioCurrency,
        'zoneMethodV2': true,
      };

  static Map<String, double>? _nums(Object? v) {
    if (v is! Map) return null;
    return {for (final e in v.entries) if (e.key is String && e.value is num) e.key as String: (e.value as num).toDouble()};
  }

  static UserSettings fromJson(Map j) {
    const d = UserSettings();
    double n(String k, double fallback) => j[k] is num ? (j[k] as num).toDouble() : fallback;
    final followedRaw = j['followed'];
    return UserSettings(
      salary: n('salary', d.salary),
      dcaPct: n('dcaPct', d.dcaPct),
      buckets: _nums(j['buckets']) ?? d.buckets,
      mainSplit: _nums(j['mainSplit']) ?? d.mainSplit,
      mainSplitSet: j['mainSplitSet'] == true,
      sectorWeights: _nums(j['sectorWeights']) ?? d.sectorWeights,
      followed: followedRaw is Map
          ? {for (final e in followedRaw.entries) if (e.key is String && e.value is bool) e.key as String: e.value as bool}
          : d.followed,
      // v2.4: the old default ("fixed", anchored on today's price) always showed "in zone"; move to the 200-day line once.
      zoneMethod: j['zoneMethodV2'] == true ? zoneMethodFrom(j['zoneMethod'] as String?) : ZoneMethod.ma200,
      bonusMonths: n('bonusMonths', d.bonusMonths),
      lifeInsurance: n('lifeInsurance', d.lifeInsurance),
      healthInsurance: n('healthInsurance', d.healthInsurance),
      providentFund: n('providentFund', d.providentFund),
      otherDeductions: n('otherDeductions', d.otherDeductions),
      esgBought: n('esgBought', d.esgBought),
      rmfBought: n('rmfBought', d.rmfBought),
      targetNet: n('targetNet', d.targetNet),
      flexMode: flexModeFrom(j['flexMode'] as String?),
      reserve: n('reserve', d.reserve),
      reserveCapMonths: n('reserveCapMonths', d.reserveCapMonths),
      lastRecordedMonth: j['lastRecordedMonth'] is String ? j['lastRecordedMonth'] as String : '',
      recordedReserveBefore: n('recordedReserveBefore', d.recordedReserveBefore),
      emergencyTarget: n('emergencyTarget', d.emergencyTarget),
      emergencyHave: n('emergencyHave', d.emergencyHave),
      stockCapPct: n('stockCapPct', d.stockCapPct),
      rebalance: j['rebalance'] is bool ? j['rebalance'] as bool : d.rebalance,
      holdings: j['holdings'] is List ? [for (final h in j['holdings'] as List) if (h is Map) Holding.fromJson(h)] : const [],
      checklistMonth: j['checklistMonth'] is String ? j['checklistMonth'] as String : '',
      checklistDone: j['checklistDone'] is List ? [for (final x in j['checklistDone'] as List) if (x is String) x] : const [],
      alertsSeenAt: j['alertsSeenAt'] is String ? j['alertsSeenAt'] as String : '',
      calmPush: j['calmPush'] is bool ? j['calmPush'] as bool : d.calmPush,
      portfolioCurrency: j['portfolioCurrency'] == 'USD' ? 'USD' : 'THB',
    );
  }
}

class SettingsNotifier extends StateNotifier<UserSettings> {
  SettingsNotifier() : super(const UserSettings()) {
    _load();
  }

  static const _key = 'user_settings_v1';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) state = UserSettings.fromJson(jsonDecode(raw) as Map);
    } catch (_) {}
  }

  Future<void> update(UserSettings Function(UserSettings s) change) async {
    state = change(state);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(state.toJson()));
    } catch (_) {}
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, UserSettings>((ref) => SettingsNotifier());

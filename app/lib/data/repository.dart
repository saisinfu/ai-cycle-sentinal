import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'backtest.dart';
import 'config.dart';
import 'models.dart';

/// Public repository written by the daily Claude task.
const repoBase = 'https://raw.githubusercontent.com/saisinfu/ai-cycle-sentinal/main';

class DataException implements Exception {
  DataException(this.message);

  final String message;

  @override
  String toString() => message;
}

class Loaded<T> {
  const Loaded(this.value, {required this.fromCache});

  final T value;

  /// True when the network failed and the last saved copy is shown.
  final bool fromCache;
}

class Repository {
  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  /// Downloads [path] from the repo; falls back to the last saved copy.
  Future<Loaded<String>> _fetch(String path) async {
    final prefs = await _prefs();
    final key = 'cache:$path';
    try {
      final uri = Uri.parse('$repoBase/$path?t=${DateTime.now().millisecondsSinceEpoch ~/ 60000}');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw DataException('เซิร์ฟเวอร์ตอบกลับ ${res.statusCode}');
      final body = utf8.decode(res.bodyBytes);
      jsonDecode(body); // validate before caching
      try {
        await prefs?.setString(key, body);
      } catch (_) {}
      return Loaded(body, fromCache: false);
    } catch (e) {
      final cached = prefs?.getString(key);
      if (cached != null) return Loaded(cached, fromCache: true);
      if (e is TimeoutException) throw DataException('เชื่อมต่ออินเทอร์เน็ตช้าเกินไป ลองใหม่อีกครั้ง');
      if (e is DataException) rethrow;
      throw DataException('โหลดข้อมูลไม่ได้ ตรวจสอบอินเทอร์เน็ตแล้วลองใหม่');
    }
  }

  Future<AppConfig> loadConfig() async {
    try {
      final r = await _fetch('config/sectors.json');
      final cfg = AppConfig.fromJson(jsonDecode(r.value) as Map);
      if (cfg.sectors.isNotEmpty) return cfg;
    } catch (_) {}
    final bundled = await rootBundle.loadString('assets/sectors.json');
    return AppConfig.fromJson(jsonDecode(bundled) as Map);
  }

  Future<Loaded<List<Reading>>> loadReadings(String path) async {
    final r = await _fetch(path);
    final decoded = jsonDecode(r.value);
    final list = decoded is Map ? decoded['readings'] : decoded;
    if (list is! List) throw DataException('รูปแบบไฟล์ข้อมูลไม่ถูกต้อง');
    final readings = list.map(Reading.tryParse).whereType<Reading>().toList()..sort((a, b) => a.date.compareTo(b.date));
    return Loaded(readings, fromCache: r.fromCache);
  }

  Future<MarketData> loadMarket() async {
    try {
      final r = await _fetch('data/market.json');
      return MarketData.fromJson(jsonDecode(r.value));
    } catch (_) {
      return MarketData.empty;
    }
  }

  /// Null when the file is missing and nothing is cached.
  Future<BacktestSummary?> loadBacktest() async {
    try {
      final r = await _fetch('data/backtest.json');
      final j = jsonDecode(r.value);
      return j is Map ? BacktestSummary.fromJson(j) : null;
    } catch (_) {
      return null;
    }
  }
}

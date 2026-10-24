import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Public data file written by the daily Claude task.
const dataUrl = 'https://raw.githubusercontent.com/saisinfu/ai-cycle-sentinal/main/data/readings.json';

class DataException implements Exception {
  DataException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ReadingsRepository {
  static const _cacheKey = 'readings_json_v1';

  ReadingsResult _parse(String body, {required bool fromCache}) {
    final decoded = jsonDecode(body);
    final list = decoded is Map ? decoded['readings'] : decoded;
    if (list is! List) throw DataException('รูปแบบไฟล์ข้อมูลไม่ถูกต้อง');
    final readings = list.map(Reading.tryParse).whereType<Reading>().toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final updatedAt = decoded is Map && decoded['updated_at'] is String ? decoded['updated_at'] as String : null;
    return ReadingsResult(readings: readings, fromCache: fromCache, updatedAt: updatedAt);
  }

  Future<ReadingsResult> load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      prefs = null;
    }
    try {
      final uri = Uri.parse('$dataUrl?t=${DateTime.now().millisecondsSinceEpoch ~/ 60000}');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw DataException('เซิร์ฟเวอร์ตอบกลับ ${res.statusCode}');
      final body = utf8.decode(res.bodyBytes);
      final result = _parse(body, fromCache: false);
      try {
        await prefs?.setString(_cacheKey, body);
      } catch (_) {}
      return result;
    } catch (e) {
      final cached = prefs?.getString(_cacheKey);
      if (cached != null) {
        try {
          return _parse(cached, fromCache: true);
        } catch (_) {}
      }
      if (e is TimeoutException) throw DataException('เชื่อมต่ออินเทอร์เน็ตช้าเกินไป ลองใหม่อีกครั้ง');
      if (e is DataException) rethrow;
      throw DataException('โหลดข้อมูลไม่ได้ ตรวจสอบอินเทอร์เน็ตแล้วลองใหม่');
    }
  }
}

// ============================================================================
// AEGIS Shield — controllers/classification_cache.dart
// ============================================================================
// Smart Cache สำหรับเก็บผลวิเคราะห์ domain จาก Gemini AI
// ============================================================================

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/classification_result.dart';

/// จัดการ cache ผลวิเคราะห์ domain
class ClassificationCache {
  static const String _prefix = 'aegis_cache_';
  static const int _expiryDays = 7;

  /// ดึงผลวิเคราะห์จาก cache
  static Future<ClassificationResult?> getCachedResult(String domain) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _prefix + _normalizeDomain(domain);
    final jsonStr = prefs.getString(key);

    if (jsonStr == null) return null;

    try {
      final result = ClassificationResult.fromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>,
      );
      if (_isExpired(result.cachedAt)) {
        await prefs.remove(key);
        return null;
      }
      return result;
    } catch (e) {
      await prefs.remove(key);
      return null;
    }
  }

  /// บันทึกผลวิเคราะห์ลง cache
  static Future<void> cacheResult(
    String domain,
    bool isGambling,
    double confidence,
    String reason,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _prefix + _normalizeDomain(domain);
    final result = ClassificationResult(
      isGambling: isGambling,
      confidence: confidence,
      reason: reason,
      cachedAt: DateTime.now(),
    );
    await prefs.setString(key, jsonEncode(result.toJson()));
  }

  /// นับจำนวน domain ที่ cache อยู่
  static Future<int> getCachedCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getKeys().where((k) => k.startsWith(_prefix)).length;
  }

  /// ล้าง cache ทั้งหมด
  static Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  static String _normalizeDomain(String domain) {
    var d = domain.toLowerCase().trim();
    if (d.startsWith('www.')) d = d.substring(4);
    return d;
  }

  static bool _isExpired(DateTime cachedAt) {
    return DateTime.now().difference(cachedAt).inDays >= _expiryDays;
  }
}

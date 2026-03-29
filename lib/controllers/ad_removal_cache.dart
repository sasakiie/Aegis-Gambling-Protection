// ============================================================================
// AEGIS Shield — controllers/ad_removal_cache.dart
// ============================================================================
// ระบบจัดการ Cache สำหรับ CSS Selectors ของเว็บที่มีโฆษณาพนัน โดยใช้ Hive DB
// ============================================================================

import 'package:hive_flutter/hive_flutter.dart';

part 'ad_removal_cache.g.dart';

@HiveType(typeId: 1)
class AdCacheEntry extends HiveObject {
  @HiveField(0)
  final String domain;

  @HiveField(1)
  final List<String> selectors;

  @HiveField(2)
  final bool isGambling;

  @HiveField(3)
  final DateTime cachedAt;

  @HiveField(4)
  int missCount;

  @HiveField(5)
  bool needsReview;

  AdCacheEntry({
    required this.domain,
    required this.selectors,
    required this.isGambling,
    required this.cachedAt,
    this.missCount = 0,
    this.needsReview = false,
  });

  /// เช็คว่า Cache หมดอายุหรือยัง (TTL 7 วันสำหรับเว็บปกติ, 30 วันสำหรับเว็บพนัน)
  bool get isExpired {
    final now = DateTime.now();
    final age = now.difference(cachedAt).inDays;
    final ttl = isGambling ? 30 : 7;
    return age >= ttl;
  }
}

class AdRemovalCache {
  static const String _boxName = 'ad_removal_cache_box';
  static Box<AdCacheEntry>? _box;

  static Future<void> init() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(AdCacheEntryAdapter());
    }
    _box = await Hive.openBox<AdCacheEntry>(_boxName);
  }

  /// ดึงข้อมูล Cache ของ Domain นั้นๆ (รวมเช็ค TTL และ needsReview)
  static AdCacheEntry? getCache(String domain) {
    if (_box == null) return null;
    
    final entry = _box!.get(domain);
    if (entry == null) return null;

    // ถ้าเว็บตั้งใจซ่อนโฆษณาเพื่อหลบหลีกเรา (miss เกิน 3 ครั้ง) ให้ข้ามไปเลย
    if (entry.needsReview) {
      return null;
    }

    // ถ้า Cache หมดอายุแล้ว ลบทิ้งแล้วตีว่า Miss
    if (entry.isExpired) {
      entry.delete();
      return null;
    }

    return entry;
  }

  /// บันทึกหรืออัปเดต Cache ใหม่ (รีเซ็ต missCount และ needsReview)
  static Future<void> saveCache({
    required String domain,
    required List<String> selectors,
    required bool isGambling,
  }) async {
    if (_box == null) return;

    final entry = AdCacheEntry(
      domain: domain,
      selectors: selectors,
      isGambling: isGambling,
      cachedAt: DateTime.now(),
      missCount: 0,
      needsReview: false,
    );

    await _box!.put(domain, entry);
  }

  /// บันทึกว่าลบโฆษณาไม่เจอ (Cache Miss)
  /// กลับค่า true ถ้าให้หยุดเรียก AI (เว็บจงใจซ่อน), ค่า false ถ้าให้ฟอลแบ็คไปเรียก AI
  static Future<bool> reportCacheMiss(String domain) async {
    if (_box == null) return false;

    final entry = _box!.get(domain);
    if (entry == null) return false;

    entry.missCount += 1;
    if (entry.missCount >= 3) {
      entry.needsReview = true;
      entry.save();
      return true; // กลับค่าบอกให้หน้าเว็บหยุดเรียก AI ยืดเยื้อ
    }

    entry.save();
    return false; // ให้ส่งรีเควสต์ไปหา AI ใหม่เผื่อ Layout เปลี่ยน
  }

  /// เรียกเคลียร์ Cache ทั้งหมด (สำหรับ Admin)
  static Future<void> clearAll() async {
    await _box?.clear();
  }
}

// ============================================================================
// AEGIS Shield — controllers/debug_logger.dart
// ============================================================================
// Admin-only Debug Logger — บันทึกทุกกิจกรรมลงไฟล์อย่างละเอียด
//
// ไฟล์ log จะถูกเก็บที่:
//   Android: /data/data/com.aegis.aegis_prog/files/aegis_debug.log
//
// วิธีดู log (สำหรับ admin):
//   adb shell run-as com.aegis.aegis_prog cat files/aegis_debug.log
//   หรือ: adb pull /data/data/com.aegis.aegis_prog/files/aegis_debug.log
//
// Format:
//   [2026-03-25 02:30:15.123] [DETECTION] 🚫 ufabet.com → blocked (pre-filter)
//   [2026-03-25 02:30:16.456] [AI]        🤖 Vision: gambling (95%)
//   [2026-03-25 02:30:17.789] [SYSTEM]    ✅ App started, keywords loaded
// ============================================================================

import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// ระดับ log
enum LogLevel { system, detection, ai, vpn, sanitizer, cache, error }

/// DebugLogger — เก็บ log ลงไฟล์สำหรับ admin เท่านั้น
class DebugLogger {
  static DebugLogger? _instance;
  File? _logFile;
  IOSink? _sink;
  bool _ready = false;

  DebugLogger._();

  static DebugLogger get instance {
    _instance ??= DebugLogger._();
    return _instance!;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Initialize — เรียกครั้งเดียวตอน main()
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/aegis_debug.log');

      // ถ้าไฟล์ใหญ่เกิน 5MB → ลบแล้วเริ่มใหม่
      if (await _logFile!.exists()) {
        final size = await _logFile!.length();
        if (size > 5 * 1024 * 1024) {
          await _logFile!.delete();
        }
      }

      _sink = _logFile!.openWrite(mode: FileMode.append);
      _ready = true;

      // เขียน header เมื่อเริ่ม session ใหม่
      _sink!.writeln('');
      _sink!.writeln('═══════════════════════════════════════════════════════');
      _sink!.writeln('  AEGIS Debug Session — ${DateTime.now()}');
      _sink!.writeln('═══════════════════════════════════════════════════════');
    } catch (e) {
      // ignore: avoid_print
      print('⚠️ DebugLogger init failed: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // log — บันทึก log entry
  // ═══════════════════════════════════════════════════════════════════════════
  void log(LogLevel level, String message) {
    if (!_ready || _sink == null) return;

    final timestamp = _formatTimestamp(DateTime.now());
    final tag = _levelTag(level);
    final line = '[$timestamp] [$tag] $message';

    _sink!.writeln(line);

    // flush ทันทีสำหรับ error เพื่อไม่ให้หลุด
    if (level == LogLevel.error) {
      _sink!.flush();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Shorthand methods
  // ═══════════════════════════════════════════════════════════════════════════
  void system(String msg)    => log(LogLevel.system, msg);
  void detection(String msg) => log(LogLevel.detection, msg);
  void ai(String msg)        => log(LogLevel.ai, msg);
  void vpn(String msg)       => log(LogLevel.vpn, msg);
  void sanitizer(String msg) => log(LogLevel.sanitizer, msg);
  void cache(String msg)     => log(LogLevel.cache, msg);
  void error(String msg)     => log(LogLevel.error, msg);

  // ═══════════════════════════════════════════════════════════════════════════
  // readLog — อ่าน log ทั้งหมด (สำหรับ admin UI ในอนาคต)
  // ═══════════════════════════════════════════════════════════════════════════
  Future<String> readLog() async {
    if (_logFile == null || !await _logFile!.exists()) return '(no log file)';
    await _sink?.flush();
    return _logFile!.readAsString();
  }

  /// ขนาดไฟล์ log (bytes)
  Future<int> logSize() async {
    if (_logFile == null || !await _logFile!.exists()) return 0;
    return _logFile!.length();
  }

  /// path ไฟล์ log
  String? get logPath => _logFile?.path;

  /// ล้าง log
  Future<void> clearLog() async {
    await _sink?.flush();
    await _sink?.close();
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.delete();
    }
    _sink = _logFile!.openWrite(mode: FileMode.append);
    system('🗑️ Log cleared by admin');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // dispose — ปิดไฟล์
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> dispose() async {
    await _sink?.flush();
    await _sink?.close();
    _ready = false;
  }

  // ─── Helpers ───
  String _formatTimestamp(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
        '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}.${dt.millisecond.toString().padLeft(3, '0')}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  String _levelTag(LogLevel level) {
    switch (level) {
      case LogLevel.system:    return 'SYSTEM   ';
      case LogLevel.detection: return 'DETECTION';
      case LogLevel.ai:        return 'AI       ';
      case LogLevel.vpn:       return 'VPN      ';
      case LogLevel.sanitizer: return 'SANITIZER';
      case LogLevel.cache:     return 'CACHE    ';
      case LogLevel.error:     return 'ERROR    ';
    }
  }
}

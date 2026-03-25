// ============================================================================
// AEGIS Shield — models/log_entry.dart
// ============================================================================
// Data model สำหรับ log entry ที่แสดงใน Live Log panel
// ============================================================================

import 'package:flutter/material.dart';

/// ประเภทของ log entry (กำหนดสีที่แสดง)
/// - blocked : สีแดงอ่อน → domain ถูก block โดย VPN
/// - cleaned : สีม่วงอ่อน → banner ถูกลบโดย sanitizer.js
/// - success : สีเขียว → การทำงานสำเร็จ (เช่น VPN started)
/// - error   : สีแดงเข้ม → เกิดข้อผิดพลาด
/// - info    : สีเทา → ข้อมูลทั่วไป
enum LogType { blocked, cleaned, success, error, info }

/// Data model สำหรับ log entry แต่ละรายการ
/// เก็บข้อมูล 3 อย่าง: ข้อความ, ประเภท, เวลา
/// + getter 'color' คืนสีตาม LogType สำหรับใช้ใน UI
class LogEntry {
  final String message;
  final LogType type;
  final DateTime time;

  LogEntry({required this.message, required this.type, required this.time});

  /// คืนสีของ log entry ตามประเภท สำหรับแสดงใน Live Log panel
  Color get color {
    switch (type) {
      case LogType.blocked:
        return const Color(0xFFFF6B6B); // แดงอ่อน
      case LogType.cleaned:
        return const Color(0xFFB388FF); // ม่วงอ่อน
      case LogType.success:
        return const Color(0xFF3FB950); // เขียว
      case LogType.error:
        return const Color(0xFFFF4444); // แดงเข้ม
      case LogType.info:
        return const Color(0xFF8B949E); // เทา
    }
  }
}

// ============================================================================
// AEGIS Shield — controllers/dashboard_controller.dart
// ============================================================================
// ChangeNotifier สำหรับจัดการ state ของ Dashboard
// แก้ช่องโหว่ #1: State Management — ใช้ notifyListeners() แทน setState()
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:async';
import '../models/log_entry.dart';
import 'vpn_channel_service.dart';
import 'classification_cache.dart';

/// DashboardController — จัดการ state ทั้งหมดของหน้า Dashboard
/// View จะ listen ผ่าน ListenableBuilder → อัปเดตอัตโนมัติ
class DashboardController extends ChangeNotifier {
  // ─── State ───
  bool _adBlockEnabled = false;
  bool _bannerRemoverEnabled = false;
  bool _hasApiKey = false;
  int _cachedDomains = 0;
  final List<LogEntry> _logs = [];
  StreamSubscription? _logSubscription;

  // ─── Getters ───
  bool get adBlockEnabled => _adBlockEnabled;
  bool get bannerRemoverEnabled => _bannerRemoverEnabled;
  bool get hasApiKey => _hasApiKey;
  int get cachedDomains => _cachedDomains;
  List<LogEntry> get logs => List.unmodifiable(_logs);
  bool get isActive => _adBlockEnabled || _bannerRemoverEnabled;

  /// เริ่มรับ log จาก VPN Service
  void startListeningVpnLogs() {
    _logSubscription = VpnChannelService.logStream.listen(
      (event) => addLog(event.toString(), LogType.blocked),
      onError: (e) => addLog('Log stream error: $e', LogType.info),
    );
  }

  /// โหลดสถานะ Gemini AI
  Future<void> loadAiStatus() async {
    final key = dotenv.env['GEMINI_API_KEY'] ?? '';
    final count = await ClassificationCache.getCachedCount();
    _hasApiKey = key.isNotEmpty;
    _cachedDomains = count;
    notifyListeners();
  }

  /// เพิ่ม log entry — View จะอัปเดตอัตโนมัติผ่าน notifyListeners()
  void addLog(String message, LogType type) {
    _logs.add(LogEntry(message: message, type: type, time: DateTime.now()));
    notifyListeners();
  }

  /// Toggle Ad Blocker
  void toggleAdBlock(bool value) {
    _adBlockEnabled = value;
    if (value) {
      addLog('🛡️ Ad Blocker ACTIVATED', LogType.success);
      addLog('   Ads will be blocked in AEGIS Browser', LogType.info);
    } else {
      addLog('⚪ Ad Blocker DEACTIVATED', LogType.info);
    }
  }

  /// Toggle Gambling Banner Remover
  void toggleBannerRemover(bool value) {
    _bannerRemoverEnabled = value;
    if (value) {
      addLog('🧹 Gambling Banner Remover ACTIVATED', LogType.success);
      addLog('   DOM Sanitizer ready — open browser to scan', LogType.info);
    } else {
      addLog('⚪ Gambling Banner Remover DEACTIVATED', LogType.info);
    }
  }

  /// ล้าง cache
  Future<void> clearCache() async {
    await ClassificationCache.clearCache();
    await loadAiStatus();
    addLog('🗑️ AI Cache cleared', LogType.info);
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    super.dispose();
  }
}

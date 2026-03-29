// ============================================================================
// AEGIS Shield — controllers/dashboard_controller.dart
// ============================================================================
// ChangeNotifier สำหรับจัดการ state ของ Dashboard
// แก้ช่องโหว่ #1: State Management — ใช้ notifyListeners() แทน setState()
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import '../models/log_entry.dart';
import '../models/phase_b_models.dart';
import 'ad_removal_cache.dart';
import 'app_config.dart';
import 'classification_cache.dart';
import 'debug_logger.dart';
import 'server_auth_service.dart';
import 'server_sync_service.dart';
import 'vpn_channel_service.dart';

/// DashboardController — จัดการ state ทั้งหมดของหน้า Dashboard
/// View จะ listen ผ่าน ListenableBuilder → อัปเดตอัตโนมัติ
class DashboardController extends ChangeNotifier {
  // ─── State ───
  bool _adBlockEnabled = false;
  bool _bannerRemoverEnabled = false;
  bool _hasApiKey = false;
  int _cachedDomains = 0;
  PhaseBAvailability _phaseBAvailability = PhaseBAvailability.disabled;
  bool _reportAvailable = false;
  bool _syncAvailable = false;
  bool _syncInProgress = false;
  String _phaseBMessage = 'Community backend not configured';
  DateTime? _lastSyncedAt;
  final List<LogEntry> _logs = [];
  StreamSubscription? _logSubscription;
  final ServerAuthService _authService = ServerAuthService();
  late final ServerSyncService _syncService =
      ServerSyncService(authService: _authService);

  // ─── Getters ───
  bool get adBlockEnabled => _adBlockEnabled;
  bool get bannerRemoverEnabled => _bannerRemoverEnabled;
  bool get hasApiKey => _hasApiKey;
  int get cachedDomains => _cachedDomains;
  PhaseBAvailability get phaseBAvailability => _phaseBAvailability;
  bool get reportAvailable => _reportAvailable;
  bool get syncAvailable => _syncAvailable;
  bool get syncInProgress => _syncInProgress;
  String get phaseBMessage => _phaseBMessage;
  DateTime? get lastSyncedAt => _lastSyncedAt;
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
    final count = await ClassificationCache.getCachedCount();
    _hasApiKey = AppConfig.hasGeminiApiKey;
    _cachedDomains = count;
    notifyListeners();
  }

  Future<void> initPhaseB() async {
    if (!_authService.isConfigured) {
      _phaseBAvailability = PhaseBAvailability.disabled;
      _reportAvailable = false;
      _syncAvailable = false;
      _phaseBMessage = 'Community backend disabled';
      notifyListeners();
      return;
    }

    _lastSyncedAt = await _syncService.getLastSyncedAt();

    final authResult = await _authService.ensureAuthenticated();
    if (authResult.isSuccess) {
      _phaseBAvailability = PhaseBAvailability.ready;
      _reportAvailable = true;
      _syncAvailable = true;
      _phaseBMessage = _lastSyncedAt == null
          ? 'Community sync ready'
          : 'Community sync ready · last sync ${_formatTime(_lastSyncedAt!)}';
      DebugLogger.instance.system('Community backend auth ready');
    } else {
      _phaseBAvailability = PhaseBAvailability.degraded;
      _reportAvailable = false;
      _syncAvailable = true;
      _phaseBMessage = 'Community report unavailable temporarily';
      DebugLogger.instance.error(
        'Community backend auth unavailable: '
        '${authResult.failure?.message ?? "unknown"}',
      );
    }

    notifyListeners();
  }

  Future<void> syncCommunityRules({bool forceFullResync = false}) async {
    if (!_authService.isConfigured || _syncInProgress) {
      return;
    }

    _syncInProgress = true;
    notifyListeners();

    addLog('Community sync started', LogType.info);
    DebugLogger.instance.system('Community sync started');

    final result = await _syncService.syncApprovedRules(
      forceFullResync: forceFullResync,
    );

    _syncInProgress = false;

    if (result.isSuccess) {
      final summary = result.data!;
      _lastSyncedAt = summary.syncedAt;
      _phaseBAvailability = PhaseBAvailability.ready;
      _syncAvailable = true;
      _phaseBMessage =
          'Community sync ready · ${summary.merged} rules merged';
      addLog(
        'Community sync complete (${summary.merged}/${summary.fetched} rules)',
        LogType.success,
      );
      DebugLogger.instance.system(
        'Community sync complete (${summary.merged}/${summary.fetched})',
      );
    } else {
      final failure = result.failure!;
      _phaseBAvailability = PhaseBAvailability.degraded;
      _phaseBMessage = failure.message;
      addLog('Community sync failed: ${failure.message}', LogType.info);
      DebugLogger.instance.error('Community sync failed: ${failure.message}');
    }

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
    await AdRemovalCache.clearAll();
    await loadAiStatus();
    addLog('🗑️ AI Cache cleared', LogType.info);
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  void dispose() {
    _logSubscription?.cancel();
    super.dispose();
  }
}

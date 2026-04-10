// ============================================================================
// AEGIS Shield - controllers/dashboard_controller.dart
// ============================================================================
// Dashboard state controller kept intentionally login-free for demo mode.
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/log_entry.dart';
import '../models/phase_b_models.dart';
import 'ad_removal_cache.dart';
import 'app_config.dart';
import 'classification_cache.dart';
import 'debug_logger.dart';
import 'server_sync_service.dart';
import 'vpn_channel_service.dart';

class DashboardController extends ChangeNotifier {
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
  final ServerSyncService _syncService = ServerSyncService();
  StreamSubscription? _logSubscription;

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

  void startListeningVpnLogs() {
    _logSubscription = VpnChannelService.logStream.listen(
      (event) => addLog(event.toString(), LogType.blocked),
      onError: (error) => addLog('Log stream error: $error', LogType.info),
    );
  }

  Future<void> loadAiStatus() async {
    final count = await ClassificationCache.getCachedCount();
    _hasApiKey = AppConfig.hasGeminiApiKey;
    _cachedDomains = count;
    notifyListeners();
  }

  Future<void> initPhaseB() async {
    if (!_syncService.isConfigured) {
      _phaseBAvailability = PhaseBAvailability.disabled;
      _reportAvailable = false;
      _syncAvailable = false;
      _phaseBMessage = 'Community backend disabled';
      notifyListeners();
      return;
    }

    _lastSyncedAt = await _syncService.getLastSyncedAt();
    _phaseBAvailability = PhaseBAvailability.ready;
    _reportAvailable = true;
    _syncAvailable = true;
    _phaseBMessage = _lastSyncedAt == null
        ? 'Community report ready'
        : 'Community sync ready - last sync ${_formatTime(_lastSyncedAt!)}';
    DebugLogger.instance.system('Community backend ready (anonymous mode)');
    notifyListeners();
  }

  Future<void> syncCommunityRules({bool forceFullResync = false}) async {
    if (!_syncService.isConfigured || _syncInProgress) {
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
      _reportAvailable = true;
      _syncAvailable = true;
      _phaseBMessage = 'Community sync ready - ${summary.merged} rules merged';
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
      _reportAvailable = true;
      _syncAvailable = true;
      _phaseBMessage = failure.message;
      addLog('Community sync failed: ${failure.message}', LogType.info);
      DebugLogger.instance.error('Community sync failed: ${failure.message}');
    }

    notifyListeners();
  }

  void addLog(String message, LogType type) {
    _logs.add(LogEntry(message: message, type: type, time: DateTime.now()));
    notifyListeners();
  }

  void toggleAdBlock(bool value) {
    _adBlockEnabled = value;
    if (value) {
      addLog('Ad Blocker ACTIVATED', LogType.success);
      addLog('Ads will be blocked in AEGIS Browser', LogType.info);
    } else {
      addLog('Ad Blocker DEACTIVATED', LogType.info);
    }
  }

  void toggleBannerRemover(bool value) {
    _bannerRemoverEnabled = value;
    if (value) {
      addLog('Gambling Banner Remover ACTIVATED', LogType.success);
      addLog('DOM Sanitizer ready - open browser to scan', LogType.info);
    } else {
      addLog('Gambling Banner Remover DEACTIVATED', LogType.info);
    }
  }

  Future<void> clearCache() async {
    await ClassificationCache.clearCache();
    await AdRemovalCache.clearAll();
    await loadAiStatus();
    addLog('AI Cache cleared', LogType.info);
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

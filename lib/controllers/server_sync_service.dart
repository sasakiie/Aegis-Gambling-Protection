import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/phase_b_models.dart';
import 'ad_removal_cache.dart';
import 'app_config.dart';

class ServerSyncService {
  static const String _lastSyncedAtKey = 'phase_b.last_synced_at';

  String get _baseUrl => AppConfig.pocketBaseUrl.trim();

  bool get isConfigured => _baseUrl.isNotEmpty;

  Future<DateTime?> getLastSyncedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastSyncedAtKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  Future<PhaseBResult<SyncSummary>> syncApprovedRules({
    bool forceFullResync = false,
  }) async {
    if (!isConfigured) {
      return PhaseBResult.failure(
        const PhaseBFailure(
          type: PhaseBFailureType.unavailable,
          message: 'Community sync is not configured.',
        ),
      );
    }

    final lastSyncedAt = forceFullResync ? null : await getLastSyncedAt();
    final filter = _buildFilter(lastSyncedAt);
    final uri = Uri.parse(
      '$_baseUrl/api/collections/ad_rules/records'
      '?filter=${Uri.encodeQueryComponent(filter)}'
      '&sort=%2Bupdated'
      '&perPage=200',
    );

    try {
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return PhaseBResult.failure(_mapFailure(response.statusCode));
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final items = List<Map<String, dynamic>>.from(
        payload['items'] as List? ?? const [],
      );
      final records = items.map(ServerRuleRecord.fromJson).toList();

      var mergedCount = 0;
      var latestTimestamp =
          lastSyncedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

      for (final rule in records) {
        if (!(rule.verified || rule.reportCount >= 10)) {
          continue;
        }

        await AdRemovalCache.saveCache(
          domain: rule.domain,
          selectors: rule.selectors,
          isGambling: rule.isGambling,
        );
        mergedCount += 1;
        if (rule.updatedAt.isAfter(latestTimestamp)) {
          latestTimestamp = rule.updatedAt;
        }
      }

      final syncedAt = records.isEmpty ? DateTime.now() : latestTimestamp;
      await _saveLastSyncedAt(syncedAt);

      return PhaseBResult.success(
        SyncSummary(
          fetched: records.length,
          merged: mergedCount,
          syncedAt: syncedAt,
          fullResync: forceFullResync,
        ),
      );
    } catch (_) {
      return PhaseBResult.failure(
        const PhaseBFailure(
          type: PhaseBFailureType.unavailable,
          message: 'Community sync is temporarily unavailable.',
        ),
      );
    }
  }

  String _buildFilter(DateTime? lastSyncedAt) {
    final base = '(verified=true || report_count>=10)';
    if (lastSyncedAt == null) {
      return base;
    }
    return '$base && updated > "${lastSyncedAt.toUtc().toIso8601String()}"';
  }

  Future<void> _saveLastSyncedAt(DateTime value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncedAtKey, value.toUtc().toIso8601String());
  }

  PhaseBFailure _mapFailure(int statusCode) {
    switch (statusCode) {
      case 400:
        return const PhaseBFailure(
          type: PhaseBFailureType.validation,
          message: 'Community sync request is invalid.',
          statusCode: 400,
        );
      case 401:
        return const PhaseBFailure(
          type: PhaseBFailureType.unauthorized,
          message: 'Community sync session has expired.',
          statusCode: 401,
        );
      case 429:
        return const PhaseBFailure(
          type: PhaseBFailureType.rateLimited,
          message: 'Community sync is temporarily rate limited.',
          statusCode: 429,
        );
      default:
        if (statusCode >= 500) {
          return PhaseBFailure(
            type: PhaseBFailureType.unavailable,
            message: 'Community sync server is unavailable.',
            statusCode: statusCode,
          );
        }
        return PhaseBFailure(
          type: PhaseBFailureType.unknown,
          message: 'Community sync failed.',
          statusCode: statusCode,
        );
    }
  }
}

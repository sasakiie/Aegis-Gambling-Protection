// ============================================================================
// AEGIS Shield — models/phase_b_models.dart
// ============================================================================
// Data models for Phase B community backend integration
// ============================================================================

enum PhaseBFailureType { validation, unauthorized, rateLimited, unavailable, unknown }

enum PhaseBAvailability { disabled, ready, degraded }

enum ReportType { gamblingSite, adSelector, falsePositive, selectorMiss }

class PhaseBFailure {
  final PhaseBFailureType type;
  final String message;
  final int? statusCode;

  const PhaseBFailure({
    required this.type,
    required this.message,
    this.statusCode,
  });
}

class PhaseBResult<T> {
  final T? data;
  final PhaseBFailure? failure;

  const PhaseBResult._({this.data, this.failure});

  bool get isSuccess => failure == null;

  factory PhaseBResult.success(T data) => PhaseBResult._(data: data);

  factory PhaseBResult.failure(PhaseBFailure failure) =>
      PhaseBResult._(failure: failure);
}

class ReportDraft {
  final String domain;
  final List<String> selectors;
  final bool isGambling;
  final String reason;
  final ReportType reportType;
  final String clientVersion;

  const ReportDraft({
    required this.domain,
    required this.selectors,
    required this.isGambling,
    required this.reason,
    required this.reportType,
    required this.clientVersion,
  });

  Map<String, dynamic> toJson() => {
        'domain': domain,
        'selectors': selectors,
        'is_gambling': isGambling,
        'reason': reason,
        'report_type': _reportTypeValue(reportType),
        'client_version': clientVersion,
        'status': 'pending',
      };

  static String _reportTypeValue(ReportType type) {
    switch (type) {
      case ReportType.gamblingSite:
        return 'gambling_site';
      case ReportType.adSelector:
        return 'ad_selector';
      case ReportType.falsePositive:
        return 'false_positive';
      case ReportType.selectorMiss:
        return 'selector_miss';
    }
  }
}

class ServerRuleRecord {
  final String domain;
  final List<String> selectors;
  final bool isGambling;
  final int reportCount;
  final bool verified;
  final DateTime updatedAt;

  const ServerRuleRecord({
    required this.domain,
    required this.selectors,
    required this.isGambling,
    required this.reportCount,
    required this.verified,
    required this.updatedAt,
  });

  factory ServerRuleRecord.fromJson(Map<String, dynamic> json) {
    return ServerRuleRecord(
      domain: (json['domain'] as String? ?? '').toLowerCase(),
      selectors: List<String>.from(json['selectors'] as List? ?? const []),
      isGambling: json['is_gambling'] as bool? ?? false,
      reportCount: (json['report_count'] as num?)?.toInt() ?? 0,
      verified: json['verified'] as bool? ?? false,
      updatedAt: DateTime.tryParse(json['updated'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class SyncSummary {
  final int fetched;
  final int merged;
  final DateTime syncedAt;
  final bool fullResync;

  const SyncSummary({
    required this.fetched,
    required this.merged,
    required this.syncedAt,
    this.fullResync = false,
  });
}

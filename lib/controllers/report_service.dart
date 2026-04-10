import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/phase_b_models.dart';
import 'app_config.dart';

class ReportService {
  String get _baseUrl => AppConfig.pocketBaseUrl.trim();

  bool get isConfigured => _baseUrl.isNotEmpty;

  Future<PhaseBResult<void>> submitReport(ReportDraft draft) async {
    final validationFailure = _validate(draft);
    if (validationFailure != null) {
      _debug(
        'validation failed for domain=${draft.domain}: ${validationFailure.message}',
      );
      return PhaseBResult.failure(validationFailure);
    }

    if (!isConfigured) {
      return PhaseBResult.failure(
        const PhaseBFailure(
          type: PhaseBFailureType.unavailable,
          message: 'Community backend is not configured.',
        ),
      );
    }

    final uri = Uri.parse('$_baseUrl/api/collections/reports/records');
    final payload = _normalizeDraft(draft).toJson();

    try {
      _debug('POST $uri payload=${jsonEncode(payload)}');

      final response = await http.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      _debug(
        'response status=${response.statusCode} body=${_truncate(response.body)}',
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return PhaseBResult.success(null);
      }

      return PhaseBResult.failure(
        _mapFailure(response.statusCode, response.body),
      );
    } catch (error) {
      _debug('network exception for domain=${draft.domain}: $error');
      return PhaseBResult.failure(
        const PhaseBFailure(
          type: PhaseBFailureType.unavailable,
          message: 'Report is temporarily unavailable.',
        ),
      );
    }
  }

  ReportDraft _normalizeDraft(ReportDraft draft) {
    return ReportDraft(
      domain: draft.domain.trim().toLowerCase(),
      selectors: draft.selectors
          .map((selector) => selector.trim())
          .where((selector) => selector.isNotEmpty)
          .toList(),
      isGambling: draft.isGambling,
      reason: draft.reason.trim(),
      reportType: draft.reportType,
      clientVersion: draft.clientVersion.trim(),
    );
  }

  PhaseBFailure? _validate(ReportDraft draft) {
    final normalizedDomain = draft.domain.trim().toLowerCase();
    if (normalizedDomain.isEmpty) {
      return const PhaseBFailure(
        type: PhaseBFailureType.validation,
        message: 'Domain is required.',
        statusCode: 400,
      );
    }

    if (draft.reason.trim().isEmpty) {
      return const PhaseBFailure(
        type: PhaseBFailureType.validation,
        message: 'Reason is required.',
        statusCode: 400,
      );
    }

    if (draft.reason.length > 500) {
      return const PhaseBFailure(
        type: PhaseBFailureType.validation,
        message: 'Reason is too long.',
        statusCode: 400,
      );
    }

    if (draft.selectors.length > 20) {
      return const PhaseBFailure(
        type: PhaseBFailureType.validation,
        message: 'Too many selectors in one report.',
        statusCode: 400,
      );
    }

    for (final selector in draft.selectors) {
      if (selector.trim().isEmpty || selector.length > 200) {
        return const PhaseBFailure(
          type: PhaseBFailureType.validation,
          message: 'Selector payload is invalid.',
          statusCode: 400,
        );
      }
    }

    return null;
  }

  PhaseBFailure _mapFailure(int statusCode, [String? responseBody]) {
    final serverMessage = _extractServerMessage(responseBody);

    switch (statusCode) {
      case 400:
        return PhaseBFailure(
          type: PhaseBFailureType.validation,
          message: serverMessage ?? 'Report payload is invalid.',
          statusCode: 400,
        );
      case 401:
      case 403:
        return PhaseBFailure(
          type: PhaseBFailureType.unauthorized,
          message: serverMessage ?? 'Report submission is not allowed.',
          statusCode: statusCode,
        );
      case 429:
        return PhaseBFailure(
          type: PhaseBFailureType.rateLimited,
          message: serverMessage ?? 'Report is temporarily rate limited.',
          statusCode: 429,
        );
      default:
        if (statusCode >= 500) {
          return PhaseBFailure(
            type: PhaseBFailureType.unavailable,
            message: serverMessage ?? 'Report service is unavailable.',
            statusCode: statusCode,
          );
        }
        return PhaseBFailure(
          type: PhaseBFailureType.unknown,
          message: serverMessage ?? 'Report request failed.',
          statusCode: statusCode,
        );
    }
  }

  String? _extractServerMessage(String? responseBody) {
    if (responseBody == null || responseBody.trim().isEmpty) {
      return null;
    }

    try {
      final payload = jsonDecode(responseBody);
      if (payload is Map<String, dynamic>) {
        final directMessage = payload['message'];
        if (directMessage is String && directMessage.trim().isNotEmpty) {
          return directMessage.trim();
        }

        final data = payload['data'];
        if (data is Map<String, dynamic>) {
          for (final value in data.values) {
            if (value is Map<String, dynamic>) {
              final message = value['message'];
              if (message is String && message.trim().isNotEmpty) {
                return message.trim();
              }
            }
          }
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  String _truncate(String value, {int maxLength = 300}) {
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength)}...';
  }

  void _debug(String message) {
    developer.log(message, name: 'ReportService');
    debugPrint('[ReportService] $message');
  }
}

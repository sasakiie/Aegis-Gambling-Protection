import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/phase_b_models.dart';
import 'server_auth_service.dart';

class ReportService {
  final ServerAuthService _authService;

  ReportService({ServerAuthService? authService})
      : _authService = authService ?? ServerAuthService();

  Future<PhaseBResult<void>> submitReport(ReportDraft draft) async {
    final validationFailure = _validate(draft);
    if (validationFailure != null) {
      _debug(
        'validation failed for domain=${draft.domain}: ${validationFailure.message}',
      );
      return PhaseBResult.failure(validationFailure);
    }

    final authResult = await _authService.ensureAuthenticated();
    if (!authResult.isSuccess) {
      _debug(
        'auth failed for domain=${draft.domain}: ${authResult.failure?.message ?? "unknown"}',
      );
      return PhaseBResult.failure(authResult.failure!);
    }

    final session = authResult.data!;
    final uri =
        Uri.parse('${_authService.baseUrl}/api/collections/reports/records');
    final payload = draft.toJson();

    try {
      _debug('POST $uri payload=${jsonEncode(payload)}');

      var response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.token}',
        },
        body: jsonEncode(payload),
      );

      _debug(
        'response status=${response.statusCode} body=${_truncate(response.body)}',
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return PhaseBResult.success(null);
      }

      if (response.statusCode == 401) {
        final retryAuth = await _authService.ensureAuthenticated(
          forceRefresh: true,
        );
        if (!retryAuth.isSuccess) {
          _debug(
            'retry auth failed for domain=${draft.domain}: ${retryAuth.failure?.message ?? "unknown"}',
          );
          return PhaseBResult.failure(retryAuth.failure!);
        }

        final retrySession = retryAuth.data!;
        response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${retrySession.token}',
          },
          body: jsonEncode(payload),
        );

        _debug(
          'retry response status=${response.statusCode} body=${_truncate(response.body)}',
        );

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return PhaseBResult.success(null);
        }
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
        return PhaseBFailure(
          type: PhaseBFailureType.unauthorized,
          message: serverMessage ?? 'Report session has expired.',
          statusCode: 401,
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

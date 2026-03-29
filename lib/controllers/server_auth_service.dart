import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/phase_b_models.dart';
import 'app_config.dart';

class ServerAuthService {
  static const String _credentialEmailKey = 'phase_b.credentials.email';
  static const String _credentialPasswordKey = 'phase_b.credentials.password';
  static const String _sessionTokenKey = 'phase_b.session.token';
  static const String _sessionUserIdKey = 'phase_b.session.user_id';
  static const String _sessionAuthenticatedAtKey =
      'phase_b.session.authenticated_at';

  String get baseUrl => AppConfig.pocketBaseUrl;

  bool get isConfigured => baseUrl.isNotEmpty;

  Future<PhaseBAuthSession?> getCachedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_sessionTokenKey);
    final userId = prefs.getString(_sessionUserIdKey);
    final authenticatedAtRaw = prefs.getString(_sessionAuthenticatedAtKey);
    final authenticatedAt = authenticatedAtRaw == null
        ? null
        : DateTime.tryParse(authenticatedAtRaw);

    if (token == null ||
        token.isEmpty ||
        userId == null ||
        userId.isEmpty ||
        authenticatedAt == null) {
      return null;
    }

    return PhaseBAuthSession(
      userId: userId,
      token: token,
      authenticatedAt: authenticatedAt,
    );
  }

  Future<PhaseBResult<PhaseBAuthSession>> ensureAuthenticated({
    bool forceRefresh = false,
  }) async {
    if (!isConfigured) {
      return PhaseBResult.failure(
        const PhaseBFailure(
          type: PhaseBFailureType.unavailable,
          message: 'Community backend is not configured.',
        ),
      );
    }

    if (!forceRefresh) {
      final cached = await getCachedSession();
      if (cached != null) {
        return PhaseBResult.success(cached);
      }
    }

    try {
      final credentialsResult = await _loadOrCreateCredentials();
      if (!credentialsResult.isSuccess) {
        return PhaseBResult.failure(credentialsResult.failure!);
      }

      final credentials = credentialsResult.data!;
      var authResult = await _authenticateWithPassword(
        credentials.email,
        credentials.password,
      );

      if (!authResult.isSuccess &&
          credentials.reusedExisting &&
          _shouldRotateCredentials(authResult.failure!)) {
        await _clearCredentials();
        final retryCredentialsResult = await _loadOrCreateCredentials();
        if (!retryCredentialsResult.isSuccess) {
          return PhaseBResult.failure(retryCredentialsResult.failure!);
        }

        final retryCredentials = retryCredentialsResult.data!;
        authResult = await _authenticateWithPassword(
          retryCredentials.email,
          retryCredentials.password,
        );
      }

      if (!authResult.isSuccess) {
        await clearSession();
        return PhaseBResult.failure(authResult.failure!);
      }

      final session = authResult.data!;
      await _saveSession(session);
      return PhaseBResult.success(session);
    } catch (_) {
      return PhaseBResult.failure(
        const PhaseBFailure(
          type: PhaseBFailureType.unavailable,
          message: 'Community auth is temporarily unavailable.',
        ),
      );
    }
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionTokenKey);
    await prefs.remove(_sessionUserIdKey);
    await prefs.remove(_sessionAuthenticatedAtKey);
  }

  Future<void> _clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_credentialEmailKey);
    await prefs.remove(_credentialPasswordKey);
  }

  Future<void> _saveSession(PhaseBAuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionTokenKey, session.token);
    await prefs.setString(_sessionUserIdKey, session.userId);
    await prefs.setString(
      _sessionAuthenticatedAtKey,
      session.authenticatedAt.toIso8601String(),
    );
  }

  Future<PhaseBResult<_PseudoAnonymousCredentials>>
  _loadOrCreateCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedEmail = prefs.getString(_credentialEmailKey);
    final cachedPassword = prefs.getString(_credentialPasswordKey);

    if (cachedEmail != null &&
        cachedEmail.isNotEmpty &&
        cachedPassword != null &&
        cachedPassword.isNotEmpty) {
      return PhaseBResult.success(
        _PseudoAnonymousCredentials(
          email: cachedEmail,
          password: cachedPassword,
          reusedExisting: true,
        ),
      );
    }

    final email = _randomEmail();
    final password = _randomPassword();
    final registerResult = await _registerPseudoAnonymousUser(email, password);

    if (!registerResult.isSuccess) {
      return PhaseBResult.failure(registerResult.failure!);
    }

    await prefs.setString(_credentialEmailKey, email);
    await prefs.setString(_credentialPasswordKey, password);

    return PhaseBResult.success(
      _PseudoAnonymousCredentials(
        email: email,
        password: password,
        reusedExisting: false,
      ),
    );
  }

  Future<PhaseBResult<void>> _registerPseudoAnonymousUser(
    String email,
    String password,
  ) async {
    final uri = Uri.parse('$baseUrl/api/collections/users/records');
    final response = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'passwordConfirm': password,
      }),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return PhaseBResult.success(null);
    }

    if (response.statusCode == 400 && _looksLikeExistingUser(response.body)) {
      return PhaseBResult.success(null);
    }

    return PhaseBResult.failure(_mapFailure(response));
  }

  Future<PhaseBResult<PhaseBAuthSession>> _authenticateWithPassword(
    String email,
    String password,
  ) async {
    final uri = Uri.parse('$baseUrl/api/collections/users/auth-with-password');
    final response = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'identity': email,
        'password': password,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return PhaseBResult.failure(_mapFailure(response));
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final token = payload['token'] as String? ?? '';
    final record = payload['record'] as Map<String, dynamic>? ?? const {};
    final userId = record['id'] as String? ?? '';

    if (token.isEmpty || userId.isEmpty) {
      return PhaseBResult.failure(
        const PhaseBFailure(
          type: PhaseBFailureType.unknown,
          message: 'Community auth response is incomplete.',
        ),
      );
    }

    return PhaseBResult.success(
      PhaseBAuthSession(
        userId: userId,
        token: token,
        authenticatedAt: DateTime.now(),
      ),
    );
  }

  bool _shouldRotateCredentials(PhaseBFailure failure) {
    return failure.type == PhaseBFailureType.unauthorized ||
        failure.type == PhaseBFailureType.validation;
  }

  bool _looksLikeExistingUser(String responseBody) {
    try {
      final payload = jsonDecode(responseBody);
      final normalized = jsonEncode(payload).toLowerCase();
      return normalized.contains('already') ||
          normalized.contains('exists') ||
          normalized.contains('unique');
    } catch (_) {
      final normalized = responseBody.toLowerCase();
      return normalized.contains('already') ||
          normalized.contains('exists') ||
          normalized.contains('unique');
    }
  }

  String _randomEmail() => 'aegis_${_randomString(16)}@example.com';

  String _randomPassword() => _randomString(32);

  String _randomString(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List<String>.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  PhaseBFailure _mapFailure(http.Response response) {
    switch (response.statusCode) {
      case 400:
        return const PhaseBFailure(
          type: PhaseBFailureType.validation,
          message: 'Community auth request is invalid.',
          statusCode: 400,
        );
      case 401:
        return const PhaseBFailure(
          type: PhaseBFailureType.unauthorized,
          message: 'Community auth session is invalid.',
          statusCode: 401,
        );
      case 429:
        return const PhaseBFailure(
          type: PhaseBFailureType.rateLimited,
          message: 'Community auth is temporarily rate limited.',
          statusCode: 429,
        );
      default:
        if (response.statusCode >= 500) {
          return PhaseBFailure(
            type: PhaseBFailureType.unavailable,
            message: 'Community auth server is unavailable.',
            statusCode: response.statusCode,
          );
        }
        return PhaseBFailure(
          type: PhaseBFailureType.unknown,
          message: 'Community auth failed.',
          statusCode: response.statusCode,
        );
    }
  }
}

class _PseudoAnonymousCredentials {
  final String email;
  final String password;
  final bool reusedExisting;

  const _PseudoAnonymousCredentials({
    required this.email,
    required this.password,
    required this.reusedExisting,
  });
}

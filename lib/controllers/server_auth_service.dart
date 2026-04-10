import '../models/phase_b_models.dart';
import 'app_config.dart';

class ServerAuthService {
  const ServerAuthService();

  String get baseUrl => AppConfig.pocketBaseUrl.trim();

  bool get isConfigured => false;

  Future<PhaseBResult<void>> ensureAuthenticated({
    bool forceRefresh = false,
  }) async {
    return PhaseBResult.failure(
      const PhaseBFailure(
        type: PhaseBFailureType.unavailable,
        message:
            'ServerAuthService is deprecated. AEGIS now uses anonymous community mode.',
      ),
    );
  }

  Future<void> clearSession() async {}
}

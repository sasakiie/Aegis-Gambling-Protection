import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static final Map<String, String> _values = <String, String>{};
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;

    final raw = await rootBundle.loadString('assets/app_config.env');
    _mergeFromString(raw);

    try {
      await dotenv.load(fileName: '.env');
      for (final entry in dotenv.env.entries) {
        final value = entry.value.trim();
        if (value.isEmpty) continue;
        _values[entry.key] = value;
      }
    } catch (_) {
      // Optional in runtime builds.
    }

    _loaded = true;
  }

  static String get pocketBaseUrl => (_values['POCKETBASE_URL'] ?? '').trim();

  static String get geminiApiKey => (_values['GEMINI_API_KEY'] ?? '').trim();

  static bool get hasGeminiApiKey => geminiApiKey.isNotEmpty;

  static void _mergeFromString(String raw) {
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      final separatorIndex = trimmed.indexOf('=');
      if (separatorIndex <= 0) continue;

      final key = trimmed.substring(0, separatorIndex).trim();
      final value = trimmed.substring(separatorIndex + 1).trim();
      if (key.isEmpty || value.isEmpty) continue;

      _values[key] = value;
    }
  }
}

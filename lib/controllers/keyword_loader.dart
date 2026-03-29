// ============================================================================
// AEGIS Shield — controllers/keyword_loader.dart
// ============================================================================
// Singleton service โหลด keyword list จาก gambling_keywords.json
// ย้ายจาก lib/keyword_loader.dart → lib/controllers/keyword_loader.dart
// ============================================================================

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class KeywordLoader {
  // ─── Singleton Pattern ───
  static final KeywordLoader _instance = KeywordLoader._internal();
  factory KeywordLoader() => _instance;
  KeywordLoader._internal();

  List<String> brands = [];
  List<String> thaiKeywords = [];
  List<String> urlRegexPatterns = [];
  List<String> gameProviders = [];
  List<String> gameTypes = [];
  List<String> financialTerms = [];
  List<String> gameNames = [];
  List<String> urlIndicators = [];
  List<String> genericGamblingSignals = [];

  List<RegExp> _compiledPatterns = [];
  List<String> _normalizedBrands = [];
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;

    try {
      final jsonStr = await rootBundle.loadString(
        'assets/gambling_keywords.json',
      );
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      brands = List<String>.from(data['brands'] ?? []);
      thaiKeywords = List<String>.from(data['thai_keywords'] ?? []);
      urlRegexPatterns = List<String>.from(data['url_regex_patterns'] ?? []);
      gameProviders = List<String>.from(data['game_providers'] ?? []);
      gameTypes = List<String>.from(data['game_types'] ?? []);
      financialTerms = List<String>.from(data['financial_terms'] ?? []);
      gameNames = List<String>.from(data['game_names'] ?? []);
      urlIndicators = List<String>.from(data['url_indicators'] ?? []);
      genericGamblingSignals = List<String>.from(data['generic_gambling_signals'] ?? []);
      _normalizedBrands = brands.map(_normalizeForMatch).toList();

      _compiledPatterns = urlRegexPatterns
          .map((p) {
            try {
              return RegExp(p, caseSensitive: false);
            } catch (e) {
              return null;
            }
          })
          .whereType<RegExp>()
          .toList();

      _loaded = true;
    } catch (e) {
      brands = _fallbackBrands;
      _loaded = true;
    }
  }

  bool isGambling(String url) {
    final lower = url.toLowerCase();
    final normalized = _normalizeForMatch(url);
    for (final brand in brands) {
      if (lower.contains(brand)) return true;
    }
    for (final brand in _normalizedBrands) {
      if (brand.isNotEmpty && normalized.contains(brand)) return true;
    }
    for (final pattern in _compiledPatterns) {
      if (pattern.hasMatch(lower)) return true;
      if (pattern.hasMatch(normalized)) return true;
    }
    return false;
  }

  static String _normalizeForMatch(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[\s\-_]'), '');
  }

  String toJsonForJs() {
    return jsonEncode({
      'brands': brands,
      'thaiKeywords': thaiKeywords,
      'urlPatterns': urlRegexPatterns,
    });
  }

  int get brandCount => brands.length;
  int get patternCount => _compiledPatterns.length;
  int get providerCount => gameProviders.length;
  int get gameTypeCount => gameTypes.length;
  int get genericSignalCount => genericGamblingSignals.length;

  static const List<String> _fallbackBrands = [
    'ufabet', 'ufa365', 'ufa888', 'pgslot', 'slotxo', 'superslot',
    'sagaming', 'betflik', 'betflix', 'joker123', 'sbobet', 'gclub',
    'lsm99', 'sexybaccarat', 'sexygame', 'ambbet', 'dafabet',
    'happyluke', 'empire777',
  ];
}

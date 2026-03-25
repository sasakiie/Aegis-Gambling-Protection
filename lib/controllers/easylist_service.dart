// ============================================================================
// AEGIS Shield — controllers/easylist_service.dart
// ============================================================================
// ย้ายจาก lib/easylist_service.dart → lib/controllers/easylist_service.dart
// ============================================================================

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class EasyListService {
  static EasyListService? _instance;
  EasyListService._();

  static EasyListService get instance {
    _instance ??= EasyListService._();
    return _instance!;
  }

  static const List<String> _filterListUrls = [
    'https://easylist.to/easylist/easylist.txt',
  ];

  static const String _cacheKey = 'easylist_css_rules';
  static const String _cacheTimestampKey = 'easylist_timestamp';
  static const int _cacheDurationHours = 24;

  List<String> _genericRules = [];
  Map<String, List<String>> _siteRules = {};
  bool _isLoaded = false;

  int get ruleCount =>
      _genericRules.length +
      _siteRules.values.fold(0, (sum, list) => sum + list.length);

  Future<void> loadFilters({Function(String)? onLog}) async {
    if (_isLoaded && _genericRules.isNotEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final cachedRules = prefs.getString(_cacheKey);
    final timestamp = prefs.getInt(_cacheTimestampKey) ?? 0;
    final cacheAge = DateTime.now().millisecondsSinceEpoch - timestamp;
    final cacheValid = cacheAge < _cacheDurationHours * 3600 * 1000;

    if (cachedRules != null && cachedRules.isNotEmpty && cacheValid) {
      _parseCachedRules(cachedRules);
      _isLoaded = true;
      onLog?.call('📋 EasyList: โหลดจาก cache ($ruleCount rules)');
      return;
    }

    onLog?.call('📥 EasyList: กำลังดาวน์โหลด filter lists...');

    try {
      final allLines = <String>[];
      for (final url in _filterListUrls) {
        try {
          final response = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 15));
          if (response.statusCode == 200) {
            allLines.addAll(response.body.split('\n'));
            onLog?.call('✅ Downloaded: ${url.split('/').last}');
          }
        } catch (e) {
          onLog?.call('⚠️ Failed to download: ${url.split('/').last}');
        }
      }

      if (allLines.isEmpty) {
        if (cachedRules != null && cachedRules.isNotEmpty) {
          _parseCachedRules(cachedRules);
          _isLoaded = true;
          onLog?.call('📋 EasyList: ใช้ cache เก่า ($ruleCount rules)');
        }
        return;
      }

      _parseFilterLines(allLines, onLog: onLog);

      final cacheData = _buildCacheString();
      await prefs.setString(_cacheKey, cacheData);
      await prefs.setInt(
        _cacheTimestampKey,
        DateTime.now().millisecondsSinceEpoch,
      );

      _isLoaded = true;
      onLog?.call('📋 EasyList: parse สำเร็จ ($ruleCount rules)');
    } catch (e) {
      onLog?.call('❌ EasyList error: $e');
      if (cachedRules != null && cachedRules.isNotEmpty) {
        _parseCachedRules(cachedRules);
        _isLoaded = true;
      }
    }
  }

  void _parseFilterLines(List<String> lines, {Function(String)? onLog}) {
    _genericRules = [];
    _siteRules = {};
    int parsed = 0;
    int skipped = 0;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('!')) continue;
      if (line.startsWith('[')) continue;
      if (line.startsWith('#@#')) continue;
      if (!line.contains('##')) continue;
      if (line.contains('##+js(')) continue;
      if (line.contains(':has(')) continue;
      if (line.contains(':has-text(')) continue;
      if (line.contains(':matches-')) continue;
      if (line.contains(':upward(')) continue;
      if (line.contains(':xpath(')) continue;
      if (line.contains(':style(')) continue;

      final hashIdx = line.indexOf('##');
      if (hashIdx < 0) continue;

      final domainPart = line.substring(0, hashIdx).trim();
      final selector = line.substring(hashIdx + 2).trim();

      if (selector.isEmpty) continue;
      if (selector.length > 200) continue;
      if (selector.contains("'") && selector.contains('"')) continue;
      if (selector.contains('\\')) continue;

      if (domainPart.isEmpty) {
        _genericRules.add(selector);
      } else {
        final domains = domainPart.split(',');
        for (final d in domains) {
          final domain = d.trim().replaceAll('~', '');
          if (domain.isEmpty || d.trim().startsWith('~')) continue;
          _siteRules.putIfAbsent(domain, () => []).add(selector);
        }
      }
      parsed++;
    }

    skipped = lines.length - parsed;
    onLog?.call('🔎 EasyList parsed: $parsed cosmetic, $skipped skipped/network');
  }

  static const List<String> _adKeywords = [
    'ad-', 'ad_', 'ads-', 'ads_', 'adsbygoogle', 'adsbox', 'adslot',
    'advert', 'adwrap', 'adcontain', 'adfox', 'adform', 'adtech',
    'banner', 'sponsor', 'promoted', 'promo-',
    'popup', 'pop-up', 'popunder', 'overlay-ad',
    'taboola', 'outbrain', 'mgid', 'revcontent',
    'google_ads', 'googletag', 'gpt-ad', 'dfp-ad',
    'sticky-ad', 'floating-ad', 'interstitial',
    'cookie-consent', 'cookie-banner', 'cookie-notice',
    'newsletter-popup', 'subscribe-popup',
  ];

  bool _isAdSelector(String selector) {
    final lower = selector.toLowerCase();
    for (final kw in _adKeywords) {
      if (lower.contains(kw)) return true;
    }
    return false;
  }

  String getCSSRules(String domain) {
    final rules = <String>[];
    for (final entry in _siteRules.entries) {
      if (domain.contains(entry.key) || entry.key.contains(domain)) {
        final siteLimit = entry.value.length > 200
            ? entry.value.sublist(0, 200)
            : entry.value;
        rules.addAll(siteLimit);
      }
    }
    int genericCount = 0;
    for (final selector in _genericRules) {
      if (genericCount >= 300) break;
      if (_isAdSelector(selector)) {
        rules.add(selector);
        genericCount++;
      }
    }
    if (rules.isEmpty) return '';
    final buffer = StringBuffer();
    for (var i = 0; i < rules.length; i += 20) {
      final end = (i + 20 < rules.length) ? i + 20 : rules.length;
      final batch = rules.sublist(i, end).join(',\n');
      buffer.writeln('$batch { display: none !important; }');
    }
    return buffer.toString();
  }

  String getInjectionJS(String domain) {
    final css = getCSSRules(domain);
    if (css.isEmpty) return '';
    final escapedCss = css
        .replaceAll('\\', '\\\\')
        .replaceAll('`', '\\`')
        .replaceAll('\$', '\\\$')
        .replaceAll('\r', '');
    return '''
(function() {
  try {
    if (document.getElementById('aegis-easylist-css')) return;
    var style = document.createElement('style');
    style.id = 'aegis-easylist-css';
    style.textContent = `$escapedCss`;
    (document.head || document.documentElement).appendChild(style);
    if (window.AegisAdBlock) {
      AegisAdBlock.postMessage('📋 EasyList: injected CSS rules for ' + location.hostname);
    }
  } catch(e) {
    if (window.AegisAdBlock) {
      AegisAdBlock.postMessage('⚠️ EasyList injection error: ' + e.message);
    }
  }
})();
''';
  }

  String _buildCacheString() {
    final parts = <String>[];
    for (final r in _genericRules) {
      parts.add('##$r');
    }
    for (final entry in _siteRules.entries) {
      for (final r in entry.value) {
        parts.add('${entry.key}##$r');
      }
    }
    return parts.join('\n');
  }

  void _parseCachedRules(String cached) {
    _parseFilterLines(cached.split('\n'));
  }
}

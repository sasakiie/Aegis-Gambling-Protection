// ============================================================================
// AEGIS Shield — Gambling Blocking Test Suite
// ============================================================================
// ทดสอบว่า KeywordLoader.isGambling() สามารถตรวจจับ domain พนัน
// จาก StevenBlack/hosts gambling-only list ได้หรือไม่
//
// Data source:
//   https://github.com/StevenBlack/hosts/blob/master/alternates/gambling-only/hosts
//
// วิธีรัน:
//   flutter test test/gambling_blocking_test.dart
// ============================================================================

import 'package:flutter_test/flutter_test.dart';

// ============================================================================
// Standalone KeywordLoader สำหรับ Unit Test
// (ไม่ต้อง rootBundle / Flutter binding — ใช้ data ตรง)
// ============================================================================

class TestKeywordLoader {
  final List<String> brands;
  final List<RegExp> compiledPatterns;
  final List<String> urlIndicators;

  TestKeywordLoader({
    required this.brands,
    required List<String> urlRegexPatterns,
    required this.urlIndicators,
  }) : compiledPatterns = urlRegexPatterns
            .map((p) {
              try {
                return RegExp(p, caseSensitive: false);
              } catch (e) {
                return null;
              }
            })
            .whereType<RegExp>()
            .toList();

  /// ตรวจว่า URL ตรงกับ gambling brand/pattern หรือไม่
  /// (Logic เดียวกับ KeywordLoader.isGambling())
  bool isGambling(String url) {
    final lower = url.toLowerCase();

    // เช็ค exact brand match
    for (final brand in brands) {
      if (lower.contains(brand)) return true;
    }

    // เช็ค regex patterns
    for (final pattern in compiledPatterns) {
      if (pattern.hasMatch(lower)) return true;
    }

    return false;
  }
}

// ============================================================================
// Keywords Data (เหมือนใน gambling_keywords.json)
// ============================================================================

final _testLoader = TestKeywordLoader(
  brands: [
    'ufabet', 'ufa365', 'ufa888', 'ufa168', 'ufa191',
    'ufazeed', 'ufabomb', 'ufac4', 'ufafat',
    'pgslot', 'pgsoft',
    'betflik', 'betflix', 'betflip',
    'joker123', 'jokergaming',
    'sexybaccarat', 'sexygame', 'sexygame1688',
    'sagaming', 'sagame', 'sagame1688',
    'slotxo', 'slotgame', 'slotgame66', 'slotgame666', 'slotgame6666',
    'superslot',
    'ambbet', 'lucabet', 'biobet', 'databet', 'sbobet',
    'lsm99', 'gclub',
    'live22', 'mega888', 'kiss918', 'pussy888',
    'ole777', 'fun88', 'w88', 'dafabet', 'happyluke', 'empire777',
    'foxz168', 'panama888', 'panama999',
    'lockdown168', 'lockdown888',
    'brazil99', 'brazil999',
    'kingdom66', 'kingdom666',
    'lotto77', 'lotto88',
    'ssgame66', 'ssgame666',
    'ruay', 'mafia88', 'game1688', 'game1688o',
  ],
  urlRegexPatterns: [
    r'ufa\d+',
    r'slot.*game',
    r'pgslot',
    r'betfli[kx]',
    r'sagam[ei]',
    r'sexygame',
    r'panama\d+',
    r'lockdown\d+',
    r'brazil\d+',
    r'kingdom\d+',
    r'ssgame\d+',
    r'lotto\d+',
    r'sbobet',
    r'gclub',
    r'lsm\d+',
    r'ambbet',
    r'superslot',
    r'slotxo',
    r'live22',
    r'mega\s*888',
    r'ole\s*777',
    r'fun\s*88',
    r'mafia\s*88',
    r'dafabet',
    r'lucabet',
    r'databet',
    r'foxz\d+',
    r'(?:slot|bet|game|play|win|vip|pro|club)[\-_]?\d{2,}',
    r'\d{2,}(?:slot|bet|game|casino|play)',
  ],
  urlIndicators: [
    'slot', 'bet', 'casino', 'ufa', 'sbo', 'joker', '888', '168',
  ],
);

// ============================================================================
// StevenBlack Gambling Domains — ตัวอย่างหลากหลายหมวด
// ============================================================================

/// เว็บพนันจาก StevenBlack hosts ที่ AEGIS ต้องบล็อคได้
/// แบ่งเป็นหมวดหมู่เพื่อวิเคราะห์จุดแข็ง/จุดอ่อน
const Map<String, List<String>> stevenBlackDomains = {
  // ─── หมวด 1: เว็บที่มี Brand/Keyword ตรง → ควรจับได้ 100% ───
  'brand_match': [
    'ufabet168.com',
    'ufabet888.net',
    'ufa365.info',
    'ufa888.com',
    'pgslot.co',
    'sbobet.com',
    'dafabet.com',
    'fun88.com',
    'w88.com',
    'gclub.com',
    'slotxo.com',
    'betflix.com',
    'joker123.net',
    'sagaming.com',
    'lsm99.com',
    'ambbet.com',
    'superslot.com',
    'happyluke.com',
    'empire777.com',
    'ole777.com',
    'mega888.com',
    'mafia88.com',
    'live22.com',
    'sexy gaming.com',
    'lucabet.com',
  ],

  // ─── หมวด 2: เว็บที่ตรงกับ Regex Pattern → ควรจับได้ ───
  'regex_match': [
    '789bet.com',        // \d{2,}bet
    '888b.com',          // 888 + bet pattern
    '11bet.com',         // \d{2,}bet
    '188bet.pro',        // \d{2,}bet
    '123win.pro',        // \d{2,}win (ไม่ตรง pattern เพราะต้อง slot|bet|game|play|win)
    '8xbet.com',         // \d{2,}bet (ไม่ตรง regex ต้อง \d{2,} ก่อน)
    '98win.com',         // \d{2,}win (ไม่ตรง) 
    'slot88.com',        // slot + \d{2,}
    'bet168.com',        // bet + \d{2,}
    '92lottery.com',     // \d{2,} + lottery (ไม่มี pattern)
    'foxz168.com',       // foxz\d+
    'lotto77.com',       // lotto\d+
    'casino88.com',      // casino + \d{2,} (ไม่มี pattern แต่มี indicator)
  ],

  // ─── หมวด 3: เว็บไทย/เอเชียจาก StevenBlack → ท้าทายกว่า ───
  'thai_asian_sites': [
    'ae888.com',         // ไม่ตรง brand แต่มี 888
    '789club.com',       // club + \d{2,}
    '8kbet.com',         // \d + bet
    '8live.com',         // ไม่ตรง pattern
    '68gamebai.social',  // \d{2,}game
    'b52.club',          // ไม่ตรงเลย
    'go88.com',          // \d{2,} + ไม่มี keyword
    'alo789.com',        // ไม่ตรง pattern
    'bachhoa88.com',     // มี 88 แต่ bachhoa ไม่ใช่ gambling keyword
    'mocbai.cc',         // ไม่มี keyword เลย
    'shbet3.com',        // bet ตรง pattern
    'sky88.com',         // มี 88
    'st666.win',         // .win TLD + 666
    'topbet.net',        // bet
    'red88.com',         // มี 88
    'debet.uk',          // bet
    'sin88.com',         // มี 88
    'vn88.com',          // มี 88
    'mu9.club',          // ไม่มี keyword
    'nbet.vin',          // bet
  ],

  // ─── หมวด 4: เว็บสากลจาก StevenBlack → international gambling ───
  'international_sites': [
    '007win.com',        // win + \d
    '009.casino',        // .casino TLD
    '3bet.win',          // bet + .win
    '3kingclub.com',     // club
    '58win.com',         // \d{2,}win
    '868vip.asia',       // vip + \d
    'agbet.co',          // bet
    'ball88.com',        // มี 88
    '88thaicasinoslots.com', // มี casino + slot + 88
    '88gobet.com',       // มี bet + 88
  ],
};

/// เว็บที่ปลอดภัย — ต้องไม่ถูกบล็อค (False Positive Test)
const List<String> safeWebsites = [
  'google.com',
  'facebook.com',
  'youtube.com',
  'thairath.co.th',
  'sanook.com',
  'pantip.com',
  'kapook.com',
  'github.com',
  'stackoverflow.com',
  'medium.com',
  'twitter.com',
  'instagram.com',
  'shopee.co.th',
  'lazada.co.th',
  'agoda.com',
  'booking.com',
  'wikipedia.org',
  'bbc.com',
  'cnn.com',
  'line.me',
  'grab.com',
  'kbank.com',
  'scb.co.th',
  'bangkokpost.com',
  'dailynews.co.th',
  'nationtv.tv',
  'ch3thailand.com',
  'ch7.com',
  'khaosod.co.th',
  'matichon.co.th',
];

// ============================================================================
// TEST SUITE
// ============================================================================

void main() {
  // ════════════════════════════════════════════════════════════════════
  // Group 1: Brand Match — ต้องจับได้ 100%
  // ════════════════════════════════════════════════════════════════════
  group('🎯 Brand Match Detection', () {
    for (final domain in stevenBlackDomains['brand_match']!) {
      test('should block gambling domain: $domain', () {
        final url = 'https://$domain';
        expect(
          _testLoader.isGambling(url),
          isTrue,
          reason: '$domain should be detected as gambling (brand match)',
        );
      });
    }
  });

  // ════════════════════════════════════════════════════════════════════
  // Group 2: Regex Pattern Match
  // ════════════════════════════════════════════════════════════════════
  group('🔍 Regex Pattern Detection', () {
    for (final domain in stevenBlackDomains['regex_match']!) {
      test('should detect gambling pattern in: $domain', () {
        final url = 'https://$domain';
        final result = _testLoader.isGambling(url);
        // Log result but don't fail — some may need new patterns
        if (!result) {
          // ignore: avoid_print
          print('⚠️ MISSED: $domain — needs new pattern or brand');
        }
        // Use expect for domains that SHOULD be caught
        expect(
          result,
          isTrue,
          reason: '$domain should be caught by regex patterns',
        );
      });
    }
  });

  // ════════════════════════════════════════════════════════════════════
  // Group 3: Thai/Asian Gambling Sites
  // ════════════════════════════════════════════════════════════════════
  group('🇹🇭 Thai/Asian Gambling Sites', () {
    int detected = 0;
    int total = stevenBlackDomains['thai_asian_sites']!.length;

    for (final domain in stevenBlackDomains['thai_asian_sites']!) {
      test('check Thai gambling domain: $domain', () {
        final url = 'https://$domain';
        final result = _testLoader.isGambling(url);
        if (result) detected++;
        // Log for analysis — ไม่ fail เพราะบางเว็บต้องการ AI detection
        // ignore: avoid_print
        print(result
            ? '✅ CAUGHT: $domain'
            : '⚠️ MISSED (needs AI): $domain');
      });
    }

    // ต้องจับได้อย่างน้อย 50% ด้วย keyword/regex alone
    test('detection rate for Thai sites should be >= 50%', () {
      // Re-calculate here since test() runs each test independently
      int count = 0;
      for (final domain in stevenBlackDomains['thai_asian_sites']!) {
        if (_testLoader.isGambling('https://$domain')) count++;
      }
      final rate = (count / total * 100).round();
      // ignore: avoid_print
      print('📊 Thai/Asian detection rate: $count/$total ($rate%)');
      expect(count, greaterThanOrEqualTo((total * 0.5).round()),
          reason: 'At least 50% of Thai gambling sites should be caught');
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // Group 4: International Gambling Sites
  // ════════════════════════════════════════════════════════════════════
  group('🌍 International Gambling Sites', () {
    for (final domain in stevenBlackDomains['international_sites']!) {
      test('check international gambling domain: $domain', () {
        final url = 'https://$domain';
        final result = _testLoader.isGambling(url);
        // ignore: avoid_print
        print(result
            ? '✅ CAUGHT: $domain'
            : '⚠️ MISSED (needs AI): $domain');
      });
    }

    test('detection rate for international sites should be >= 50%', () {
      int count = 0;
      final sites = stevenBlackDomains['international_sites']!;
      for (final domain in sites) {
        if (_testLoader.isGambling('https://$domain')) count++;
      }
      final rate = (count / sites.length * 100).round();
      // ignore: avoid_print
      print('📊 International detection rate: $count/${sites.length} ($rate%)');
      expect(count, greaterThanOrEqualTo((sites.length * 0.5).round()),
          reason: 'At least 50% of international gambling sites should be caught');
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // Group 5: False Positive Test — เว็บปกติต้องไม่ถูกบล็อค
  // ════════════════════════════════════════════════════════════════════
  group('✅ False Positive Prevention (Safe Sites)', () {
    for (final domain in safeWebsites) {
      test('should NOT block safe website: $domain', () {
        final url = 'https://www.$domain';
        expect(
          _testLoader.isGambling(url),
          isFalse,
          reason: '$domain should NOT be detected as gambling',
        );
      });
    }
  });

  // ════════════════════════════════════════════════════════════════════
  // Group 6: Edge Cases
  // ════════════════════════════════════════════════════════════════════
  group('🧪 Edge Cases', () {
    test('should handle empty URL', () {
      expect(_testLoader.isGambling(''), isFalse);
    });

    test('should handle URL with query params containing gambling keywords', () {
      // ค้นหาคำว่า ufabet ใน Google ต้องไม่ block Google
      expect(
        _testLoader.isGambling('https://www.google.com/search?q=ufabet'),
        isTrue, // URL contains 'ufabet' → จะจับ (เพราะเช็คทั้ง URL)
        reason: 'URL containing gambling brand even in query should be caught',
      );
    });

    test('should handle subdomains', () {
      expect(_testLoader.isGambling('https://www.ufabet.com'), isTrue);
      expect(_testLoader.isGambling('https://m.ufabet.com'), isTrue);
      expect(_testLoader.isGambling('https://app.sbobet.com'), isTrue);
    });

    test('should handle URLs with paths', () {
      expect(
        _testLoader.isGambling('https://ufabet.com/slot/play'),
        isTrue,
      );
    });

    test('should be case insensitive', () {
      expect(_testLoader.isGambling('https://UFABET.COM'), isTrue);
      expect(_testLoader.isGambling('https://SbObeT.com'), isTrue);
    });

    test('should handle URLs with port numbers', () {
      expect(_testLoader.isGambling('https://ufabet.com:8080'), isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // Group 7: Coverage Summary
  // ════════════════════════════════════════════════════════════════════
  group('📊 Overall Coverage Summary', () {
    test('print overall detection statistics', () {
      int totalDomains = 0;
      int totalDetected = 0;
      final categoryResults = <String, String>{};

      for (final entry in stevenBlackDomains.entries) {
        int detected = 0;
        for (final domain in entry.value) {
          if (_testLoader.isGambling('https://$domain')) detected++;
        }
        totalDomains += entry.value.length;
        totalDetected += detected;
        final rate = (detected / entry.value.length * 100).round();
        categoryResults[entry.key] = '$detected/${entry.value.length} ($rate%)';
      }

      final overallRate = (totalDetected / totalDomains * 100).round();

      // ignore: avoid_print
      print('\n${'=' * 60}');
      // ignore: avoid_print
      print('📊 AEGIS Gambling Blocking — Coverage Report');
      // ignore: avoid_print
      print('${'=' * 60}');
      for (final entry in categoryResults.entries) {
        // ignore: avoid_print
        print('  ${entry.key}: ${entry.value}');
      }
      // ignore: avoid_print
      print('${'─' * 60}');
      // ignore: avoid_print
      print('  TOTAL: $totalDetected/$totalDomains ($overallRate%)');
      // ignore: avoid_print
      print('${'=' * 60}');
      // ignore: avoid_print
      print('  * Domains not caught by keywords need AI (Gemini) detection');
      // ignore: avoid_print
      print('  * Overall system detection with AI layer would be higher');
      // ignore: avoid_print
      print('${'=' * 60}\n');

      // ต้องจับได้อย่างน้อย 60% overall ด้วย keyword/regex
      expect(totalDetected, greaterThanOrEqualTo((totalDomains * 0.60).round()),
          reason: 'Overall detection rate should be >= 60%');
    });
  });
}

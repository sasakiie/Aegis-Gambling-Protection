// ============================================================================
// AEGIS Shield — Thai Gambling URL Dataset Test
// ============================================================================
// ทดสอบว่า AEGIS สามารถตรวจจับเว็บพนันไทยจากข้อมูลจริง 31 URL ได้หรือไม่
//
// Data source: รวบรวมจากผู้พัฒนา (real-world Thai gambling URLs)
//
// วิธีรัน:
//   flutter test test/thai_gambling_url_test.dart
// ============================================================================

import 'package:flutter_test/flutter_test.dart';

// ============================================================================
// Standalone KeywordLoader สำหรับ Unit Test
// ============================================================================
class TestKeywordLoader {
  final List<String> brands;
  final List<RegExp> compiledPatterns;
  final List<String> normalizedBrands;

  TestKeywordLoader({
    required this.brands,
    required List<String> urlRegexPatterns,
  }) : compiledPatterns = urlRegexPatterns
           .map((p) {
             try {
               return RegExp(p, caseSensitive: false);
             } catch (e) {
               return null;
             }
           })
           .whereType<RegExp>()
           .toList(),
       normalizedBrands = brands
           .map((b) => b.toLowerCase().replaceAll(RegExp(r'[\s\-_]'), ''))
           .toList();

  bool isGambling(String url) {
    final lower = url.toLowerCase();
    final normalized = lower.replaceAll(RegExp(r'[\s\-_]'), '');
    for (final brand in brands) {
      if (lower.contains(brand)) return true;
    }
    for (final brand in normalizedBrands) {
      if (brand.isNotEmpty && normalized.contains(brand)) return true;
    }
    for (final pattern in compiledPatterns) {
      if (pattern.hasMatch(lower)) return true;
      if (pattern.hasMatch(normalized)) return true;
    }
    return false;
  }
}

// ============================================================================
// Keywords ตรงตาม gambling_keywords.json ล่าสุด
// ============================================================================
final _testLoader = TestKeywordLoader(
  brands: [
    // Thai brands (original)
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
    // International brands
    'pokerstars', '888casino', 'bet365', 'betfair',
    'jackpotcity', 'spincasino', 'zodiac casino',
    'bitstarz', 'ignition casino', 'betano',
    'wazamba', 'unibet', 'ladbrokes',
    'paddy power', 'party poker', 'fanduel',
    'betmgm', 'playojo',
    'chumba casino', 'luckyland slots', 'high5casino',
    'pulsz', 'funzpoints',
    '777casino', 'admiral casino',
    'brango casino', 'bizzo casino', 'comeon casino',
    'nine casino', 'mystake',
    'ice casino', 'bwin', 'slots of vegas',
    'casino classic', 'ruby fortune', 'meritking',
    'skyvegas', 'skybet',
    '1xbet', '22bet', 'mostbet', 'pin-up casino',
    'vulkan vegas', '1win', 'melbet',
    // NEW: Thai brands from user dataset
    'tgabet', 'tga69', 'tga1pro', 'play-tga',
    'meowsung',
    'boston777',
    'fafa168', 'fafa456', 'fafa191',
    'dkk789',
    'bplay666', 'bplay999',
    'pgbet888', 'pgbet',
    'mahagame',
    '1xlite',
    'sexy365bet',
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
    r'(?:slot|bet|game|play|win|vip|pro|club)[\-_]?\d+',
    r'\d+(?:slot|bet|game|casino|play|win|vip|club|live|vnd|lottery)',
    r'[a-z0-9]*888[a-z0-9]*\.(?:com|net|bet|co|tv|pro)',
    r'[a-z0-9]*88[a-z0-9]*\.(?:com|net|club|vip|pro|bet|tv|win)',
    r'[a-z0-9]*bet\.(?:com|net|org|asia|cc|uk|us|win|fun|life|mobi|pro)',
    r'[a-z0-9]+win\d*\.(?:com|net|org|pro|mobi|cool|wtf)',
    r'(?:^|\.)888[a-z]?\.(?:com|net|bet|co|tv|pro|win)',
    r'\d+win\.(?:com|net|pro|vip|bet|co|win)',
    r'\d+[a-z]?bet\.(?:com|net|pro|vip|co|win)',
    r'\d+lottery\.(?:com|net|pro|vip)',
    r'casino\d+\.(?:com|net|pro|vip|win)',
    r'[a-z]{2,5}88\.(?:com|net|co|vip|club|win|pro)',
    r'[a-z]{2,5}789\.(?:com|net|co|club|vip)',
    r'[a-z]{1,4}\d{2,3}\.(?:club|win|vin|vip|asia|social|cc|fun)',
    r'\w+\.casino',
    r'\w+\.bet',
    r'\w+\.poker',
    r'\w+\.slots',
    // NEW: Thai patterns from user dataset
    r'tga[\-_]?\w+',
    r'fafa\d+',
    r'mahagame\d+',
    r'boston\d+',
    r'dkk\d+',
    r'bplay\d+',
    r'1xlite',
    r'sexy\d*bet',
  ],
);

// ============================================================================
// Thai Gambling URL Dataset (31 URLs จากผู้พัฒนา)
// ============================================================================
const List<Map<String, String>> thaiGamblingUrls = [
  {'url': 'https://sexy365bet.net/', 'brand': 'sexy365bet'},
  {'url': 'https://mahagame66.com/', 'brand': 'mahagame'},
  {'url': 'https://brazil999b.cc/', 'brand': 'brazil999'},
  {'url': 'https://lockdown168q.com/', 'brand': 'lockdown168'},
  {'url': 'https://kingdom66p.com/', 'brand': 'kingdom66'},
  {'url': 'https://www.ssgame666i.com/', 'brand': 'ssgame666'},
  {'url': 'https://lotto77l.com/', 'brand': 'lotto77'},
  {
    'url': 'https://sexygame1688c-aff.com/U1gxNjg4MTA3NDAzMjI=',
    'brand': 'sexygame1688',
  },
  {'url': 'https://1688sagame4.com/', 'brand': 'sagame'},
  {'url': 'https://ufac4w.com/', 'brand': 'ufac4'},
  {'url': 'https://ufa191p.com/', 'brand': 'ufa191'},
  {'url': 'https://ufafat15.com/', 'brand': 'ufafat'},
  {'url': 'https://ufazeed18.com/', 'brand': 'ufazeed'},
  {'url': 'https://ufabomb2.com/', 'brand': 'ufabomb'},
  {'url': 'https://sagame66r.com/', 'brand': 'sagame'},
  {'url': 'https://boston777i.com/', 'brand': 'boston777'},
  {'url': 'https://meowsung.com/', 'brand': 'meowsung'},
  {'url': 'https://member.tgabetu.com/login', 'brand': 'tgabet'},
  {'url': 'https://www.tgabet95.io/login', 'brand': 'tgabet'},
  {'url': 'https://tga69-play.com/', 'brand': 'tga69'},
  {'url': 'https://play-tga.com/', 'brand': 'play-tga'},
  {'url': 'https://tgabet.at/login/', 'brand': 'tgabet'},
  {'url': 'https://tga-auto54.com', 'brand': 'tga (regex)'},
  {'url': 'https://tga1pro.com/login', 'brand': 'tga1pro'},
  {'url': 'https://www.bet365.com/#/HO/', 'brand': 'bet365'},
  {'url': 'https://1xlite-613210.top/en', 'brand': '1xlite'},
  {
    'url': 'https://app.dkk789.com/?prefix=dkk789&action=register',
    'brand': 'dkk789',
  },
  {'url': 'https://m.fafa168bs.com/th/register', 'brand': 'fafa168'},
  {'url': 'https://bplay666.me/?action=register', 'brand': 'bplay666'},
  {'url': 'https://fafa456bht.com/th/register', 'brand': 'fafa456'},
  {'url': 'https://pgbet888x.com/?rc=dj2222', 'brand': 'pgbet'},
];

// ============================================================================
// TEST SUITE
// ============================================================================
void main() {
  group('🇹🇭 Thai Gambling URL Dataset Test (31 URLs)', () {
    for (final entry in thaiGamblingUrls) {
      test(
        'should block: ${entry['brand']} → ${Uri.parse(entry['url']!).host}',
        () {
          expect(
            _testLoader.isGambling(entry['url']!),
            isTrue,
            reason:
                '${entry['url']} (brand: ${entry['brand']}) should be detected',
          );
        },
      );
    }

    test('📊 Overall detection rate should be 100%', () {
      int detected = 0;
      final List<String> missed = [];

      for (final entry in thaiGamblingUrls) {
        if (_testLoader.isGambling(entry['url']!)) {
          detected++;
        } else {
          missed.add('${entry['brand']}: ${entry['url']}');
        }
      }

      final rate = (detected / thaiGamblingUrls.length * 100).round();

      // ignore: avoid_print
      print('\n${'=' * 60}');
      // ignore: avoid_print
      print('📊 Thai Gambling URL Dataset — Detection Report');
      // ignore: avoid_print
      print('${'=' * 60}');
      // ignore: avoid_print
      print('  Detected: $detected/${thaiGamblingUrls.length} ($rate%)');

      if (missed.isNotEmpty) {
        // ignore: avoid_print
        print('  ❌ MISSED:');
        for (final m in missed) {
          // ignore: avoid_print
          print('    - $m');
        }
      }

      // ignore: avoid_print
      print('${'=' * 60}\n');

      expect(
        detected,
        equals(thaiGamblingUrls.length),
        reason: 'ALL Thai gambling URLs must be detected (100%)',
      );
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // False Positive Test — เว็บปลอดภัยต้องไม่ถูกบล็อค
  // ════════════════════════════════════════════════════════════════════
  group('✅ False Positive Prevention', () {
    const safeWebsites = [
      'https://www.google.com',
      'https://www.thairath.co.th',
      'https://www.sanook.com',
      'https://www.pantip.com',
      'https://www.facebook.com',
      'https://www.youtube.com',
      'https://www.github.com',
      'https://www.lazada.co.th',
      'https://www.shopee.co.th',
      'https://www.agoda.com',
      'https://www.kbank.com',
      'https://www.bangkokpost.com',
      'https://www.dailynews.co.th',
      'https://www.matichon.co.th',
      'https://www.ch3thailand.com',
      'https://sport.trueid.net/',
      'https://www.siamsport.co.th/',
      'https://www.tigerthai.com/',
    ];

    for (final url in safeWebsites) {
      test('should NOT block: ${Uri.parse(url).host}', () {
        expect(
          _testLoader.isGambling(url),
          isFalse,
          reason: '$url should NOT be detected as gambling',
        );
      });
    }
  });
}

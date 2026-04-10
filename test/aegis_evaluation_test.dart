// ============================================================================
// AEGIS Shield — Full-System Statistical Evaluation Test
// ============================================================================
// ทดสอบระบบตรวจจับเว็บพนันของ AEGIS ครบทุก Layer:
//
//   Layer 1: Pre-filter       (Brand + Regex — ใช้ KeywordLoader จริง)
//   Layer 2: VPN DNS Blocklist (Exact + Keyword — copy จาก MyVpnService.kt
//                               เพราะ Kotlin class ไม่สามารถ import เข้า Dart ได้)
//   Layer 3: Local Scoring     (7 หมวด — ใช้ KeywordLoader จริง)
//   Layer 4: Gemini AI         (จำลอง — ไม่สามารถเรียก API ใน unit test)
//
// วิธีเพิ่ม URL ทดสอบ:
//   1. เว็บพนัน     → เพิ่มใน gamblingUrls
//   2. เว็บปลอดภัย  → เพิ่มใน safeUrls
//
// วิธีรัน:
//   flutter test test/aegis_evaluation_test.dart
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:aegis_prog/controllers/keyword_loader.dart'; // ← import จริงจาก project (MVC path)

// ============================================================================
// Data Structures
// ============================================================================
enum Label { gambling, safe }

class TestUrl {
  final String url;
  final Label actualLabel;
  final String note;
  const TestUrl(this.url, this.actualLabel, [this.note = '']);
}

class LayerResult {
  final bool blocked;
  final String layer;
  final String reason;
  const LayerResult(this.blocked, this.layer, this.reason);
}

class FullSystemResult {
  final bool blocked;
  final List<LayerResult> layerResults;
  final String decidingLayer;
  final String reason;

  const FullSystemResult({
    required this.blocked,
    required this.layerResults,
    required this.decidingLayer,
    required this.reason,
  });
}

// ============================================================================
// AegisFullSystem — ใช้ KeywordLoader จริง + VPN Blocklist
// ============================================================================
class AegisFullSystem {
  final KeywordLoader keywords;
  late final List<RegExp> _compiledPatterns;

  // ── Layer 2: VPN DNS Blocklist ──
  // หมายเหตุ: ต้อง hardcode เพราะ MyVpnService.kt เป็น Kotlin
  // Dart ไม่สามารถ import class ข้ามภาษาได้ (ใช้ Platform Channel เท่านั้น)
  static const vpnBlockedDomains = <String>{
    'ufabet.com', 'ufa365.com', 'ufa888.com', 'ufa168.com', 'ufa191.com',
    'ufazeed.com', 'ufabomb.com',
    'pgslot.com', 'slotxo.com', 'superslot.com',
    'sagaming.com', 'sexygame.com', 'sexybaccarat.com',
    'betflik.com', 'betflix.com',
    'joker123.com', 'jokergaming.com',
    'sbobet.com', 'gclub.com', 'lsm99.com',
    'ole777.com', 'fun88.com', 'w88.com',
    'dafabet.com', 'happyluke.com', 'empire777.com',
    'lucabet.com', 'foxz168.com', 'databet.com',
    'mafia88.com', 'biobet.com', 'ruay.com', 'ambbet.com',
    'live22.com', 'mega888.com', 'kiss918.com',
    'ssgame666.com', 'ssgame666h.com', 'ssgame66.com',
    'panama888.com', 'panama999.com',
    'lockdown168.com', 'lockdown888.com',
    'brazil99.com', 'brazil999.com',
    'kingdom66.com', 'kingdom666.com',
  };

  static const vpnBlockedKeywords = <String>[
    'ufabet', 'ufazeed', 'ufabomb', 'ufac4', 'ufafat',
    'pgslot', 'slotxo', 'superslot', 'slotgame',
    'sagaming', 'sexygame', 'sexybaccarat',
    'betflik', 'betflix', 'sbobet', 'gclub',
    'ambbet', 'lucabet', 'databet', 'biobet',
    'ssgame66', 'ssgame666',
    'panama888', 'panama999',
    'lockdown168', 'lockdown888',
    'kingdom66', 'kingdom666',
    'mafia88', 'joker123',
  ];

  AegisFullSystem(this.keywords) {
    _compiledPatterns = keywords.urlRegexPatterns
        .map((p) {
          try {
            return RegExp(p, caseSensitive: false);
          } catch (_) {
            return null;
          }
        })
        .whereType<RegExp>()
        .toList();
  }

  /// รันทุก Layer แล้วรวมผลลัพธ์
  FullSystemResult evaluate(String url) {
    final results = <LayerResult>[];

    // ── Layer 1: Pre-filter (ใช้ KeywordLoader.brands + regex จริง) ──
    final l1 = _checkPreFilter(url);
    results.add(l1);
    if (l1.blocked) {
      return FullSystemResult(
        blocked: true, layerResults: results,
        decidingLayer: l1.layer, reason: l1.reason,
      );
    }

    // ── Layer 2: VPN DNS Blocklist ──
    final l2 = _checkVpnDns(url);
    results.add(l2);
    if (l2.blocked) {
      return FullSystemResult(
        blocked: true, layerResults: results,
        decidingLayer: l2.layer, reason: l2.reason,
      );
    }

    // ── Layer 3: Local Scoring (ใช้ KeywordLoader ทุกหมวดจริง) ──
    final l3 = _checkLocalScoring(url);
    results.add(l3);
    if (l3.blocked) {
      return FullSystemResult(
        blocked: true, layerResults: results,
        decidingLayer: l3.layer, reason: l3.reason,
      );
    }

    // ── Layer 4: AI (ไม่สามารถเรียก Gemini API ใน unit test) ──
    results.add(const LayerResult(
      false, 'Layer 4: Gemini AI',
      'ต้องส่ง screenshot + text ให้ Gemini AI (ไม่สามารถจำลองใน unit test)',
    ));

    return FullSystemResult(
      blocked: false, layerResults: results,
      decidingLayer: 'ไม่มี Layer ใดจับได้ → ต้องพึ่ง AI',
      reason: 'ผ่าน Pre-filter, VPN, Local Scoring → ส่ง Gemini AI ตัดสิน',
    );
  }

  // ── Layer 1: Pre-filter ──
  LayerResult _checkPreFilter(String url) {
    final lower = url.toLowerCase();

    // ใช้ brands จาก KeywordLoader จริง
    for (final brand in keywords.brands) {
      if (lower.contains(brand)) {
        return LayerResult(true, 'Layer 1: Pre-filter',
            'Brand match: "$brand" พบใน URL');
      }
    }

    // ใช้ regex จาก KeywordLoader จริง
    for (final pattern in _compiledPatterns) {
      if (pattern.hasMatch(lower)) {
        return LayerResult(true, 'Layer 1: Pre-filter',
            'Regex match: "${pattern.pattern}"');
      }
    }

    return const LayerResult(false, 'Layer 1: Pre-filter', 'ไม่ตรง brand/regex');
  }

  // ── Layer 2: VPN DNS Blocklist (hardcoded จาก MyVpnService.kt) ──
  LayerResult _checkVpnDns(String url) {
    final domain = _extractDomain(url);

    if (vpnBlockedDomains.contains(domain)) {
      return LayerResult(true, 'Layer 2: VPN DNS',
          'Exact match: "$domain" อยู่ใน blocklist');
    }

    for (final blocked in vpnBlockedDomains) {
      if (domain.endsWith('.$blocked')) {
        return LayerResult(true, 'Layer 2: VPN DNS',
            'Subdomain match: "$domain" → ".$blocked"');
      }
    }

    for (final keyword in vpnBlockedKeywords) {
      if (domain.contains(keyword)) {
        return LayerResult(true, 'Layer 2: VPN DNS',
            'Keyword match: "$keyword" พบใน "$domain"');
      }
    }

    return const LayerResult(false, 'Layer 2: VPN DNS', 'ไม่อยู่ใน DNS blocklist');
  }

  // ── Layer 3: Local Scoring (ใช้ KeywordLoader ทุกหมวดจริง) ──
  LayerResult _checkLocalScoring(String url) {
    final lower = url.toLowerCase();
    int score = 0;
    final matches = <String>[];

    // 1. Game Providers (จาก keywords.gameProviders จริง)
    int providerHits = 0;
    for (final p in keywords.gameProviders) {
      if (lower.contains(p)) providerHits++;
    }
    if (providerHits >= 3) {
      score += 3; matches.add('providers($providerHits)');
    } else if (providerHits >= 1) {
      score += providerHits; matches.add('providers($providerHits)');
    }

    // 2. Game Types (จาก keywords.gameTypes จริง)
    for (final t in keywords.gameTypes) {
      if (lower.contains(t)) {
        score += 1; matches.add('type:$t'); break;
      }
    }

    // 3. Financial Terms (จาก keywords.financialTerms จริง)
    for (final f in keywords.financialTerms) {
      if (lower.contains(f)) {
        score += 2; matches.add('financial:$f'); break;
      }
    }

    // 4. URL Indicators (จาก keywords.urlIndicators จริง)
    for (final d in keywords.urlIndicators) {
      if (lower.contains(d)) {
        score += 1; matches.add('url:$d'); break;
      }
    }

    // 5. Game Names (จาก keywords.gameNames จริง)
    int gameHits = 0;
    for (final g in keywords.gameNames) {
      if (lower.contains(g)) gameHits++;
    }
    if (gameHits >= 1) {
      score += 2; matches.add('games($gameHits)');
    }

    // 6. Generic Gambling Signals (จาก keywords.genericGamblingSignals จริง)
    int signalHits = 0;
    for (final s in keywords.genericGamblingSignals) {
      if (lower.contains(s)) signalHits++;
    }
    if (signalHits >= 3) {
      score += 3; matches.add('signals($signalHits)');
    } else if (signalHits >= 1) {
      score += signalHits; matches.add('signals($signalHits)');
    }

    if (score >= 4) {
      return LayerResult(true, 'Layer 3: Local Scoring',
          'Score=$score (≥4 = gambling) [${matches.join(", ")}]');
    }

    return LayerResult(false, 'Layer 3: Local Scoring',
        score > 0
            ? 'Score=$score (<4 = gray zone) [${matches.join(", ")}]'
            : 'Score=0 (ไม่พบ keyword ใดๆ)');
  }

  String _extractDomain(String url) {
    try {
      return Uri.parse(url).host.replaceFirst(RegExp(r'^www\.'), '');
    } catch (_) {
      return url;
    }
  }
}

// ╔════════════════════════════════════════════════════════════════════════════╗
// ║  ⬇️ เพิ่ม URL ทดสอบที่นี่ ⬇️                                             ║
// ╚════════════════════════════════════════════════════════════════════════════╝

// ──────────────────────────────────────────────────────────────────────────────
// 🎰 เว็บพนัน (Ground Truth = gambling)
// ──────────────────────────────────────────────────────────────────────────────
const gamblingUrls = <TestUrl>[
  // ── Thai brands (31 URLs จาก dataset) ──
  TestUrl('https://sexy365bet.net/', Label.gambling, 'sexy365bet'),
  TestUrl('https://mahagame66.com/', Label.gambling, 'mahagame'),
  TestUrl('https://brazil999b.cc/', Label.gambling, 'brazil999'),
  TestUrl('https://lockdown168q.com/', Label.gambling, 'lockdown168'),
  TestUrl('https://kingdom66p.com/', Label.gambling, 'kingdom66'),
  TestUrl('https://www.ssgame666i.com/', Label.gambling, 'ssgame666'),
  TestUrl('https://lotto77l.com/', Label.gambling, 'lotto77'),
  TestUrl('https://sexygame1688c-aff.com/', Label.gambling, 'sexygame1688'),
  TestUrl('https://1688sagame4.com/', Label.gambling, 'sagame'),
  TestUrl('https://ufac4w.com/', Label.gambling, 'ufac4'),
  TestUrl('https://ufa191p.com/', Label.gambling, 'ufa191'),
  TestUrl('https://ufafat15.com/', Label.gambling, 'ufafat'),
  TestUrl('https://ufazeed18.com/', Label.gambling, 'ufazeed'),
  TestUrl('https://ufabomb2.com/', Label.gambling, 'ufabomb'),
  TestUrl('https://sagame66r.com/', Label.gambling, 'sagame'),
  TestUrl('https://boston777i.com/', Label.gambling, 'boston777'),
  TestUrl('https://meowsung.com/', Label.gambling, 'meowsung'),
  TestUrl('https://member.tgabetu.com/login', Label.gambling, 'tgabet'),
  TestUrl('https://www.tgabet95.io/login', Label.gambling, 'tgabet'),
  TestUrl('https://tga69-play.com/', Label.gambling, 'tga69'),
  TestUrl('https://play-tga.com/', Label.gambling, 'play-tga'),
  TestUrl('https://tgabet.at/login/', Label.gambling, 'tgabet'),
  TestUrl('https://tga-auto54.com', Label.gambling, 'tga (regex)'),
  TestUrl('https://tga1pro.com/login', Label.gambling, 'tga1pro'),
  TestUrl('https://www.bet365.com/', Label.gambling, 'bet365'),
  TestUrl('https://1xlite-613210.top/en', Label.gambling, '1xlite'),
  TestUrl('https://app.dkk789.com/', Label.gambling, 'dkk789'),
  TestUrl('https://m.fafa168bs.com/th/register', Label.gambling, 'fafa168'),
  TestUrl('https://bplay666.me/', Label.gambling, 'bplay666'),
  TestUrl('https://fafa456bht.com/', Label.gambling, 'fafa456'),
  TestUrl('https://pgbet888x.com/', Label.gambling, 'pgbet'),

  // ── International brands ──
  TestUrl('https://www.pokerstars.com/', Label.gambling, 'pokerstars'),
  TestUrl('https://www.sbobet.com/', Label.gambling, 'sbobet'),
  TestUrl('https://www.unibet.com/', Label.gambling, 'unibet'),
  TestUrl('https://www.888casino.com/', Label.gambling, '888casino'),
  TestUrl('https://www.betfair.com/', Label.gambling, 'betfair'),
  TestUrl('https://www.dafabet.com/', Label.gambling, 'dafabet'),
  TestUrl('https://www.fun88.com/', Label.gambling, 'fun88'),
  TestUrl('https://www.w88.com/', Label.gambling, 'w88'),

  // ── StevenBlack ──
  TestUrl('https://789bet.com/', Label.gambling, 'StevenBlack'),
  TestUrl('https://slot88.com/', Label.gambling, 'StevenBlack'),
  TestUrl('https://009.casino/', Label.gambling, '.casino TLD'),
  TestUrl('https://88gobet.com/', Label.gambling, 'StevenBlack'),

  // ─── เพิ่ม URL พนันใหม่ด้านล่างนี้ ───
  TestUrl('https://lsm919v2.com/register/', Label.gambling, 'new gambling URL 1'),
  TestUrl('https://www.juad888s.com/', Label.gambling, 'new gambling URL 2'),
  TestUrl('https://ufagool.com/', Label.gambling, 'new gambling URL 3'),
  TestUrl('https://debet.vip/th?a=2ca27b85c004a55d6052a41d0e7b96ed&utm_source=javwowcom&utm_medium=floatingleft-95x170&utm_campaign=cpd&utm_term=sex', Label.gambling, 'new gambling URL 4'),
  TestUrl('https://pgk44b.org/', Label.gambling, 'new gambling URL 5'),
  TestUrl('https://slotgame6666c.co/', Label.gambling, 'new gambling URL 6'),
  TestUrl('https://pgw44.net/', Label.gambling, 'new gambling URL 7'),
  TestUrl('https://ufaza.com/', Label.gambling, 'new gambling URL 8'),
  TestUrl('https://ufanance17.com/', Label.gambling, 'new gambling URL 9'),
  TestUrl('https://sexygame992h.com/', Label.gambling, 'new gambling URL 10'),
  TestUrl('https://www.heng666.fun/?pid=Javwow', Label.gambling, 'new gambling URL 11'),
  TestUrl('https://550ww.pro/', Label.gambling, 'new gambling URL 12'),
  TestUrl('https://youthworkresource.com/', Label.gambling, 'new gambling URL 13'),
  TestUrl('https://play.ufa-11k.pro/', Label.gambling, 'new gambling URL 14'),
  TestUrl('https://huaypung5.com/login', Label.gambling, 'new gambling URL 15'),
  TestUrl('https://sbobet888m.win/', Label.gambling, 'new gambling URL 16'),
  TestUrl('https://sbobetone.co/', Label.gambling, 'new gambling URL 17'),
  TestUrl('https://baccarat888e.com/', Label.gambling, 'new gambling URL 18'),
  TestUrl('https://ufanice2.com/', Label.gambling, 'new gambling URL 19'),
  TestUrl('https://rb289.online/home', Label.gambling, 'new gambling URL 20'),
];

// ──────────────────────────────────────────────────────────────────────────────
// ✅ เว็บปลอดภัย (Ground Truth = safe)
// ──────────────────────────────────────────────────────────────────────────────
const safeUrls = <TestUrl>[
  TestUrl('https://www.thairath.co.th', Label.safe, 'ข่าว'),
  TestUrl('https://www.sanook.com', Label.safe, 'ข่าว'),
  TestUrl('https://www.pantip.com', Label.safe, 'กระทู้'),
  TestUrl('https://www.bangkokpost.com', Label.safe, 'ข่าว EN'),
  TestUrl('https://www.dailynews.co.th', Label.safe, 'ข่าว'),
  TestUrl('https://www.matichon.co.th', Label.safe, 'ข่าว'),
  TestUrl('https://www.ch3thailand.com', Label.safe, 'TV'),
  TestUrl('https://www.khaosod.co.th', Label.safe, 'ข่าว'),
  TestUrl('https://sport.trueid.net/', Label.safe, 'กีฬา'),
  TestUrl('https://www.siamsport.co.th/', Label.safe, 'กีฬา'),
  TestUrl('https://www.google.com', Label.safe, 'ค้นหา'),
  TestUrl('https://www.facebook.com', Label.safe, 'โซเชียล'),
  TestUrl('https://www.youtube.com', Label.safe, 'วิดีโอ'),
  TestUrl('https://www.instagram.com', Label.safe, 'โซเชียล'),
  TestUrl('https://www.tiktok.com', Label.safe, 'โซเชียล'),
  TestUrl('https://www.twitter.com', Label.safe, 'โซเชียล'),
  TestUrl('https://line.me', Label.safe, 'แชท'),
  TestUrl('https://www.lazada.co.th', Label.safe, 'ช้อปปิ้ง'),
  TestUrl('https://www.shopee.co.th', Label.safe, 'ช้อปปิ้ง'),
  TestUrl('https://www.agoda.com', Label.safe, 'ท่องเที่ยว'),
  TestUrl('https://www.kbank.com', Label.safe, 'ธนาคาร'),
  TestUrl('https://www.scb.co.th', Label.safe, 'ธนาคาร'),
  TestUrl('https://www.github.com', Label.safe, 'เขียนโค้ด'),
  TestUrl('https://www.stackoverflow.com', Label.safe, 'เขียนโค้ด'),
  TestUrl('https://www.wikipedia.org', Label.safe, 'สารานุกรม'),
  TestUrl('https://www.tigerthai.com/', Label.safe, 'เว็บกีฬา'),
  TestUrl('https://www.booking.com', Label.safe, 'จองโรงแรม'),
  TestUrl('https://www.grab.com', Label.safe, 'เรียกรถ'),
  TestUrl('https://www.bbc.com', Label.safe, 'ข่าวต่างประเทศ'),
  TestUrl('https://www.medium.com', Label.safe, 'บทความ'),

  // ─── เพิ่ม URL ปลอดภัยใหม่ด้านล่างนี้ ───
];

// ============================================================================
// TEST SUITE
// ============================================================================

void main() {
  // ── Setup: โหลด KeywordLoader จริงจาก gambling_keywords.json ──
  late AegisFullSystem system;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final kw = KeywordLoader();
    await kw.load(); // โหลด gambling_keywords.json จริง
    system = AegisFullSystem(kw);

    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('📦 KeywordLoader โหลดจาก gambling_keywords.json สำเร็จ:');
    // ignore: avoid_print
    print('   Brands: ${kw.brandCount}, Regex: ${kw.patternCount}, '
        'Providers: ${kw.providerCount}, GameTypes: ${kw.gameTypeCount}, '
        'Signals: ${kw.genericSignalCount}');
    // ignore: avoid_print
    print('');
  });

  final allUrls = [...gamblingUrls, ...safeUrls];

  // ─── ส่วนที่ 1: ทดสอบทีละ URL พร้อมแสดงเหตุผล ───
  group('🔍 AEGIS Full-System Detection — Per-URL Results', () {
    for (final testUrl in allUrls) {
      final icon = testUrl.actualLabel == Label.gambling ? '🎰' : '✅';
      test('$icon ${testUrl.note}: ${_shortUrl(testUrl.url)}', () {
        final result = system.evaluate(testUrl.url);
        final predicted = result.blocked ? Label.gambling : Label.safe;
        final match = predicted == testUrl.actualLabel ? '✅' : '❌';

        // ignore: avoid_print
        print(
          '$match ${_shortUrl(testUrl.url)} '
          '| จริง: ${testUrl.actualLabel.name} '
          '| AEGIS: ${predicted.name} '
          '| ${result.decidingLayer} '
          '| ${result.reason}',
        );
      });
    }
  });

  // ─── ส่วนที่ 2: Per-Layer Coverage ───
  group('📋 Per-Layer Coverage Analysis', () {
    test('แสดงว่าแต่ละ Layer จับ URL พนันได้กี่ตัว', () {
      int l1 = 0, l2 = 0, l3 = 0, ai = 0;

      for (final testUrl in gamblingUrls) {
        final result = system.evaluate(testUrl.url);
        if (result.blocked) {
          if (result.decidingLayer.contains('1')) l1++;
          else if (result.decidingLayer.contains('2')) l2++;
          else if (result.decidingLayer.contains('3')) l3++;
        } else {
          ai++;
        }
      }

      // ignore: avoid_print
      print('\n${'═' * 60}');
      // ignore: avoid_print
      print('  📋 Per-Layer Gambling URL Coverage');
      // ignore: avoid_print
      print('${'═' * 60}');
      // ignore: avoid_print
      print('  Layer 1 (Pre-filter):    จับได้ $l1/${gamblingUrls.length} URLs');
      // ignore: avoid_print
      print('  Layer 2 (VPN DNS):       จับเพิ่มได้ $l2 URLs');
      // ignore: avoid_print
      print('  Layer 3 (Local Scoring): จับเพิ่มได้ $l3 URLs');
      // ignore: avoid_print
      print('  Layer 4 (Gemini AI):     ต้องพึ่ง AI อีก $ai URLs');
      // ignore: avoid_print
      print('${'═' * 60}\n');
    });
  });

  // ─── ส่วนที่ 3: Precision / Recall / F1-Score ───
  group('📊 Statistical Evaluation (Full System)', () {
    test('Precision / Recall / F1-Score / Accuracy Report', () {
      int tp = 0, fp = 0, tn = 0, fn = 0;
      final fnList = <String>[];
      final fpList = <String>[];

      for (final testUrl in allUrls) {
        final result = system.evaluate(testUrl.url);
        final predicted = result.blocked ? Label.gambling : Label.safe;
        final actual = testUrl.actualLabel;

        if (actual == Label.gambling && predicted == Label.gambling) tp++;
        else if (actual == Label.safe && predicted == Label.gambling) {
          fp++;
          fpList.add('${testUrl.note}: ${_shortUrl(testUrl.url)} ← ${result.reason}');
        } else if (actual == Label.safe && predicted == Label.safe) tn++;
        else {
          fn++;
          fnList.add('${testUrl.note}: ${_shortUrl(testUrl.url)} ← ${result.reason}');
        }
      }

      final precision = tp + fp > 0 ? tp / (tp + fp) : 0.0;
      final recall = tp + fn > 0 ? tp / (tp + fn) : 0.0;
      final f1 = precision + recall > 0
          ? 2 * (precision * recall) / (precision + recall)
          : 0.0;
      final accuracy = allUrls.isNotEmpty ? (tp + tn) / allUrls.length : 0.0;

      // ignore: avoid_print
      print('\n${'═' * 70}');
      // ignore: avoid_print
      print('  📊 AEGIS Full-System — Statistical Evaluation Report');
      // ignore: avoid_print
      print('${'═' * 70}');
      // ignore: avoid_print
      print('');
      // ignore: avoid_print
      print('  📦 Dataset:');
      // ignore: avoid_print
      print('     Gambling URLs (Positive): ${gamblingUrls.length}');
      // ignore: avoid_print
      print('     Safe URLs (Negative):     ${safeUrls.length}');
      // ignore: avoid_print
      print('     Total:                    ${allUrls.length}');
      // ignore: avoid_print
      print('');
      // ignore: avoid_print
      print('  📋 Confusion Matrix:');
      // ignore: avoid_print
      print('     ┌────────────────┬──────────────┬──────────────┐');
      // ignore: avoid_print
      print('     │                │ Predicted:   │ Predicted:   │');
      // ignore: avoid_print
      print('     │                │ GAMBLING     │ SAFE         │');
      // ignore: avoid_print
      print('     ├────────────────┼──────────────┼──────────────┤');
      // ignore: avoid_print
      print('     │ Actual:        │              │              │');
      // ignore: avoid_print
      print('     │ GAMBLING       │  TP = ${tp.toString().padLeft(3)}   │  FN = ${fn.toString().padLeft(3)}   │');
      // ignore: avoid_print
      print('     ├────────────────┼──────────────┼──────────────┤');
      // ignore: avoid_print
      print('     │ Actual:        │              │              │');
      // ignore: avoid_print
      print('     │ SAFE           │  FP = ${fp.toString().padLeft(3)}   │  TN = ${tn.toString().padLeft(3)}   │');
      // ignore: avoid_print
      print('     └────────────────┴──────────────┴──────────────┘');
      // ignore: avoid_print
      print('');
      // ignore: avoid_print
      print('  📈 Metrics (Layers 1-3 รวมกัน, ไม่รวม AI):');
      // ignore: avoid_print
      print('     Precision : ${(precision * 100).toStringAsFixed(2)}%  (บล็อคแล้วถูกจริงกี่ %)');
      // ignore: avoid_print
      print('     Recall    : ${(recall * 100).toStringAsFixed(2)}%  (เว็บพนันจริงจับได้กี่ %)');
      // ignore: avoid_print
      print('     F1-Score  : ${(f1 * 100).toStringAsFixed(2)}%  (ค่าเฉลี่ยถ่วงน้ำหนัก)');
      // ignore: avoid_print
      print('     Accuracy  : ${(accuracy * 100).toStringAsFixed(2)}%  (ถูกต้องทั้งหมด)');
      // ignore: avoid_print
      print('');

      if (fnList.isNotEmpty) {
        // ignore: avoid_print
        print('  ❌ False Negatives (เว็บพนันที่หลุดทั้ง 3 Layers):');
        for (final item in fnList) {
          // ignore: avoid_print
          print('     - $item');
        }
        // ignore: avoid_print
        print('     💡 เว็บเหล่านี้จะถูก Gemini AI วิเคราะห์จาก screenshot + OCR');
        // ignore: avoid_print
        print('');
      }

      if (fpList.isNotEmpty) {
        // ignore: avoid_print
        print('  ⚠️ False Positives (เว็บปลอดภัยที่ถูกบล็อคผิด):');
        for (final item in fpList) {
          // ignore: avoid_print
          print('     - $item');
        }
        // ignore: avoid_print
        print('');
      }

      // ignore: avoid_print
      print('${'═' * 70}');
      // ignore: avoid_print
      print('  ℹ️  Layer 1: Pre-filter ← gambling_keywords.json (import จริง)');
      // ignore: avoid_print
      print('  ℹ️  Layer 2: VPN DNS   ← MyVpnService.kt (hardcode เพราะเป็น Kotlin)');
      // ignore: avoid_print
      print('  ℹ️  Layer 3: Scoring   ← gambling_keywords.json (import จริง)');
      // ignore: avoid_print
      print('  ℹ️  Layer 4: Gemini AI ← ไม่รวมในค่าข้างต้น');
      // ignore: avoid_print
      print('${'═' * 70}\n');

      // ── Assertions ──
      expect(precision, greaterThanOrEqualTo(0.90),
          reason: 'Precision ควร ≥ 90%');
      expect(recall, greaterThanOrEqualTo(0.80),
          reason: 'Recall ควร ≥ 80%');
      expect(f1, greaterThanOrEqualTo(0.85),
          reason: 'F1-Score ควร ≥ 85%');
      expect(fp, equals(0),
          reason: 'ไม่ควรมี False Positive');
    });
  });
}

String _shortUrl(String url) {
  try {
    return Uri.parse(url).host;
  } catch (_) {
    return url.length > 40 ? '${url.substring(0, 40)}...' : url;
  }
}

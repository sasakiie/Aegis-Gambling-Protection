// ============================================================================
// AEGIS Shield — controllers/detection_controller.dart
// ============================================================================
// 4-Layer Detection Logic — ย้ายจาก webview_screen.dart
// แก้ช่องโหว่ #4: return DetectionResult แทนการสั่ง Navigation โดยตรง
// แก้ปัญหาโค้ดซ้ำ: รวม _scoreContent + _analyzeContentLocally เป็นตัวเดียว
// ============================================================================

import 'package:flutter/material.dart';
import 'dart:typed_data';
import '../models/classification_result.dart';
import 'keyword_loader.dart';
import 'ad_removal_cache.dart';
import 'gemini_service.dart';
import 'ocr_service.dart';
import 'debug_logger.dart';

/// DetectionController — จัดการ 4-Layer Detection
/// คืน DetectionResult ให้ View ตัดสินใจ Navigation เอง
class DetectionController extends ChangeNotifier {
  final KeywordLoader _keywords = KeywordLoader();
  GeminiService? _geminiService;

  bool _isAnalyzing = false;
  bool get isAnalyzing => _isAnalyzing;

  /// Callback สำหรับส่ง log ไปแสดงบน UI
  void Function(String)? onLog;

  /// ตั้งค่า Gemini Service (เรียกตอน init)
  void initGeminiService(String apiKey, {void Function(String)? logCallback}) {
    onLog = logCallback;
    if (apiKey.isNotEmpty) {
      _geminiService = GeminiService(apiKey: apiKey, onLog: logCallback);
      _log('🤖 Gemini Vision AI: ACTIVE (gemini-2.0-flash)');
    } else {
      _log('ℹ️ Gemini API key ไม่พบ — ใช้เฉพาะ pre-filter');
    }
    _log(
      '📋 Pre-filter: โหลด ${_keywords.brandCount} brands, ${_keywords.patternCount} patterns',
    );
  }

  void _log(String message) {
    onLog?.call(message);
    // บันทึกลงไฟล์ debug log (admin only)
    DebugLogger.instance.detection(message);
  }

  /// ดึง domain จาก URL
  String extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      var host = uri.host.toLowerCase();
      if (host.startsWith('www.')) host = host.substring(4);
      return host;
    } catch (e) {
      return url.toLowerCase();
    }
  }

  /// Pre-filter check (synchronous)
  bool isDefinitelyGambling(String url) {
    return _keywords.isGambling(url);
  }

  bool _shouldBlockWholeSite(
    String url,
    String title,
    String content,
    int score, {
    double aiConfidence = 0.0,
    List<String> selectors = const [],
  }) {
    final lower = '$title\n$content'.toLowerCase();

    int gameTypeHits = 0;
    for (final term in _keywords.gameTypes) {
      if (lower.contains(term.toLowerCase())) {
        gameTypeHits++;
      }
    }

    int financialHits = 0;
    for (final term in _keywords.financialTerms) {
      if (lower.contains(term.toLowerCase())) {
        financialHits++;
      }
    }

    int genericHits = 0;
    for (final term in _keywords.genericGamblingSignals) {
      if (lower.contains(term.toLowerCase())) {
        genericHits++;
      }
    }

    int urlHits = 0;
    final urlLower = url.toLowerCase();
    for (final term in _keywords.urlIndicators) {
      if (urlLower.contains(term.toLowerCase())) {
        urlHits++;
      }
    }

    final looksLikeWholeSite =
        score >= 10 ||
        (score >= 8 && gameTypeHits >= 3) ||
        (gameTypeHits >= 4 && financialHits >= 1) ||
        (genericHits >= 2 && financialHits >= 1 && score >= 7) ||
        (aiConfidence >= 0.9 && score >= 7 && selectors.length <= 2) ||
        (urlHits >= 2 && gameTypeHits >= 3 && score >= 7);

    _log(
      '🧭 Whole-site check: score=$score gameTypes=$gameTypeHits financial=$financialHits generic=$genericHits urlHits=$urlHits selectors=${selectors.length} aiConfidence=${aiConfidence.toStringAsFixed(2)} => ${looksLikeWholeSite ? "block" : "sanitize"}',
    );

    return looksLikeWholeSite;
  }

  /// ══════════════════════════════════════════════════════════════════════
  /// checkUrl — 4-Layer Detection → คืน DetectionResult
  /// ══════════════════════════════════════════════════════════════════════
  Future<DetectionResult> checkUrl(
    String url, {
    String title = '',
    String snippet = '',
    Future<Uint8List?> Function()? captureScreenshot,
    bool forceAiRefresh = false,
  }) async {
    final domain = extractDomain(url);

    // ─── Layer 1: Smart Cache (Hive) ───
    if (!forceAiRefresh) {
      final cached = AdRemovalCache.getCache(domain);
      if (cached != null) {
        if (cached.isGambling && cached.selectors.isEmpty) {
          _log('⚠️ Hive Cache: $domain → gambling-only cache without selectors, re-evaluating live');
        } else {
          _log(
            cached.isGambling
                ? '⚡ Hive Cache: $domain → Gambling'
                : '⚡ Hive Cache: $domain → Safe (Injecting ${cached.selectors.length} selectors)',
          );
          return DetectionResult(
            verdict: cached.isGambling
                ? DetectionVerdict.sanitize
                : DetectionVerdict.safe,
            reason: 'Hive Cache (selectors: ${cached.selectors.length})',
            layer: 'Cache',
            selectors: cached.selectors,
          );
        }
      }
    }

    // ─── Layer 2: Pre-filter (gambling_keywords.json) ───
    if (isDefinitelyGambling(url)) {
      _log('🚫 Pre-filter: $domain → Known gambling brand');
      await AdRemovalCache.saveCache(
        domain: domain,
        selectors: [],
        isGambling: true,
      );
      return const DetectionResult(
        verdict: DetectionVerdict.blocked,
        reason: 'Known gambling brand (pre-filter)',
        layer: 'Pre-filter',
      );
    }

    // ─── Layer 3a: OCR + Deep Extraction → Local Scoring ───
    _isAnalyzing = true;
    notifyListeners();

    try {
      String ocrText = '';
      Uint8List? screenshot;

      if (captureScreenshot != null) {
        _log('📸 OCR: กำลังจับภาพหน้าจอ $domain ...');
        screenshot = await captureScreenshot();
        if (screenshot != null && screenshot.isNotEmpty) {
          _log('🔤 OCR: กำลังอ่าน text จากรูป ...');
          ocrText = await OcrService.instance.recognizeText(screenshot);
          if (ocrText.isNotEmpty) {
            _log('🔤 OCR: อ่านได้ ${ocrText.length} ตัวอักษร');
          } else {
            _log('🔤 OCR: ไม่พบ text ในรูป');
          }
        }
      }

      final combinedContent = '$snippet\nOCR_TEXT: $ocrText';
      final score = scoreContent(url, title, combinedContent);
      _log('📊 Hybrid Score: $score (threshold: ≥4 sanitize, 1-3 gray zone)');

      if (score >= 4) {
        final shouldBlockWholeSite = _shouldBlockWholeSite(
          url,
          title,
          combinedContent,
          score,
        );
        _log(
          shouldBlockWholeSite
              ? '🚫 Hybrid: $domain → whole-site gambling detected (score=$score, block page)'
              : '🧹 Hybrid: $domain → gambling-like content (score=$score, sanitize page)',
        );
        _isAnalyzing = false;
        notifyListeners();
        await AdRemovalCache.saveCache(
          domain: domain,
          selectors: [],
          isGambling: true,
        );
        return DetectionResult(
          verdict: shouldBlockWholeSite
              ? DetectionVerdict.blocked
              : DetectionVerdict.sanitize,
          reason: shouldBlockWholeSite
              ? 'Hybrid block: whole-site gambling score $score'
              : 'Hybrid sanitize: local score $score',
          layer: 'Local Scoring',
        );
      }

      // ─── Layer 3b: Gray zone → Gemini AI ───
      _log(
        score == 0
            ? '🔍 Score=0 (เว็บใหม่) → ส่ง Gemini AI ตรวจ 1 ครั้ง'
            : '🟡 Gray zone (score=$score) → ส่งให้ Gemini AI ตัดสิน',
      );

      if (_geminiService != null) {
        // Vision AI
        if (screenshot != null && screenshot.isNotEmpty) {
          _log('🤖 Vision AI: วิเคราะห์ภาพ + OCR text $domain ...');
          final visionResult = await _geminiService!.classifyScreenshot(
            screenshotBytes: screenshot,
            url: url,
            pageTitle: title,
            domContent: snippet,
            ocrContent: ocrText,
          );
          if (visionResult != null) {
            _isAnalyzing = false;
            notifyListeners();
            final isGambling =
                visionResult.isGambling && visionResult.confidence >= 0.7;
            await AdRemovalCache.saveCache(
              domain: domain,
              selectors: visionResult.semanticSelectors,
              isGambling: isGambling,
            );
            _log(
              isGambling
                  ? '🤖 Vision AI: $domain → Gambling-like content (${(visionResult.confidence * 100).toInt()}%)'
                  : '🤖 Vision AI: $domain → Safe (${((1 - visionResult.confidence) * 100).toInt()}%)',
            );
            final shouldBlockWholeSite = isGambling &&
                _shouldBlockWholeSite(
                  url,
                  title,
                  combinedContent,
                  score,
                  aiConfidence: visionResult.confidence,
                  selectors: visionResult.semanticSelectors,
                );
            return DetectionResult(
              verdict: !isGambling
                  ? DetectionVerdict.safe
                  : shouldBlockWholeSite
                      ? DetectionVerdict.blocked
                      : DetectionVerdict.sanitize,
              reason: shouldBlockWholeSite
                  ? 'Vision block: ${visionResult.reason}'
                  : 'Vision: ${visionResult.reason}',
              layer: 'Gemini Vision AI',
              selectors: visionResult.semanticSelectors,
            );
          }
        }

        // Fallback: Text AI
        _log('🤖 Text AI: fallback วิเคราะห์จาก text $domain ...');
        final textResult = await _geminiService!.classifyUrl(
          url: url,
          pageTitle: title,
          domContent: snippet,
          ocrContent: ocrText,
        );
        _isAnalyzing = false;
        notifyListeners();
        if (textResult != null) {
          final isGambling =
              textResult.isGambling && textResult.confidence >= 0.7;
          await AdRemovalCache.saveCache(
            domain: domain,
            selectors: textResult.semanticSelectors,
            isGambling: isGambling,
          );
          _log(
            isGambling
                ? '🤖 Text AI: $domain → Gambling-like content (${(textResult.confidence * 100).toInt()}%)'
                : '🤖 Text AI: $domain → Safe (${((1 - textResult.confidence) * 100).toInt()}%)',
          );
          final shouldBlockWholeSite = isGambling &&
              _shouldBlockWholeSite(
                url,
                title,
                combinedContent,
                score,
                aiConfidence: textResult.confidence,
                selectors: textResult.semanticSelectors,
              );
          return DetectionResult(
            verdict: !isGambling
                ? DetectionVerdict.safe
                : shouldBlockWholeSite
                    ? DetectionVerdict.blocked
                    : DetectionVerdict.sanitize,
            reason: shouldBlockWholeSite
                ? 'Text block: ${textResult.reason}'
                : 'Text AI: ${textResult.reason}',
            layer: 'Gemini Text AI',
            selectors: textResult.semanticSelectors,
          );
        }
      }

      // Gemini ไม่พร้อม → local fallback
      _isAnalyzing = false;
      notifyListeners();
      final isGambling = score >= 3;
      final shouldBlockWholeSite = isGambling &&
          _shouldBlockWholeSite(url, title, combinedContent, score);
      _log(
        isGambling
            ? '🔎 Local fallback: $domain → Gambling (score=$score ≥ 3)'
            : '🔎 Local fallback: $domain → Safe (score=$score < 3)',
      );
      if (isGambling) {
        await AdRemovalCache.saveCache(
          domain: domain,
          selectors: [],
          isGambling: true,
        );
      }
      return DetectionResult(
        verdict: !isGambling
            ? DetectionVerdict.safe
            : shouldBlockWholeSite
                ? DetectionVerdict.blocked
                : DetectionVerdict.sanitize,
        reason: shouldBlockWholeSite
            ? 'Local fallback block: score $score'
            : 'Local fallback: score $score',
        layer: 'Local Scoring',
      );
    } catch (e) {
      _isAnalyzing = false;
      notifyListeners();
      _log('⚠️ Hybrid Error: $e → local fallback');
      final score = scoreContent(url, title, snippet);
      final isGambling = score >= 3;
      final shouldBlockWholeSite = isGambling &&
          _shouldBlockWholeSite(url, title, snippet, score);
      if (isGambling) {
        _log('🔎 Local Analysis: $domain → Gambling');
        await AdRemovalCache.saveCache(
          domain: domain,
          selectors: [],
          isGambling: true,
        );
      }
      return DetectionResult(
        verdict: !isGambling
            ? DetectionVerdict.safe
            : shouldBlockWholeSite
                ? DetectionVerdict.blocked
                : DetectionVerdict.sanitize,
        reason: shouldBlockWholeSite
            ? 'Error fallback block: score $score'
            : 'Error fallback: score $score',
        layer: 'Local Scoring (error)',
      );
    }
  }

  /// ══════════════════════════════════════════════════════════════════════
  /// scoreContent — รวม _scoreContent + _analyzeContentLocally เป็นตัวเดียว
  /// ══════════════════════════════════════════════════════════════════════
  int scoreContent(String url, String title, String content) {
    final lower = content.toLowerCase();
    final titleLower = title.toLowerCase();
    final metaLower = _extractStructuredSection(content, 'META:').toLowerCase();
    final linksLower = _extractStructuredSection(content, 'LINKS:').toLowerCase();
    final imagesLower = _extractStructuredSection(content, 'IMAGES:').toLowerCase();
    final titleAndMeta = '$titleLower\n$metaLower';
    final combined = '$titleLower\n$lower';
    int score = 0;
    final List<String> matches = [];

    int titleMetaStrongHits = 0;
    for (final kw in _keywords.thaiTitleMetaStrong) {
      if (_containsNormalized(titleAndMeta, kw)) titleMetaStrongHits++;
    }
    int titleMetaMediumHits = 0;
    for (final kw in _keywords.thaiTitleMetaMedium) {
      if (_containsNormalized(titleAndMeta, kw)) titleMetaMediumHits++;
    }
    if (titleMetaStrongHits >= 2) {
      score += 5;
      matches.add('titleStrong($titleMetaStrongHits)');
    } else if (titleMetaStrongHits == 1) {
      score += 4;
      matches.add('titleStrong($titleMetaStrongHits)');
    }
    if (titleMetaMediumHits >= 2) {
      score += 2;
      matches.add('titleMedium($titleMetaMediumHits)');
    } else if (titleMetaMediumHits == 1) {
      score += 1;
      matches.add('titleMedium($titleMetaMediumHits)');
    }

    int providerHits = 0;
    for (final p in _keywords.gameProviders) {
      if (_containsNormalized(combined, p)) providerHits++;
    }
    if (providerHits >= 3) {
      score += 3;
      matches.add('providers($providerHits)');
    } else if (providerHits >= 1) {
      score += providerHits;
      matches.add('providers($providerHits)');
    }

    for (final t in _keywords.gameTypes) {
      if (_containsNormalized(combined, t)) {
        score += 1;
        matches.add('type:$t');
        break;
      }
    }

    int financialHits = 0;
    for (final f in _keywords.financialTerms) {
      if (_containsNormalized(combined, f)) financialHits++;
    }
    if (financialHits >= 1) {
      score += 2;
      matches.add('financial($financialHits)');
    }

    int thaiHits = 0;
    for (final kw in _keywords.thaiKeywords) {
      if (_containsNormalized(lower, kw)) thaiHits++;
    }
    if (thaiHits >= 2) {
      score += 2;
      matches.add('thai($thaiHits)');
    } else if (thaiHits == 1) {
      score += 1;
      matches.add('thai($thaiHits)');
    }

    final urlLower = url.toLowerCase();
    for (final d in _keywords.urlIndicators) {
      if (urlLower.contains(d)) {
        score += 1;
        matches.add('url:$d');
        break;
      }
    }

    int gameHits = 0;
    for (final g in _keywords.gameNames) {
      if (_containsNormalized(combined, g)) gameHits++;
    }
    if (gameHits >= 1) {
      score += 2;
      matches.add('games($gameHits)');
    }

    int signalHits = 0;
    for (final s in _keywords.genericGamblingSignals) {
      if (_containsNormalized(combined, s)) signalHits++;
    }
    if (signalHits >= 3) {
      score += 3;
      matches.add('signals($signalHits)');
    } else if (signalHits >= 1) {
      score += signalHits;
      matches.add('signals($signalHits)');
    }

    final baseGamblingScore = score;

    final authFormSignals = _countContainsNormalized(combined, <String>[
      'เข้าสู่ระบบ',
      'สมัครสมาชิก',
      'เบอร์โทรศัพท์',
      'รหัสผ่าน',
      'ทางเข้าเล่น',
    ]);
    if (authFormSignals >= 3) {
      score += 1;
      matches.add('authFlow($authFormSignals)');
    }

    final authEndpointDetected = RegExp(
      r'(action\.php\?(login|register)|/login\b|/register\b|auth/login|member/auth/login)',
      caseSensitive: false,
    ).hasMatch(content);
    if (authEndpointDetected && baseGamblingScore > 0) {
      score += 1;
      matches.add('authEndpoint');
    }

    final lineContactDetected = RegExp(
      r'(line\.me\/r\/ti\/p|lin\.ee/|ibit\.ly/)',
      caseSensitive: false,
    ).hasMatch(content);
    final strongTitleMetaSignal = titleMetaStrongHits > 0;
    if (lineContactDetected &&
        (providerHits > 0 || financialHits > 0 || strongTitleMetaSignal)) {
      score += 1;
      matches.add('lineContact');
    }

    final linkActionHits = _countContainsNormalized(linksLower, <String>[
      'เข้าสู่ระบบ',
      'สมัครสมาชิก',
      'ทางเข้าเล่น',
      'โปรโมชั่น',
      'ติดต่อ',
      'login',
      'register',
      'promotion',
    ]);
    if (linkActionHits >= 2 &&
        (providerHits > 0 || financialHits > 0 || strongTitleMetaSignal)) {
      score += 1;
      matches.add('linkActions($linkActionHits)');
    }

    final imageBrandingHits = _countContainsNormalized(imagesLower, <String>[
      ..._keywords.gameProviders,
      'คาสิโน',
      'สล็อต',
      'บาคาร่า',
      'เดิมพัน',
      'พนัน',
    ]);
    if (imageBrandingHits >= 2 &&
        (providerHits > 0 || financialHits > 0 || strongTitleMetaSignal)) {
      score += 1;
      matches.add('imageBranding($imageBrandingHits)');
    }

    _log('Score detail: $score (${matches.join(", ")})');
    return score;
  }

  bool _containsNormalized(String haystack, String needle) {
    final normalizedNeedle = _normalizeForMatch(needle);
    if (normalizedNeedle.isEmpty) return false;
    return _normalizeForMatch(haystack).contains(normalizedNeedle);
  }

  int _countContainsNormalized(String haystack, List<String> needles) {
    var hits = 0;
    for (final needle in needles) {
      if (_containsNormalized(haystack, needle)) hits++;
    }
    return hits;
  }

  String _extractStructuredSection(String content, String label) {
    final start = content.indexOf(label);
    if (start == -1) return '';

    final sectionStart = start + label.length;
    final sectionEnd = content.indexOf(' ||| ', sectionStart);
    if (sectionEnd == -1) {
      return content.substring(sectionStart).trim();
    }
    return content.substring(sectionStart, sectionEnd).trim();
  }

  String _normalizeForMatch(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[\s\-_]'), '');
  }

}

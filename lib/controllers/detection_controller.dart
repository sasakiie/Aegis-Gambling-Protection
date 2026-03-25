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
import 'classification_cache.dart';
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

  /// ══════════════════════════════════════════════════════════════════════
  /// checkUrl — 4-Layer Detection → คืน DetectionResult
  /// ══════════════════════════════════════════════════════════════════════
  Future<DetectionResult> checkUrl(
    String url, {
    String title = '',
    String snippet = '',
    Future<Uint8List?> Function()? captureScreenshot,
  }) async {
    final domain = extractDomain(url);

    // ─── Layer 1: Smart Cache ───
    final cached = await ClassificationCache.getCachedResult(domain);
    if (cached != null) {
      _log(
        cached.isGambling
            ? '⚡ Cache: $domain → Gambling (${(cached.confidence * 100).toInt()}%)'
            : '⚡ Cache: $domain → Safe',
      );
      return DetectionResult(
        verdict: cached.isGambling
            ? DetectionVerdict.blocked
            : DetectionVerdict.safe,
        reason: cached.reason,
        layer: 'Cache',
      );
    }

    // ─── Layer 2: Pre-filter (gambling_keywords.json) ───
    if (isDefinitelyGambling(url)) {
      _log('🚫 Pre-filter: $domain → Known gambling brand');
      await ClassificationCache.cacheResult(
        domain,
        true,
        1.0,
        'Known gambling brand (pre-filter)',
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
      _log('📊 Hybrid Score: $score (threshold: ≥4 block, 1-3 gray zone)');

      if (score >= 4) {
        _log('🚫 Hybrid: $domain → Gambling (score=$score, ชัดเจน)');
        _isAnalyzing = false;
        notifyListeners();
        await ClassificationCache.cacheResult(
          domain,
          true,
          0.9,
          'Hybrid: local score $score (OCR+Deep)',
        );
        return DetectionResult(
          verdict: DetectionVerdict.blocked,
          reason: 'Hybrid: local score $score',
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
            extractedContent: combinedContent,
          );
          if (visionResult != null) {
            _isAnalyzing = false;
            notifyListeners();
            final isGambling =
                visionResult.isGambling && visionResult.confidence >= 0.7;
            await ClassificationCache.cacheResult(
              domain,
              isGambling,
              visionResult.confidence,
              'Hybrid→Vision: ${visionResult.reason}',
            );
            _log(
              isGambling
                  ? '🤖 Vision AI: $domain → Gambling (${(visionResult.confidence * 100).toInt()}%)'
                  : '🤖 Vision AI: $domain → Safe (${((1 - visionResult.confidence) * 100).toInt()}%)',
            );
            return DetectionResult(
              verdict: isGambling
                  ? DetectionVerdict.blocked
                  : DetectionVerdict.safe,
              reason: 'Vision: ${visionResult.reason}',
              layer: 'Gemini Vision AI',
            );
          }
        }

        // Fallback: Text AI
        _log('🤖 Text AI: fallback วิเคราะห์จาก text $domain ...');
        final textResult = await _geminiService!.classifyUrl(
          url: url,
          pageTitle: title,
          contentSnippet: combinedContent,
        );
        _isAnalyzing = false;
        notifyListeners();
        if (textResult != null) {
          final isGambling =
              textResult.isGambling && textResult.confidence >= 0.7;
          await ClassificationCache.cacheResult(
            domain,
            isGambling,
            textResult.confidence,
            'Hybrid→Text: ${textResult.reason}',
          );
          _log(
            isGambling
                ? '🤖 Text AI: $domain → Gambling (${(textResult.confidence * 100).toInt()}%)'
                : '🤖 Text AI: $domain → Safe (${((1 - textResult.confidence) * 100).toInt()}%)',
          );
          return DetectionResult(
            verdict: isGambling
                ? DetectionVerdict.blocked
                : DetectionVerdict.safe,
            reason: 'Text AI: ${textResult.reason}',
            layer: 'Gemini Text AI',
          );
        }
      }

      // Gemini ไม่พร้อม → local fallback
      _isAnalyzing = false;
      notifyListeners();
      final isGambling = score >= 3;
      _log(
        isGambling
            ? '🔎 Local fallback: $domain → Gambling (score=$score ≥ 3)'
            : '🔎 Local fallback: $domain → Safe (score=$score < 3)',
      );
      if (isGambling) {
        await ClassificationCache.cacheResult(
          domain,
          true,
          0.85,
          'Local fallback: score $score',
        );
      }
      return DetectionResult(
        verdict: isGambling ? DetectionVerdict.blocked : DetectionVerdict.safe,
        reason: 'Local fallback: score $score',
        layer: 'Local Scoring',
      );
    } catch (e) {
      _isAnalyzing = false;
      notifyListeners();
      _log('⚠️ Hybrid Error: $e → local fallback');
      final score = scoreContent(url, title, snippet);
      final isGambling = score >= 3;
      if (isGambling) {
        _log('🔎 Local Analysis: $domain → Gambling');
        await ClassificationCache.cacheResult(
          domain,
          true,
          0.85,
          'Local: gambling patterns detected',
        );
      }
      return DetectionResult(
        verdict: isGambling ? DetectionVerdict.blocked : DetectionVerdict.safe,
        reason: 'Error fallback: score $score',
        layer: 'Local Scoring (error)',
      );
    }
  }

  /// ══════════════════════════════════════════════════════════════════════
  /// scoreContent — รวม _scoreContent + _analyzeContentLocally เป็นตัวเดียว
  /// ══════════════════════════════════════════════════════════════════════
  int scoreContent(String url, String title, String content) {
    final lower = content.toLowerCase();
    int score = 0;
    final List<String> matches = [];

    // 1. Game providers
    int providerHits = 0;
    for (final p in _keywords.gameProviders) {
      if (lower.contains(p)) providerHits++;
    }
    if (providerHits >= 3) {
      score += 3;
      matches.add('providers($providerHits)');
    } else if (providerHits >= 1) {
      score += providerHits;
      matches.add('providers($providerHits)');
    }

    // 2. Game types
    for (final t in _keywords.gameTypes) {
      if (lower.contains(t)) {
        score += 1;
        matches.add('type:$t');
        break;
      }
    }

    // 3. Financial terms
    for (final f in _keywords.financialTerms) {
      if (lower.contains(f)) {
        score += 2;
        matches.add('financial:$f');
        break;
      }
    }

    // 4. Thai keywords
    int thaiHits = 0;
    for (final kw in _keywords.thaiKeywords) {
      if (content.contains(kw)) thaiHits++;
    }
    if (thaiHits >= 2) {
      score += 2;
      matches.add('thai($thaiHits)');
    } else if (thaiHits == 1) {
      score += 1;
      matches.add('thai($thaiHits)');
    }

    // 5. URL indicators
    final urlLower = url.toLowerCase();
    for (final d in _keywords.urlIndicators) {
      if (urlLower.contains(d)) {
        score += 1;
        matches.add('url:$d');
        break;
      }
    }

    // 6. Game names
    int gameHits = 0;
    for (final g in _keywords.gameNames) {
      if (lower.contains(g)) gameHits++;
    }
    if (gameHits >= 1) {
      score += 2;
      matches.add('games($gameHits)');
    }

    // 7. Generic gambling signals
    int signalHits = 0;
    for (final s in _keywords.genericGamblingSignals) {
      if (lower.contains(s)) signalHits++;
    }
    if (signalHits >= 3) {
      score += 3;
      matches.add('signals($signalHits)');
    } else if (signalHits >= 1) {
      score += signalHits;
      matches.add('signals($signalHits)');
    }

    _log('🔎 Score detail: $score (${matches.join(", ")})');
    return score;
  }
}

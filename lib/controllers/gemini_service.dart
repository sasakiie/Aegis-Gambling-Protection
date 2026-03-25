// ============================================================================
// AEGIS Shield — controllers/gemini_service.dart (v3.0)
// ============================================================================
// Gemini API Client สำหรับวิเคราะห์ว่าเว็บเป็นเว็บพนันหรือไม่
// ============================================================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/classification_result.dart';

/// Gemini API Service — เรียก Gemini API เพื่อวิเคราะห์เว็บ (Text + Vision)
class GeminiService {
  final String apiKey;
  static const String _model = 'gemini-2.0-flash';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  final void Function(String)? onLog;

  GeminiService({required this.apiKey, this.onLog});

  void _log(String message) {
    // ignore: avoid_print
    print('[GeminiService] $message');
    onLog?.call(message);
  }

  /// วิเคราะห์ URL ว่าเป็นเว็บพนันหรือไม่ (text-only)
  Future<GeminiClassification?> classifyUrl({
    required String url,
    String pageTitle = '',
    String contentSnippet = '',
  }) async {
    try {
      final prompt = _buildTextPrompt(url, pageTitle, contentSnippet);
      _log('📝 Text prompt length: ${prompt.length} chars');
      final response = await _callGeminiText(prompt);

      if (response == null) {
        _log('⚠️ Text API returned null response');
        return null;
      }

      _log(
        '📝 Text API raw: ${response.substring(0, response.length.clamp(0, 200))}',
      );
      return _parseResponse(response);
    } catch (e) {
      _log('❌ classifyUrl error: $e');
      return null;
    }
  }

  /// วิเคราะห์ screenshot ของหน้าเว็บ (Vision)
  Future<GeminiClassification?> classifyScreenshot({
    required Uint8List screenshotBytes,
    String url = '',
    String extractedContent = '',
  }) async {
    try {
      final base64Image = base64Encode(screenshotBytes);
      _log(
        '🖼️ Vision: sending ${(screenshotBytes.length / 1024).toStringAsFixed(0)} KB image + ${extractedContent.length} chars text',
      );
      final response = await _callGeminiVision(
        base64Image,
        url,
        extractedContent,
      );

      if (response == null) {
        _log('⚠️ Vision API returned null response');
        return null;
      }

      _log(
        '🖼️ Vision API raw: ${response.substring(0, response.length.clamp(0, 200))}',
      );
      return _parseResponse(response);
    } catch (e) {
      _log('❌ classifyScreenshot error: $e');
      return null;
    }
  }

  String _buildTextPrompt(String url, String title, String snippet) {
    final truncatedSnippet = snippet.length > 5000
        ? snippet.substring(0, 5000)
        : snippet;

    return '''You are an expert website classifier specialized in detecting online gambling/betting websites.
Your job is to protect children from accessing gambling sites.

IMPORTANT: Many gambling sites DISGUISE themselves as normal websites but embed gambling content
in their page data, JavaScript, or rendered after page load. You must check ALL provided data carefully.

=== STRONG GAMBLING INDICATORS (high confidence if found) ===
- Game categories: SLOT, LIVECASINO, BACCARAT, SPORT BETTING, FISHING GAME, POKER
- Game providers: PGSOFT, SAGAME, SEXY, PRAGMATIC, SLOTXO, JOKER, JILI, ALLBET, PRETTY, SBO, DREAM, SPADE, CQ9, HACKSAW, WM, NAGA, SPINIX, 918KISS
- Financial operations: deposit, withdraw, minDepositAmt, minWithdrawAmt, reimburse, credit
- Thai gambling terms: สล็อต, บาคาร่า, คาสิโน, แทงบอล, พนัน, เครดิตฟรี, ฝากถอน, หวย
- Brand patterns: UFA, Betflix, SBOBET, GCLUB, LSM99, etc.
- Game data objects with type:SLOT, category:LIVECASINO, category:SPORT

=== CHECK THESE DATA SOURCES ===
1. VISIBLE_TEXT: rendered page text
2. NEXT_DATA: JSON data from Next.js SPA — check for game lists, providers, deposit/withdraw config
3. SCRIPT_DATA: embedded JSON with game/casino data
4. META: page metadata
5. LINKS: navigation links pointing to gambling sections
6. IMAGES: image sources/alt text with gambling references

=== NON-GAMBLING (avoid false positives) ===
- Technology/IT companies, game review sites, news about gambling industry
- Game stores (Steam, PlayStation, Nintendo) — selling video games is NOT gambling
- Educational content about gambling addiction
- E-commerce, social media, banking apps

URL: $url
Page Title: ${title.isEmpty ? '(not available)' : title}

Extracted Page Content:
$truncatedSnippet

Respond ONLY with a valid JSON object (no markdown, no code blocks):
{"isGambling": true/false, "confidence": 0.0-1.0, "reason": "brief explanation in English"}''';
  }

  String _buildVisionPrompt(String url, String extractedContent) {
    final hasContent = extractedContent.trim().isNotEmpty;
    final truncatedContent = extractedContent.length > 3000
        ? extractedContent.substring(0, 3000)
        : extractedContent;

    return '''You are a visual website classifier specialized in detecting online gambling websites.

Analyze this screenshot of a webpage and determine if it is an online gambling website.

Look for these VISUAL gambling indicators:
- Casino/slot machine imagery, playing cards, dice, roulette wheels
- Banners promoting online betting, sports betting, or casino games
- Thai text related to gambling: สล็อต, บาคาร่า, เครดิตฟรี, ฝากถอน, แทงบอล, พนัน
- Logos of gambling brands: UFA, PG Slot, SA Gaming, Betflix, SBOBET, Joker, etc.
- Promotional banners with deposit/withdrawal, free credits, bonus offers
- Login/register forms specifically for gambling platforms
- Live casino dealer images or slot game thumbnails
- Website layouts typical of gambling platforms (dark themes with neon colors, game grids)

NON-gambling indicators (avoid false positives):
- Regular news, shopping, social media, or entertainment websites
- Video game platforms (Steam, PlayStation, etc.)
- Educational or informational content about gambling addiction
- Financial or banking websites

${url.isNotEmpty ? 'URL context: $url' : ''}
${hasContent ? '\n=== EXTRACTED TEXT FROM PAGE (OCR + DOM) ===\n$truncatedContent\n=== END EXTRACTED TEXT ===' : ''}

IMPORTANT: Use BOTH the screenshot image AND the extracted text above to make your decision.
The extracted text was read from the actual webpage by OCR and DOM parsing.
If either the visual elements OR the text content suggest gambling, classify as gambling.

Respond ONLY with a valid JSON object (no markdown, no code blocks):
{"isGambling": true/false, "confidence": 0.0-1.0, "reason": "brief explanation of what visual elements were detected"}''';
  }

  Future<String?> _callGeminiText(String prompt) async {
    final url = Uri.parse('$_baseUrl/$_model:generateContent?key=$apiKey');

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {'temperature': 0.1, 'maxOutputTokens': 200},
    });

    try {
      final response = await http
          .post(url, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 20));
      return _extractTextFromResponse(response);
    } catch (e) {
      _log('❌ _callGeminiText HTTP error: $e');
      return null;
    }
  }

  Future<String?> _callGeminiVision(
    String base64Image,
    String pageUrl,
    String extractedContent,
  ) async {
    final url = Uri.parse('$_baseUrl/$_model:generateContent?key=$apiKey');

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {
              'inline_data': {'mime_type': 'image/jpeg', 'data': base64Image},
            },
            {'text': _buildVisionPrompt(pageUrl, extractedContent)},
          ],
        },
      ],
      'generationConfig': {'temperature': 0.1, 'maxOutputTokens': 300},
    });

    try {
      final response = await http
          .post(url, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 20));
      return _extractTextFromResponse(response);
    } catch (e) {
      _log('❌ _callGeminiVision HTTP error: $e');
      return null;
    }
  }

  String? _extractTextFromResponse(http.Response response) {
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = json['candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates[0]['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          return parts[0]['text'] as String?;
        }
        final finishReason = candidates[0]['finishReason'] as String?;
        if (finishReason != null && finishReason != 'STOP') {
          _log('⚠️ API finish reason: $finishReason');
        }
      } else {
        final promptFeedback = json['promptFeedback'] as Map<String, dynamic>?;
        if (promptFeedback != null) {
          _log('⚠️ Prompt blocked: ${jsonEncode(promptFeedback)}');
        }
      }
    } else {
      _log(
        '❌ API HTTP ${response.statusCode}: ${response.body.substring(0, response.body.length.clamp(0, 300))}',
      );
    }
    return null;
  }

  GeminiClassification? _parseResponse(String responseText) {
    try {
      var cleaned = responseText.trim();
      if (cleaned.startsWith('```')) {
        cleaned = cleaned.replaceAll(RegExp(r'^```\w*\n?'), '');
        cleaned = cleaned.replaceAll(RegExp(r'\n?```$'), '');
        cleaned = cleaned.trim();
      }

      final json = jsonDecode(cleaned) as Map<String, dynamic>;

      return GeminiClassification(
        isGambling: json['isGambling'] as bool? ?? false,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        reason: json['reason'] as String? ?? 'Unknown',
      );
    } catch (e) {
      _log(
        '⚠️ JSON parse failed: $e — raw: ${responseText.substring(0, responseText.length.clamp(0, 200))}',
      );
      final isGambling =
          responseText.toLowerCase().contains('"isgambling": true') ||
          responseText.toLowerCase().contains('"isgambling":true');
      return GeminiClassification(
        isGambling: isGambling,
        confidence: 0.5,
        reason: 'Parsed from non-JSON response',
      );
    }
  }
}

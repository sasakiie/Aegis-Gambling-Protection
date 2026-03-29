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
    String domContent = '',
    String ocrContent = '',
  }) async {
    try {
      final prompt = _buildPromptBase(url, pageTitle, domContent, ocrContent, isVision: false);
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
    String pageTitle = '',
    String domContent = '',
    String ocrContent = '',
  }) async {
    try {
      final base64Image = base64Encode(screenshotBytes);
      _log(
        '🖼️ Vision: sending ${(screenshotBytes.length / 1024).toStringAsFixed(0)} KB image + ${domContent.length + ocrContent.length} chars text',
      );
      
      final prompt = _buildPromptBase(url, pageTitle, domContent, ocrContent, isVision: true);
      
      final response = await _callGeminiVision(
        base64Image,
        prompt,
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

  String _sanitizeForXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  String _buildPromptBase(String url, String title, String domContent, String ocrContent, {bool isVision = false}) {
    final truncDom = domContent.length > 5000 ? domContent.substring(0, 5000) : domContent;
    final truncOcr = ocrContent.length > 2000 ? ocrContent.substring(0, 2000) : ocrContent;
    
    final safeTitle = _sanitizeForXml(title);
    final safeDom = _sanitizeForXml(truncDom);
    final safeOcr = _sanitizeForXml(truncOcr);

    final String instruction = isVision 
      ? 'Analyze the screenshot AND the XML text content extracted from the page. Determine if this is an online gambling/betting website. Look for visual gambling indicators (slot machines, cards, betting banners, login forms for casino).'
      : 'Analyze the XML text content extracted from the webpage. Determine if this is an online gambling/betting website. Look for gambling keywords, providers, or game types.';

    return '''You are an expert website classifier specialized in detecting online gambling websites.
Your job is to protect children from accessing these sites.

<instruction>
$instruction
IMPORTANT: Many gambling sites DISGUISE themselves as normal websites but embed gambling content in their DOM. YOU MUST read both the `<dom_content>` and `<ocr_content>` components.
Respond ONLY with a valid JSON object (no markdown, no code blocks) matching this schema:
{
  "isGambling": true/false,
  "confidence": 0.0-1.0,
  "reason": "brief explanation in English",
  "semanticSelectors": ["a[href*='ufa']", ".gambling-banner", "img[alt*='slot']"]
}
For `semanticSelectors`, output an array of valid semantic CSS Selectors that specifically target gambling ads or banners inside the DOM. Do NOT use generic tags like `div` or generic classes like `container`. Return an empty array if no specific gambling elements are found.
</instruction>

<website_context>
  <url>$url</url>
  <title>$safeTitle</title>
</website_context>

<dom_content>
$safeDom
</dom_content>

<ocr_content>
$safeOcr
</ocr_content>''';
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
    String visionPrompt,
  ) async {
    final url = Uri.parse('$_baseUrl/$_model:generateContent?key=$apiKey');

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {
              'inline_data': {'mime_type': 'image/jpeg', 'data': base64Image},
            },
            {'text': visionPrompt},
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

      List<String> selectors = [];
      if (json['semanticSelectors'] != null) {
        selectors = List<String>.from(json['semanticSelectors'] as List);
      }

      return GeminiClassification(
        isGambling: json['isGambling'] as bool? ?? false,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        reason: json['reason'] as String? ?? 'Unknown',
        semanticSelectors: selectors,
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

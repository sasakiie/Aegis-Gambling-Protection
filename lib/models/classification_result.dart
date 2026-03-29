// ============================================================================
// AEGIS Shield — models/classification_result.dart
// ============================================================================
// Data models สำหรับผลวิเคราะห์เว็บไซต์
// ============================================================================

/// ผลลัพธ์จากการวิเคราะห์ domain (เก็บใน cache)
class ClassificationResult {
  final bool isGambling;
  final double confidence;
  final String reason;
  final DateTime cachedAt;

  ClassificationResult({
    required this.isGambling,
    required this.confidence,
    required this.reason,
    required this.cachedAt,
  });

  /// แปลงเป็น JSON สำหรับเก็บใน SharedPreferences
  Map<String, dynamic> toJson() => {
    'isGambling': isGambling,
    'confidence': confidence,
    'reason': reason,
    'cachedAt': cachedAt.toIso8601String(),
  };

  /// สร้างจาก JSON ที่อ่านจาก SharedPreferences
  factory ClassificationResult.fromJson(Map<String, dynamic> json) {
    return ClassificationResult(
      isGambling: json['isGambling'] as bool,
      confidence: (json['confidence'] as num).toDouble(),
      reason: json['reason'] as String,
      cachedAt: DateTime.parse(json['cachedAt'] as String),
    );
  }
}

/// ผลลัพธ์จาก Gemini API
class GeminiClassification {
  final bool isGambling;
  final double confidence;
  final String reason;
  final List<String> semanticSelectors;

  GeminiClassification({
    required this.isGambling,
    required this.confidence,
    required this.reason,
    this.semanticSelectors = const [],
  });
}

/// ผลการตรวจจับจาก DetectionController
enum DetectionVerdict { safe, sanitize, blocked, analyzing }

class DetectionResult {
  final DetectionVerdict verdict;
  final String reason;
  final String layer;
  final List<String> selectors;

  const DetectionResult({
    required this.verdict,
    required this.reason,
    required this.layer,
    this.selectors = const [],
  });
}

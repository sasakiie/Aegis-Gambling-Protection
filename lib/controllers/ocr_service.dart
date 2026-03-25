// ============================================================================
// AEGIS Shield — controllers/ocr_service.dart (On-Device OCR)
// ============================================================================
// ย้ายจาก lib/ocr_service.dart → lib/controllers/ocr_service.dart
// ============================================================================

import 'dart:io';
import 'dart:typed_data';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;

class OcrService {
  static OcrService? _instance;
  TextRecognizer? _recognizer;

  OcrService._();

  static OcrService get instance {
    _instance ??= OcrService._();
    return _instance!;
  }

  TextRecognizer _getRecognizer() {
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    return _recognizer!;
  }

  Future<String> recognizeText(Uint8List imageBytes) async {
    if (imageBytes.isEmpty) return '';

    File? tempFile;
    try {
      final tempDir = await getTemporaryDirectory();
      tempFile = File(
        '${tempDir.path}/aegis_ocr_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(imageBytes);

      final inputImage = InputImage.fromFilePath(tempFile.path);
      final recognizer = _getRecognizer();
      final recognizedText = await recognizer.processImage(inputImage);

      final buffer = StringBuffer();
      for (final block in recognizedText.blocks) {
        buffer.writeln(block.text);
      }
      return buffer.toString().trim();
    } catch (e) {
      return '';
    } finally {
      try {
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  void close() {
    _recognizer?.close();
    _recognizer = null;
  }
}

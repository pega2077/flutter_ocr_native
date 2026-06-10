import 'dart:typed_data';

import 'models/ocr_result.dart';
import 'ocr_platform_interface.dart';
import 'ocr_web_plugin.dart';
import 'utils/ocr_document_saver_web.dart';
import 'validators/ocr_validator.dart';

class OcrReader {
  final OcrPlatformInterface _platform;

  /// When true, rejects empty and handwritten images.
  bool validateDocument;

  /// When true, automatically masks Aadhaar numbers if detected.
  bool maskAadhaar;

  /// Custom validator thresholds.
  final OcrValidator validator;

  OcrReader({
    OcrPlatformInterface? platform,
    this.validateDocument = false,
    this.maskAadhaar = false,
    OcrValidator? validator,
  })  : _platform = platform ?? FlutterOcrNativeWeb(),
        validator = validator ?? const OcrValidator();

  Future<OcrResult> _process(Future<OcrResult> result) async {
    final resolved = await result;
    if (validateDocument) validator.validate(resolved);
    return maskAadhaar ? resolved.maskAadhaar() : resolved;
  }

  /// Recognize English text from an image URL/path.
  Future<OcrResult> readFromPath(String imagePath) {
    if (imagePath.trim().isEmpty) {
      throw ArgumentError('Image path cannot be empty');
    }
    return _process(_platform.recognizeFromPath(imagePath));
  }

  /// Recognize English text from raw image bytes.
  Future<OcrResult> readFromBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw ArgumentError('Image bytes cannot be empty');
    }
    return _process(_platform.recognizeFromBytes(bytes));
  }

  /// Recognize text from a PDF byte array.
  /// Web currently does not support native PDF page rendering.
  Future<OcrResult> readFromPdf(
    Uint8List pdfBytes, {
    int page = 0,
    double scale = 2.0,
  }) async {
    final imageBytes = await OcrDocumentSaver.renderPdfPage(pdfBytes,
        page: page, scale: scale);
    if (imageBytes == null) {
      throw UnsupportedError(
        'PDF rendering is not supported on web. Convert PDF pages to images before OCR.',
      );
    }
    return readFromBytes(imageBytes);
  }

  /// Release resources.
  Future<void> dispose() => _platform.dispose();
}

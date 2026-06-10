import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../models/ocr_result.dart';
import '../models/ocr_watermark.dart';

/// Lightweight browser-side file object used for web downloads.
class File {
  final String path;
  const File(this.path);
}

/// Lightweight browser-side directory object.
class Directory {
  final String path;
  const Directory(this.path);
}

/// Output image format for saving.
enum OcrImageFormat {
  /// JPEG — smaller file size, configurable quality. Default.
  jpeg,

  /// PNG — lossless, larger file size.
  png,
}

class OcrDocumentSaver {
  static Future<Uint8List?> renderPdfPage(
    Uint8List pdfBytes, {
    int page = 0,
    double scale = 2.0,
  }) async {
    return null;
  }

  static Future<int> getPdfPageCount(Uint8List pdfBytes) async => 0;

  static Future<List<Uint8List>> renderAllPdfPages(
    Uint8List pdfBytes, {
    double scale = 2.0,
  }) async {
    return const [];
  }

  static Future<File> download({
    required OcrResult result,
    required Uint8List originalImageBytes,
    String? fileName,
    OcrWatermark? watermark,
    int imageQuality = 90,
    OcrImageFormat format = OcrImageFormat.jpeg,
  }) async {
    final imageBytes =
        result.hasAadhaar ? result.maskedImageBytes! : originalImageBytes;
    return downloadBytes(
      imageBytes: imageBytes,
      fileName: fileName,
      watermark: watermark,
      imageQuality: imageQuality,
      format: format,
    );
  }

  static Future<File> downloadFromPath({
    required OcrResult result,
    required String originalImagePath,
    String? fileName,
    OcrWatermark? watermark,
    int imageQuality = 90,
    OcrImageFormat? format,
  }) async {
    throw UnsupportedError(
      'downloadFromPath is not supported on web. Use downloadBytes instead.',
    );
  }

  static Future<File> downloadBytes({
    required Uint8List imageBytes,
    String? fileName,
    OcrWatermark? watermark,
    int imageQuality = 90,
    OcrImageFormat format = OcrImageFormat.jpeg,
  }) async {
    final isPng = format == OcrImageFormat.png;
    final ext = isPng ? 'png' : 'jpg';
    final name =
        fileName ?? 'ocr_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final finalBytes = watermark == null
        ? imageBytes
        : await burnWatermark(imageBytes, watermark, quality: imageQuality);
    _triggerDownload(finalBytes, name, isPng ? 'image/png' : 'image/jpeg');
    return File(name);
  }

  static Future<File> save({
    required OcrResult result,
    required Uint8List originalImageBytes,
    required Directory directory,
    String? fileName,
    OcrWatermark? watermark,
    int imageQuality = 90,
    OcrImageFormat format = OcrImageFormat.jpeg,
  }) async {
    return download(
      result: result,
      originalImageBytes: originalImageBytes,
      fileName: fileName,
      watermark: watermark,
      imageQuality: imageQuality,
      format: format,
    );
  }

  static Future<File> saveFromPath({
    required OcrResult result,
    required String originalImagePath,
    required Directory directory,
    String? fileName,
    OcrWatermark? watermark,
    int imageQuality = 90,
    OcrImageFormat? format,
  }) async {
    throw UnsupportedError(
      'saveFromPath is not supported on web. Use downloadBytes instead.',
    );
  }

  static Future<Uint8List> burnWatermark(
    Uint8List imageBytes,
    OcrWatermark watermark, {
    int quality = 90,
  }) async {
    return imageBytes;
  }

  static Future<Uint8List> compressImage(
    Uint8List imageBytes, {
    int quality = 80,
  }) async {
    return imageBytes;
  }

  static Future<Uint8List?> extractFace(Uint8List imageBytes) async => null;

  static Future<Uint8List?> extractFaceFromPath(String imagePath) async => null;

  static bool get isFaceExtractionSupported => false;

  static Future<Uint8List> correctOrientation(Uint8List imageBytes) async {
    return imageBytes;
  }

  static void _triggerDownload(Uint8List bytes, String name, String mimeType) {
    final blobParts = <web.BlobPart>[bytes.toJS as web.BlobPart].toJS;
    final blob = web.Blob(blobParts, web.BlobPropertyBag(type: mimeType));
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = name
      ..style.display = 'none';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
  }
}

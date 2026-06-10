import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';

import 'models/ocr_result.dart';
import 'ocr_platform_interface.dart';

@JS('Tesseract')
external JSObject? get _tesseract;

class FlutterOcrNativeWeb implements OcrPlatformInterface {
  static void registerWith([Object? _]) {}

  @override
  Future<OcrResult> recognizeFromPath(String imagePath) async {
    if (imagePath.trim().isEmpty) {
      throw ArgumentError('Image path cannot be empty');
    }
    final response = await _recognize(imagePath);
    return _toOcrResult(response);
  }

  @override
  Future<OcrResult> recognizeFromBytes(Uint8List bytes) async {
    if (bytes.isEmpty) {
      throw ArgumentError('Image bytes cannot be empty');
    }
    final response = await _recognize(_toDataUrl(bytes));
    return _toOcrResult(response);
  }

  @override
  Future<Uint8List?> renderPdfPage(
    Uint8List pdfBytes, {
    int page = 0,
    double scale = 2.0,
  }) async {
    return null;
  }

  @override
  Future<int> getPdfPageCount(Uint8List pdfBytes) async => 0;

  @override
  Future<void> dispose() async {}

  Future<dynamic> _recognize(dynamic imageSource) async {
    final tesseract = _tesseract;
    if (tesseract == null) {
      throw PlatformException(
        code: 'tesseract_not_loaded',
        message:
            'Tesseract.js is not loaded. Add the CDN script in web/index.html.',
      );
    }

    final recognize = _requireJsFunction(
      tesseract.getProperty('recognize'.toJS),
      code: 'tesseract_invalid_api',
      message: 'Tesseract.recognize is not available on window.',
    );

    final rawPromise = recognize.callAsFunction(
      tesseract,
      imageSource.toString().toJS,
      'eng'.toJS,
      _recognizeOptions(),
    );
    final promise = _requireJsPromise(
      rawPromise,
      code: 'tesseract_invalid_response',
      message: 'Tesseract.recognize did not return a Promise.',
    );
    return promise.toDart;
  }

  OcrResult _toOcrResult(dynamic rawResult) {
    final data = _readData(rawResult);
    final text = _extractText(data);
    final blocks =
        text.isEmpty ? <Map<String, dynamic>>[] : _parseBlocks(data, text);
    return OcrResult.fromMap({
      'text': text,
      'isPrinted': true,
      'blocks': blocks,
    });
  }

  JSObject _recognizeOptions() {
    final options = JSObject();
    // PSM 3 = fully automatic page segmentation (better for ID cards/documents).
    options.setProperty('tessedit_pageseg_mode'.toJS, 3.toJS);
    options.setProperty('preserve_interword_spaces'.toJS, '1'.toJS);
    return options;
  }

  Map<String, dynamic>? _readData(dynamic rawResult) {
    try {
      final resultObject = rawResult as JSObject;
      final data = resultObject.getProperty('data'.toJS);
      final dartified = data.dartify();
      if (dartified is Map) {
        return Map<String, dynamic>.from(dartified);
      }
    } catch (_) {}
    return null;
  }

  String _extractText(Map<String, dynamic>? data) {
    if (data == null) return '';
    final lines = data['lines'];
    if (lines is List && lines.isNotEmpty) {
      final lineTexts = lines
          .whereType<Map>()
          .map((line) => (line['text'] ?? '').toString().trim())
          .where((text) => text.isNotEmpty)
          .toList();
      if (lineTexts.isNotEmpty) {
        return lineTexts.join('\n');
      }
    }
    return (data['text'] ?? '').toString().trim();
  }

  List<Map<String, dynamic>> _parseBlocks(
    Map<String, dynamic>? data,
    String text,
  ) {
    final lines = _parseLines(data?['lines']);
    if (lines.isEmpty) {
      return [_fallbackBlock(text)];
    }
    return [
      {
        'text': text,
        'boundingBox': _mergeBoxes(lines),
        'lines': lines,
      },
    ];
  }

  List<Map<String, dynamic>> _parseLines(dynamic linesRaw) {
    if (linesRaw is! List) return const [];
    return linesRaw
        .whereType<Map>()
        .map((line) {
          final elements = _parseElements(line['words']);
          return <String, dynamic>{
            'text': (line['text'] ?? '').toString().trim(),
            'boundingBox':
                _readBoundingBox(line['bbox'], fallback: _mergeBoxes(elements)),
            'confidence': _normalizeConfidence(line['confidence']),
            'elements': elements,
          };
        })
        .where((line) => (line['text'] as String).isNotEmpty)
        .toList();
  }

  List<Map<String, dynamic>> _parseElements(dynamic wordsRaw) {
    if (wordsRaw is! List) return const [];
    return wordsRaw
        .whereType<Map>()
        .map((word) {
          return <String, dynamic>{
            'text': (word['text'] ?? '').toString().trim(),
            'boundingBox': _readBoundingBox(word['bbox']),
            'confidence': _normalizeConfidence(word['confidence']),
          };
        })
        .where((word) => (word['text'] as String).isNotEmpty)
        .toList();
  }

  double? _normalizeConfidence(dynamic value) {
    if (value is! num) return null;
    final confidence = value.toDouble();
    return confidence > 1.0 ? confidence / 100.0 : confidence;
  }

  Map<String, dynamic> _readBoundingBox(
    dynamic bbox, {
    Map<String, dynamic>? fallback,
  }) {
    if (bbox is Map) {
      final x0 = _toDouble(bbox['x0']);
      final y0 = _toDouble(bbox['y0']);
      final x1 = _toDouble(bbox['x1']);
      final y1 = _toDouble(bbox['y1']);
      return {
        'left': x0,
        'top': y0,
        'width': (x1 - x0).abs(),
        'height': (y1 - y0).abs(),
      };
    }
    return fallback ??
        const {'left': 0.0, 'top': 0.0, 'width': 0.0, 'height': 0.0};
  }

  double _toDouble(dynamic value) => (value as num?)?.toDouble() ?? 0.0;

  Map<String, dynamic> _mergeBoxes(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return const {'left': 0.0, 'top': 0.0, 'width': 0.0, 'height': 0.0};
    }
    var left = double.infinity;
    var top = double.infinity;
    var right = 0.0;
    var bottom = 0.0;

    for (final item in items) {
      final box = Map<String, dynamic>.from(item['boundingBox'] as Map);
      final x = _toDouble(box['left']);
      final y = _toDouble(box['top']);
      final width = _toDouble(box['width']);
      final height = _toDouble(box['height']);
      left = x < left ? x : left;
      top = y < top ? y : top;
      right = (x + width) > right ? (x + width) : right;
      bottom = (y + height) > bottom ? (y + height) : bottom;
    }

    return {
      'left': left,
      'top': top,
      'width': (right - left).abs(),
      'height': (bottom - top).abs(),
    };
  }

  /// Native platforms always return at least one block. The validator rejects
  /// results when [OcrResult.blocks] is empty, so web must mirror that shape.
  Map<String, dynamic> _fallbackBlock(String text) {
    const bbox = {'left': 0.0, 'top': 0.0, 'width': 0.0, 'height': 0.0};
    return {
      'text': text,
      'boundingBox': bbox,
      'lines': [
        {
          'text': text,
          'boundingBox': bbox,
          'confidence': 1.0,
          'elements': <Map<String, dynamic>>[],
        },
      ],
    };
  }

  String _toDataUrl(Uint8List bytes) {
    final mime = _detectMimeType(bytes);
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  String _detectMimeType(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return 'image/gif';
    }
    return 'image/png';
  }

  JSFunction _requireJsFunction(
    JSAny? value, {
    required String code,
    required String message,
  }) {
    try {
      return value as JSFunction;
    } catch (_) {
      throw PlatformException(code: code, message: message);
    }
  }

  JSPromise<JSAny?> _requireJsPromise(
    JSAny? value, {
    required String code,
    required String message,
  }) {
    try {
      return value as JSPromise<JSAny?>;
    } catch (_) {
      throw PlatformException(code: code, message: message);
    }
  }
}

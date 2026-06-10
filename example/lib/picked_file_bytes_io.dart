import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

Future<Uint8List?> readPickedFileBytes(PlatformFile file) async {
  final cached = file.bytes;
  if (cached != null) return cached;

  final path = file.path;
  if (path == null) return null;

  return File(path).readAsBytes();
}

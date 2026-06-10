import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

Future<Uint8List?> readPickedFileBytes(PlatformFile file) async => file.bytes;

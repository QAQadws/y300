import 'dart:typed_data';

import '../models/imported_font.dart';

abstract interface class FontRuntimeLoader {
  Future<String> load(ImportedFont font, Uint8List bytes);
}

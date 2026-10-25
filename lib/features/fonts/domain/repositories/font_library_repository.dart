import 'dart:typed_data';

import '../models/imported_font.dart';

abstract interface class FontLibraryRepository {
  /// Metadata includes unavailable entries so users can remove or repair them.
  Future<List<ImportedFont>> listFonts();

  Future<ImportedFont> importFont({
    required String fileName,
    required Uint8List bytes,
  });

  /// Verifies the file still matches its committed content identity.
  Future<Uint8List> readFont(String fontId);

  Future<void> deleteFont(String fontId);

  Stream<void> get changes;

  Future<void> dispose();
}

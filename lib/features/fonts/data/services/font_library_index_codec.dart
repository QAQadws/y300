import 'dart:convert';

import 'package:y300/features/fonts/domain/models/font_library_failure.dart';
import 'package:y300/features/fonts/domain/models/imported_font.dart';
import 'package:y300/features/fonts/domain/services/font_file_validator.dart';

/// The index contains metadata only. Private paths are derived from font IDs.
final class FontLibraryIndexCodec {
  const FontLibraryIndexCodec();

  static const version = 1;
  static const maxIndexBytes = 1024 * 1024;
  static const maxEntries = 4096;

  static final _fontIdPattern = RegExp(r'^[0-9a-f]{64}$');

  List<ImportedFont> decode(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FontLibraryException(FontLibraryFailure.corruptLibrary);
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FontLibraryException(FontLibraryFailure.corruptLibrary);
    }
    final storedVersion = decoded['version'];
    if (storedVersion is! int || storedVersion < 1) {
      throw const FontLibraryException(FontLibraryFailure.corruptLibrary);
    }
    if (storedVersion != version) {
      throw const FontLibraryException(
        FontLibraryFailure.unsupportedLibraryVersion,
      );
    }
    final entries = decoded['fonts'];
    if (entries is! List || entries.length > maxEntries) {
      throw const FontLibraryException(FontLibraryFailure.corruptLibrary);
    }
    final seenIds = <String>{};
    final fonts = <ImportedFont>[];
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) {
        throw const FontLibraryException(FontLibraryFailure.corruptLibrary);
      }
      final id = entry['id'];
      final name = entry['displayName'];
      final fileName = entry['storageFileName'];
      final byteLength = entry['byteLength'];
      if (id is! String ||
          !_fontIdPattern.hasMatch(id) ||
          !seenIds.add(id) ||
          name is! String ||
          name.trim().isEmpty ||
          name.length > 256 ||
          fileName is! String ||
          (fileName != '$id.ttf' && fileName != '$id.otf') ||
          byteLength is! int ||
          byteLength <= 0 ||
          byteLength > FontFileValidator.maxFontBytes) {
        throw const FontLibraryException(FontLibraryFailure.corruptLibrary);
      }
      fonts.add(
        ImportedFont(
          id: id,
          displayName: name,
          storageFileName: fileName,
          byteLength: byteLength,
        ),
      );
    }
    return List<ImportedFont>.unmodifiable(fonts);
  }

  String encode(List<ImportedFont> fonts) {
    final source = jsonEncode(<String, Object>{
      'version': version,
      'fonts': <Map<String, Object>>[
        for (final font in fonts)
          <String, Object>{
            'id': font.id,
            'displayName': font.displayName,
            'storageFileName': font.storageFileName,
            'byteLength': font.byteLength,
          },
      ],
    });
    // Treat writes with the same rules as restart reads, before touching disk.
    decode(source);
    if (utf8.encode(source).length > maxIndexBytes) {
      throw const FontLibraryException(FontLibraryFailure.storage);
    }
    return source;
  }
}

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/font_import_file.dart';
import '../../domain/models/font_library_failure.dart';
import '../../domain/services/font_file_validator.dart';
import '../../domain/services/font_import_picker.dart';

typedef PickFontFile = Future<PlatformFile?> Function();

final class FilePickerFontImportPicker implements FontImportPicker {
  FilePickerFontImportPicker({PickFontFile? pickFile})
    : _pickFile = pickFile ?? _pick;

  final PickFontFile _pickFile;

  @override
  Future<FontImportFile?> pickFont() async {
    try {
      final file = await _pickFile();
      if (file == null) return null;
      final extension = p.extension(file.name.trim()).toLowerCase();
      if (extension != '.ttf' && extension != '.otf') {
        throw const FontLibraryException(FontLibraryFailure.unsupportedFormat);
      }
      final knownLength = file.lengthSync();
      if (knownLength != null && knownLength > FontFileValidator.maxFontBytes) {
        throw const FontLibraryException(FontLibraryFailure.tooLarge);
      }
      final bytes = BytesBuilder();
      // A provider may report an unknown/stale length. Bound the actual stream
      // too, instead of asking the picker to materialize an arbitrary file.
      await for (final chunk in file.readAsByteStream()) {
        if (chunk.length > FontFileValidator.maxFontBytes - bytes.length) {
          throw const FontLibraryException(FontLibraryFailure.tooLarge);
        }
        bytes.add(chunk);
      }
      return FontImportFile(
        fileName: file.name,
        bytes: bytes.takeBytes().asUnmodifiableView(),
      );
    } on FontLibraryException {
      rethrow;
    } catch (_) {
      throw const FontLibraryException(FontLibraryFailure.storage);
    }
  }

  static Future<PlatformFile?> _pick() => FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['ttf', 'otf'],
  );
}

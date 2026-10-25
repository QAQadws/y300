import '../models/font_import_file.dart';

abstract interface class FontImportPicker {
  /// Cancellation is a normal null result, separate from an import failure.
  Future<FontImportFile?> pickFont();
}

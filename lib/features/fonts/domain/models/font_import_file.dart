import 'dart:typed_data';

/// Bytes captured from a single selection, without retaining an external path.
final class FontImportFile {
  const FontImportFile({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}

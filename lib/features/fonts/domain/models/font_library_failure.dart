enum FontLibraryFailure {
  unsupportedFormat,
  invalidFont,
  tooLarge,
  notFound,
  storage,
  corruptLibrary,
  unsupportedLibraryVersion,
  loadFailed,
}

final class FontLibraryException implements Exception {
  const FontLibraryException(this.code);

  final FontLibraryFailure code;

  @override
  String toString() => 'FontLibraryException(${code.name})';
}

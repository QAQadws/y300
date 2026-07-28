enum LibraryOperationFailureCode {
  workNotFound,
  chapterNotFound,
  unsupported,
  cacheWriteFailed,
  defaultCategoryImmutable,
}

/// Stable failure passed from library adapters to shared presentation.
///
/// [detail] is diagnostic-only and must be sanitized before display.
final class LibraryOperationException implements Exception {
  const LibraryOperationException(this.code, {this.detail});

  final LibraryOperationFailureCode code;
  final Object? detail;

  @override
  String toString() => 'LibraryOperationException(${code.name})';
}

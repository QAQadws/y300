/// A sanitized parsing failure that exposes only a stable diagnostic code.
final class DataParseException implements Exception {
  /// Creates a parsing failure identified by [code].
  const DataParseException(this.code);

  /// Stable, payload-free diagnostic code.
  final String code;
  @override
  String toString() => 'DataParseException($code)';
}

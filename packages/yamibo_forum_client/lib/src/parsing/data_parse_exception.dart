final class DataParseException implements Exception {
  const DataParseException(this.code);
  final String code;
  @override
  String toString() => 'DataParseException($code)';
}

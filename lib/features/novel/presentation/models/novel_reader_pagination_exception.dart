class NovelReaderPaginationException implements Exception {
  const NovelReaderPaginationException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;

  @override
  String toString() => 'NovelReaderPaginationException($code): $message';
}

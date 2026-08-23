final class ForumResponse<T> {
  const ForumResponse({
    required this.uri,
    required this.statusCode,
    required this.headers,
    required this.body,
  });
  final Uri uri;
  final int? statusCode;
  final Map<String, List<String>> headers;
  final T body;
}

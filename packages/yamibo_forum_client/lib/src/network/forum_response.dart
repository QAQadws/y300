/// Source-neutral forum response.
final class ForumResponse<T> {
  /// Creates a [ForumResponse].
  const ForumResponse({
    required this.uri,
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  /// Validated resolved URI.
  final Uri uri;

  /// HTTP status code when safely available.
  final int? statusCode;

  /// Headers.
  final Map<String, List<String>> headers;

  /// Response or request body in the declared representation.
  final T body;
}

/// Removes query credentials before a URI reaches a client-provided logger.
final class ForumLogUriRedactor {
  /// Creates a stateless URI redactor for transport diagnostics.
  const ForumLogUriRedactor();

  static const Set<String> _sensitiveQueryNames = <String>{
    'formhash',
    'uploadhash',
    'cookie',
    'auth',
    'token',
    'password',
    'passwd',
    'access_token',
    'refresh_token',
    'session',
    'sessionid',
    'sid',
    'sign',
  };

  /// Returns [uri] with credentials and sensitive query values removed.
  Uri redact(Uri uri) {
    final queryParts = <String>[];
    for (final entry in uri.queryParametersAll.entries) {
      final sensitive = _sensitiveQueryNames.contains(entry.key.toLowerCase());
      for (final value in entry.value) {
        queryParts.add(
          '${Uri.encodeQueryComponent(entry.key)}='
          '${Uri.encodeQueryComponent(sensitive ? '[REDACTED]' : value)}',
        );
      }
    }
    return uri.replace(
      userInfo: '',
      query: queryParts.isEmpty ? null : queryParts.join('&'),
    );
  }
}

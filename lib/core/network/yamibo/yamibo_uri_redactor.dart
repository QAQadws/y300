/// Redacts credentials that may accidentally appear in a request URI before
/// the URI reaches application logs.
final class YamiboUriRedactor {
  const YamiboUriRedactor();

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
  };

  Uri redact(Uri uri) {
    final queryParts = <String>[];
    for (final entry in uri.queryParametersAll.entries) {
      final name = entry.key;
      final redacted = _sensitiveQueryNames.contains(name.toLowerCase());
      for (final value in entry.value) {
        queryParts.add(
          '${Uri.encodeQueryComponent(name)}='
          '${Uri.encodeQueryComponent(redacted ? '[REDACTED]' : value)}',
        );
      }
    }

    return uri.replace(
      userInfo: '',
      query: queryParts.isEmpty ? null : queryParts.join('&'),
    );
  }
}

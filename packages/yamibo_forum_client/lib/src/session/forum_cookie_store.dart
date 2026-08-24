/// Persistent Cookie boundary used by the standalone network runtime.
abstract interface class ForumCookieStore {
  /// Reads cookies applicable to [uri] without exposing transport headers.
  Future<Map<String, String>> read(Uri uri);

  /// Merges normalized Cookie name/value pairs for [uri].
  Future<void> merge(Uri uri, Map<String, String> cookies);

  /// Parses and merges response `Set-Cookie` header values.
  Future<void> mergeSetCookie(Uri uri, List<String> headers);

  /// Removes all forum cookies managed by this store.
  Future<void> clear();
}

/// Ephemeral Cookie store for tests and short-lived tools.
final class MemoryForumCookieStore implements ForumCookieStore {
  final Map<String, Map<String, String>> _cookies =
      <String, Map<String, String>>{};
  @override
  Future<Map<String, String>> read(Uri uri) async =>
      Map.unmodifiable(_cookies[uri.host] ?? const <String, String>{});
  @override
  Future<void> merge(Uri uri, Map<String, String> cookies) async {
    final target = _cookies.putIfAbsent(uri.host, () => <String, String>{});
    for (final entry in cookies.entries) {
      if (entry.key.trim().isEmpty) continue;
      if (entry.value.trim().isEmpty ||
          entry.value.toLowerCase() == 'deleted') {
        target.remove(entry.key);
      } else {
        target[entry.key] = entry.value;
      }
    }
    if (target.isEmpty) _cookies.remove(uri.host);
  }

  @override
  Future<void> mergeSetCookie(Uri uri, List<String> headers) async {
    final values = <String, String>{};
    for (final header in headers) {
      final segments = header
          .split(';')
          .map((segment) => segment.trim())
          .where((segment) => segment.isNotEmpty)
          .toList(growable: false);
      if (segments.isEmpty) {
        continue;
      }
      final pair = segments.first;
      final index = pair.indexOf('=');
      if (index <= 0) {
        continue;
      }
      final name = pair.substring(0, index).trim();
      final value = pair.substring(index + 1).trim();
      var deleted = value.isEmpty || value.toLowerCase() == 'deleted';
      for (final attribute in segments.skip(1)) {
        final separator = attribute.indexOf('=');
        final key =
            (separator < 0 ? attribute : attribute.substring(0, separator))
                .trim()
                .toLowerCase();
        if (key == 'max-age' &&
            int.tryParse(
                  separator < 0
                      ? ''
                      : attribute.substring(separator + 1).trim(),
                ) ==
                0) {
          deleted = true;
        }
      }
      if (deleted) {
        values[name] = '';
      } else {
        values[name] = value;
      }
    }
    await merge(uri, values);
  }

  @override
  Future<void> clear() async => _cookies.clear();
}

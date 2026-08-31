import 'package:html/parser.dart' as html_parser;

/// Resolves and normalizes supported same-site thread and tag references.
///
/// Cross-site, malformed, or identity-ambiguous values fail closed instead of
/// leaking source-specific URL handling into application code.
class ForumReferenceResolver {
  /// Creates a [ForumReferenceResolver].
  const ForumReferenceResolver({this.siteOrigin = 'https://bbs.yamibo.com'});

  /// Site origin.
  final String siteOrigin;

  static final RegExp _numericId = RegExp(r'^\d+$');
  static final RegExp _threadPath = RegExp(
    r'(?:^|/)thread-(\d+)-\d+-\d+\.html$',
    caseSensitive: false,
  );
  static final RegExp _damagedTid = RegExp(
    r'(^|[?&;])tid=(\d+)(?:[&#]|$)',
    caseSensitive: false,
  );

  /// Resolves same site using the configured forum boundary.
  Uri? resolveSameSite(String value, {String? baseUrl}) {
    final decoded = (html_parser.parseFragment(value).text ?? '').trim();
    if (decoded.isEmpty) return null;
    final base = Uri.tryParse(baseUrl ?? _normalizedOrigin);
    final parsed = Uri.tryParse(decoded);
    if (base == null || parsed == null) return null;
    final resolved = parsed.isAbsolute ? parsed : base.resolveUri(parsed);
    return _isSameSite(resolved) ? resolved : null;
  }

  /// Extracts a stable thread identifier from a supported same-site reference.
  String? extractTid(String value, {String? baseUrl}) {
    final damaged = _damagedTid.firstMatch(value)?.group(2);
    if ((value.trim().startsWith(';tid=') || value.trim().startsWith('tid=')) &&
        damaged != null) {
      return damaged;
    }
    final uri = resolveSameSite(value, baseUrl: baseUrl);
    if (uri == null) return null;
    final pathMatch = _threadPath.firstMatch(uri.path);
    if (pathMatch != null) return pathMatch.group(1);
    final tid = _queryValue(uri, 'tid')?.trim();
    if (_endsWithPath(uri, 'forum.php') &&
        _queryValue(uri, 'mod')?.toLowerCase() == 'viewthread' &&
        tid != null &&
        _numericId.hasMatch(tid)) {
      return tid;
    }
    final apiTid = _queryValue(uri, 'tid')?.trim();
    if (_endsWithPath(uri, 'api/mobile/index.php') &&
        _queryValue(uri, 'module')?.toLowerCase() == 'viewthread' &&
        apiTid != null &&
        _numericId.hasMatch(apiTid)) {
      return apiTid;
    }
    return null;
  }

  /// Normalizes a supported same-site reference without unsafe parameters.
  String? normalizeHref(String value, {String? baseUrl}) {
    final trimmed = value.trim();
    final damaged = _damagedTid.firstMatch(trimmed)?.group(2);
    if ((trimmed.startsWith(';tid=') || trimmed.startsWith('tid=')) &&
        damaged != null) {
      return Uri.parse(_normalizedOrigin)
          .resolve('forum.php')
          .replace(
            queryParameters: <String, String>{
              'mod': 'viewthread',
              'tid': damaged,
            },
          )
          .toString();
    }
    final uri = resolveSameSite(value, baseUrl: baseUrl);
    if (uri == null) return null;
    final tid = extractTid(uri.toString());
    if (tid == null) return uri.toString();
    if (_threadPath.hasMatch(uri.path)) {
      return _withoutQueryAndFragment(uri).toString();
    }
    if (_endsWithPath(uri, 'api/mobile/index.php')) {
      return _withoutQueryAndFragment(uri)
          .replace(
            queryParameters: <String, String>{
              'module': 'viewthread',
              'tid': tid,
            },
          )
          .toString();
    }
    final fromUid = _queryValue(uri, 'fromuid')?.trim();
    return _withoutQueryAndFragment(uri)
        .replace(
          queryParameters: <String, String>{
            'mod': 'viewthread',
            'tid': tid,
            if (fromUid?.isNotEmpty == true) 'fromuid': fromUid!,
          },
        )
        .toString();
  }

  /// Extracts a stable thread identifier from a supported same-site reference.
  bool isThreadUrl(String value) => extractTid(value) != null;

  /// Whether the reference has a supported same-site thread shape.
  bool isSupportedThreadUrl(String value) {
    final uri = resolveSameSite(value);
    if (uri == null) return false;
    if (_threadPath.hasMatch(uri.path)) return true;
    if (_endsWithPath(uri, 'forum.php')) {
      return _queryValue(uri, 'mod')?.toLowerCase() == 'viewthread' &&
          _queryValue(uri, 'tid')?.trim().isNotEmpty == true;
    }
    return _endsWithPath(uri, 'api/mobile/index.php') &&
        _queryValue(uri, 'module')?.toLowerCase() == 'viewthread' &&
        _queryValue(uri, 'tid')?.trim().isNotEmpty == true;
  }

  /// Extracts a stable tag identifier from a supported same-site reference.
  String? extractTagId(String value, {String? baseUrl}) {
    final uri = resolveSameSite(value, baseUrl: baseUrl);
    if (uri == null || !_endsWithPath(uri, 'misc.php')) return null;
    final id = _queryValue(uri, 'id')?.trim();
    if (_queryValue(uri, 'mod')?.toLowerCase() != 'tag' ||
        id == null ||
        !_numericId.hasMatch(id)) {
      return null;
    }
    return id;
  }

  /// Extracts a one-based tag page, defaulting safely to page one.
  int extractTagPage(String value, {String? baseUrl}) {
    final uri = resolveSameSite(value, baseUrl: baseUrl);
    if (uri == null || extractTagId(uri.toString()) == null) return 1;
    final page = int.tryParse(_queryValue(uri, 'page')?.trim() ?? '');
    return page == null || page < 1 ? 1 : page;
  }

  /// Whether the value identifies a supported same-site tag catalog.
  bool isTagCatalogUrl(String value, {String? baseUrl}) =>
      extractTagId(value, baseUrl: baseUrl) != null;

  /// Normalizes a tag catalog reference to one explicit page.
  String? normalizeTagPageReference(
    String value, {
    int? page,
    String? baseUrl,
  }) {
    final uri = resolveSameSite(value, baseUrl: baseUrl);
    if (uri == null || extractTagId(uri.toString()) == null) return null;
    final parameters = _safeQueryParameters(uri)
      ..['mod'] = 'tag'
      ..['type'] = 'thread'
      ..['page'] = (page ?? extractTagPage(uri.toString())).toString();
    return _withoutQueryAndFragment(
      uri,
    ).replace(queryParameters: parameters).toString();
  }

  String get _normalizedOrigin {
    final parsed = Uri.parse(siteOrigin);
    return parsed.path.isEmpty || parsed.path.endsWith('/')
        ? parsed.toString()
        : parsed.replace(path: '${parsed.path}/').toString();
  }

  bool _isSameSite(Uri uri) {
    final origin = Uri.parse(siteOrigin);
    return (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.toLowerCase() == origin.host.toLowerCase();
  }

  bool _endsWithPath(Uri uri, String name) =>
      uri.path.toLowerCase().endsWith('/${name.toLowerCase()}');

  String? _queryValue(Uri uri, String key) {
    final expected = key.toLowerCase();
    for (final entry in _safeQueryParameters(uri).entries) {
      if (entry.key.toLowerCase() == expected) return entry.value;
    }
    return null;
  }

  /// Decodes query pairs independently so one legacy non-UTF8 value (most
  /// commonly Discuz's `highlight`) cannot hide otherwise valid identities.
  /// Malformed pairs are discarded rather than repaired or exposed downstream.
  Map<String, String> _safeQueryParameters(Uri uri) {
    final parameters = <String, String>{};
    for (final pair in uri.query.split('&')) {
      if (pair.isEmpty) continue;
      final separator = pair.indexOf('=');
      final encodedKey = separator < 0 ? pair : pair.substring(0, separator);
      final encodedValue = separator < 0 ? '' : pair.substring(separator + 1);
      try {
        final key = Uri.decodeQueryComponent(encodedKey);
        final value = Uri.decodeQueryComponent(encodedValue);
        parameters[key] = value;
      } on FormatException {
        // Fail closed for this pair while preserving other valid parameters.
      }
    }
    return parameters;
  }

  Uri _withoutQueryAndFragment(Uri uri) {
    final serialized = uri.toString();
    final queryIndex = serialized.indexOf('?');
    final fragmentIndex = serialized.indexOf('#');
    final cutAt = switch ((queryIndex, fragmentIndex)) {
      (< 0, < 0) => serialized.length,
      (final int query, < 0) => query,
      (< 0, final int fragment) => fragment,
      (final int query, final int fragment) =>
        query < fragment ? query : fragment,
    };
    return Uri.parse(serialized.substring(0, cutAt));
  }
}

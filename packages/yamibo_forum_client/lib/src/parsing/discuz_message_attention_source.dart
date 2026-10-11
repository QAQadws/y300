/// API versions whose public arrival variables are supported by extraction.
const discuzMessageAttentionApiVersions = <String>{'1', '2', '3', '4'};

/// Checks whether a URI identifies a supported, non-consuming HTML page.
///
/// Shared by pure extraction and network observation so a consuming request
/// cannot become a passive sample merely by redirecting to ordinary chrome.
bool acceptsDiscuzMessageAttentionHtmlSource(
  Uri uri, {
  required Uri siteOrigin,
}) {
  if (!_sameOrigin(uri, siteOrigin) || uri.hasFragment) return false;
  final query = _query(uri);
  if (query == null ||
      const [
        'inajax',
        'infloat',
        'action',
        'ac',
        'op',
      ].any(query.containsKey)) {
    return false;
  }
  return switch (uri.path) {
    '/index.php' || '/' => query['mod'] == null,
    '/forum.php' => const [
      null,
      'index',
      'forumdisplay',
      'viewthread',
      'guide',
    ].contains(query['mod']),
    '/home.php' =>
      query['mod'] == 'space' &&
          const [
            'profile',
            'thread',
            'blog',
            'album',
            'favorite',
            'friend',
            'feed',
          ].contains(query['do']),
    _ => false,
  };
}

/// Checks whether a URI identifies a supported, non-consuming API module.
bool acceptsDiscuzMessageAttentionApiSource(
  Uri uri, {
  required Uri siteOrigin,
}) {
  if (!_sameOrigin(uri, siteOrigin) ||
      uri.hasFragment ||
      uri.path != '/api/mobile/index.php') {
    return false;
  }
  final query = _query(uri);
  if (query == null ||
      const ['submodule', 'mod', 'do', 'action', 'op'].any(query.containsKey)) {
    return false;
  }
  final version = query['version'];
  if (version != null && !discuzMessageAttentionApiVersions.contains(version)) {
    return false;
  }
  // Unknown modules are not implicitly safe: lists consume arrival hints,
  // and authentication or command responses are not passive observations.
  return const {
    'forumindex',
    'forumdisplay',
    'viewthread',
    'profile',
    'myfavforum',
    'myfavthread',
    'smiley',
  }.contains(query['module']);
}

bool _sameOrigin(Uri uri, Uri siteOrigin) =>
    const {'http', 'https'}.contains(siteOrigin.scheme) &&
    siteOrigin.host.isNotEmpty &&
    siteOrigin.userInfo.isEmpty &&
    uri.scheme == siteOrigin.scheme &&
    uri.host.toLowerCase() == siteOrigin.host.toLowerCase() &&
    uri.port == siteOrigin.port &&
    uri.userInfo.isEmpty;

Map<String, String>? _query(Uri uri) {
  try {
    final values = uri.queryParametersAll;
    if (values.values.any((value) => value.length != 1)) return null;
    return values.map((key, value) => MapEntry(key, value.single));
  } on FormatException {
    return null;
  }
}

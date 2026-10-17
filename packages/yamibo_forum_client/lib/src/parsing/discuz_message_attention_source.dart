/// API versions whose public arrival variables are supported by extraction.
const discuzMessageAttentionApiVersions = <String>{'1', '2', '3', '4'};

/// Checks whether a URI identifies a supported, non-consuming HTML page.
///
/// Shared by pure extraction and network observation so a consuming request
/// cannot become a passive sample merely by redirecting to ordinary chrome.
/// A supported route alone is not evidence: the response must still contain
/// a complete, identity-verified public navigation shell.
bool acceptsDiscuzMessageAttentionHtmlSource(
  Uri uri, {
  required Uri siteOrigin,
}) {
  if (!_sameOrigin(uri, siteOrigin) || uri.hasFragment) return false;
  final query = _query(uri);
  if (query == null || _hasHtmlCommandOrFragment(query)) {
    return false;
  }
  final rewrite = _htmlRewrite(uri.path);
  if (rewrite != null) {
    // Discuz's generated rules append the original query. Do not guess which
    // duplicate routing value the web server/PHP would select.
    if (rewrite.query.keys.any(query.containsKey)) return false;
    return _acceptsHtmlRoute(rewrite.path, {...rewrite.query, ...query});
  }
  return _acceptsHtmlRoute(uri.path, query);
}

bool _acceptsHtmlRoute(String path, Map<String, String> query) =>
    switch (path) {
      '/index.php' || '/' => query['mod'] == null && _hasNoHtmlOperation(query),
      '/forum.php' => _acceptsForumHtml(query),
      '/home.php' => _acceptsHomeHtml(query),
      '/search.php' =>
        _hasNoHtmlOperation(query) &&
            const {
              null,
              'forum',
              'curforum',
              'newthread',
              'user',
              'group',
              'blog',
              'album',
              'portal',
              'collection',
            }.contains(query['mod']),
      '/misc.php' => _acceptsMiscHtml(query),
      '/portal.php' =>
        _hasNoHtmlOperation(query) &&
            const {
              null,
              'index',
              'list',
              'view',
              'comment',
              'topic',
            }.contains(query['mod']),
      '/group.php' =>
        _hasNoHtmlOperation(query) &&
            const {
              null,
              'index',
              'my',
              'attentiongroup',
            }.contains(query['mod']),
      _ => false,
    };

bool _hasHtmlCommandOrFragment(Map<String, String> query) =>
    const {
      'inajax',
      'infloat',
      'ajax',
      'formhash',
      'confirm',
      'delete',
      'ignore',
      'checknewpm',
      '_makehtml',
    }.any(query.containsKey) ||
    query.keys.any(
      // Searches use searchsubmit=yes without consuming a message hint. They
      // can still have the search service's ordinary indexing/credit effects.
      (key) => key.endsWith('submit') && key != 'searchsubmit',
    ) ||
    query['additional'] == 'removevlog';

bool _hasNoHtmlOperation(Map<String, String> query) =>
    !const {'action', 'ac', 'op'}.any(query.containsKey);

bool _acceptsForumHtml(Map<String, String> query) {
  if (query.containsKey('ac') || query.containsKey('op')) return false;
  final action = query['action'];
  return switch (query['mod']) {
    null ||
    'index' ||
    'forumdisplay' ||
    'viewthread' ||
    'guide' ||
    'announcement' ||
    'tag' => action == null,
    // These GETs only prepare a form. Command submissions, including GET
    // commands carrying formhash, were rejected before reaching this branch.
    'post' => const {'newthread', 'reply', 'edit'}.contains(action),
    'misc' => action == 'nav',
    'group' => const {
      null,
      'index',
      'viewmember',
      'memberlist',
    }.contains(action),
    _ => false,
  };
}

bool _acceptsHomeHtml(Map<String, String> query) {
  final module = query['mod'];
  if (module == 'spacecp') {
    if (query.containsKey('action')) return false;
    // An operation name is not inherently a write: existing editor/friend
    // preparation GETs include it. Keep the supported operations explicit;
    // e.g. friend addconfirm and PM checknewpm do mutate arrival state.
    return switch (query['ac']) {
      'blog' => const {null, '', 'edit'}.contains(query['op']),
      'friend' => query['op'] == 'add',
      'comment' => query['op'] == 'edit',
      _ => false,
    };
  }
  if (!_hasNoHtmlOperation(query)) return false;
  if (module == null) return query['do'] == null;
  if (module != 'space') return false;
  // An omitted do may be redirected to follow, which consumes notifications.
  // PM, notice and follow responses can retain the pre-consumption $_G member
  // snapshot even after their database flags have been cleared.
  return const {
    'index',
    'profile',
    'thread',
    'blog',
    'album',
    'favorite',
    'friend',
    'feed',
    'home',
    'doing',
    'share',
    'wall',
    'trade',
    'poll',
    'activity',
    'debate',
    'reward',
  }.contains(query['do']);
}

bool _acceptsMiscHtml(Map<String, String> query) {
  if (query.containsKey('ac')) return false;
  return switch (query['mod']) {
    'tag' => _hasNoHtmlOperation(query) && query['type'] != 'countitem',
    'faq' =>
      !query.containsKey('op') &&
          const {null, 'faq', 'search'}.contains(query['action']),
    'stat' =>
      !query.containsKey('action') &&
          !query.containsKey('exportexcel') &&
          const {
            null,
            'basic',
            'trade',
            'team',
            'trend',
            'modworks',
            'memberlist',
            'forumstat',
          }.contains(query['op']),
    'ranklist' => _hasNoHtmlOperation(query),
    _ => false,
  };
}

typedef _HtmlRewrite = ({String path, Map<String, String> query});

_HtmlRewrite? _htmlRewrite(String path) {
  // Discuz's default rewrite definitions map these
  // shapes to ordinary PHP reads; custom/plugin rewrites remain unsupported.
  final thread = _threadRewrite.firstMatch(path);
  if (thread != null) {
    return (
      path: '/forum.php',
      query: {
        'mod': 'viewthread',
        'tid': thread[1]!,
        'page': thread[2]!,
        'extra': 'page=${thread[3]!}',
      },
    );
  }
  final numbered = _numberedRewrite.firstMatch(path);
  if (numbered != null) {
    final kind = numbered[1]!;
    final id = numbered[2]!;
    final page = numbered[3]!;
    if (kind != 'forum' && !_rewriteNumber.hasMatch(id)) return null;
    return switch (kind) {
      'forum' => (
        path: '/forum.php',
        query: {'mod': 'forumdisplay', 'fid': id, 'page': page},
      ),
      'group' => (
        path: '/forum.php',
        query: {'mod': 'group', 'fid': id, 'page': page},
      ),
      'article' => (
        path: '/portal.php',
        query: {'mod': 'view', 'aid': id, 'page': page},
      ),
      'blog' => (
        path: '/home.php',
        query: {'mod': 'space', 'uid': id, 'do': 'blog', 'id': page},
      ),
      _ => null,
    };
  }
  final space = _spaceUidRewrite.firstMatch(path);
  if (space != null) {
    // Omitted do is intentionally not filled in: the server can choose follow
    // and consume notifications. An explicit safe do is checked by home rules.
    return (path: '/home.php', query: {'mod': 'space', 'uid': space[1]!});
  }
  final named = _namedRewrite.firstMatch(path);
  if (named == null) return null;
  final String value;
  try {
    value = Uri.decodeComponent(named[2]!);
  } on FormatException {
    return null;
  }
  // A name is data, never an encoded second path or query. Decline ambiguous
  // backreference escapes instead of projecting a different effective route.
  if (value.isEmpty || _rewriteNameDelimiter.hasMatch(value)) return null;
  return named[1] == 'topic'
      ? (path: '/portal.php', query: {'mod': 'topic', 'topic': value})
      : (path: '/home.php', query: {'mod': 'space', 'username': value});
}

final _threadRewrite = RegExp(r'^/thread-([0-9]+)-([0-9]+)-([0-9]+)\.html$');
final _numberedRewrite = RegExp(
  r'^/(forum|group|article|blog)-([A-Za-z0-9_]+)-([0-9]+)\.html$',
);
final _spaceUidRewrite = RegExp(r'^/space-uid-([0-9]+)\.html$');
final _namedRewrite = RegExp(r'^/(topic|space-username)-(.+)\.html$');
final _rewriteNumber = RegExp(r'^[0-9]+$');
final _rewriteNameDelimiter = RegExp(r'[\s/?#&=%\\]');

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

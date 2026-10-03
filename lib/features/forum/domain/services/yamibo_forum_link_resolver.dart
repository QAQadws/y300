import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

enum YamiboForumLinkKind {
  home,
  forumDisplay,
  search,
  thread,
  threadPost,
  tagThreadPage,
  userThreadDirectory,
  friendFeed,
  managedWebView,
  external,
}

class YamiboForumLinkDestination {
  const YamiboForumLinkDestination({
    required this.kind,
    required this.uri,
    this.tid,
    this.pid,
    this.page,
    this.tagId,
    this.userId,
    this.userThreadType,
    this.friendScope,
    this.forumId,
    this.searchScope,
  });

  final YamiboForumLinkKind kind;
  final Uri uri;
  final String? tid;
  final String? pid;
  final int? page;
  final String? tagId;
  final String? userId;
  final UserThreadDirectoryType? userThreadType;
  final ForumFriendFeedScope? friendScope;
  final String? forumId;
  final ForumSearchScope? searchScope;
}

class YamiboForumLinkResolver {
  const YamiboForumLinkResolver({
    SiteUrlResolver siteUrlResolver = const SiteUrlResolver(),
    ForumReferenceResolver references = const ForumReferenceResolver(),
  }) : _siteUrlResolver = siteUrlResolver,
       _references = references;

  final SiteUrlResolver _siteUrlResolver;
  final ForumReferenceResolver _references;

  /// Reads the verified viewer only when it can change route classification.
  /// Account providers may validate sessions remotely; ordinary links must not
  /// start that work just to choose a browser destination.
  YamiboForumLinkDestination? resolveForViewer(
    String rawUrl, {
    required String? Function() readViewerUserId,
  }) {
    final candidate = resolve(rawUrl);
    if (candidate == null) return null;
    if (candidate.kind == YamiboForumLinkKind.userThreadDirectory ||
        (candidate.kind == YamiboForumLinkKind.managedWebView &&
            _extractFriendFeed(
                  candidate.uri,
                  candidate.uri.queryParameters['uid'],
                ) !=
                null)) {
      return resolve(rawUrl, viewerUserId: readViewerUserId());
    }
    return candidate;
  }

  YamiboForumLinkDestination? resolve(String rawUrl, {String? viewerUserId}) {
    final normalizedUrl = _siteUrlResolver.resolve(rawUrl);
    if (normalizedUrl == null) {
      return null;
    }
    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null) {
      return null;
    }
    if (!_isYamiboSite(uri)) {
      return YamiboForumLinkDestination(
        kind: YamiboForumLinkKind.external,
        uri: uri,
      );
    }

    // Native pages must be able to retain the URL's full meaning. Ambiguous
    // origins, duplicate fields and unknown filters remain browser-owned.
    if (!_isNativeOrigin(uri) ||
        uri.queryParametersAll.values.any((values) => values.length != 1)) {
      return _browserDestination(uri);
    }

    final browsing = _extractBrowsingDestination(uri);
    if (browsing != null) return browsing;

    final friends = _extractFriendFeed(uri, viewerUserId);
    if (friends != null) return friends;

    final userThreads = _extractUserThreadDirectory(uri, viewerUserId);
    if (userThreads != null) return userThreads;

    final supportsThread = _supportsNativeThread(uri);
    final postTarget = supportsThread
        ? _extractThreadPostTarget(uri, normalizedUrl)
        : null;
    if (postTarget != null) {
      return YamiboForumLinkDestination(
        kind: YamiboForumLinkKind.threadPost,
        uri: uri,
        tid: postTarget.tid,
        pid: postTarget.pid,
        page: postTarget.page,
      );
    }

    final threadTid = supportsThread
        ? _references.extractTid(normalizedUrl)
        : null;
    if (threadTid != null && threadTid.isNotEmpty) {
      return YamiboForumLinkDestination(
        kind: YamiboForumLinkKind.thread,
        uri: uri,
        tid: threadTid,
        page:
            _parsePositiveInt(uri.queryParameters['page']) ??
            _parsePositiveInt(
              RegExp(
                r'thread-\d+-(\d+)-\d+\.html',
              ).firstMatch(uri.path)?.group(1),
            ),
      );
    }

    final tagId = _extractTagId(uri);
    if (tagId != null) {
      final tagUrl = _references.normalizeTagPageReference(normalizedUrl);
      if (tagUrl == null) return null;
      return YamiboForumLinkDestination(
        kind: YamiboForumLinkKind.tagThreadPage,
        uri: Uri.parse(tagUrl),
        tagId: tagId,
        page: _parsePositiveInt(uri.queryParameters['page']),
      );
    }

    return _browserDestination(uri);
  }

  YamiboForumLinkDestination _browserDestination(Uri uri) =>
      YamiboForumLinkDestination(
        kind: YamiboForumLinkKind.managedWebView,
        uri: uri,
      );

  bool _isNativeOrigin(Uri uri) =>
      {'https', 'http'}.contains(uri.scheme) &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == (uri.scheme == 'https' ? 443 : 80));

  bool _hasOnly(Uri uri, Set<String> keys) =>
      uri.queryParameters.keys.every(keys.contains);

  YamiboForumLinkDestination? _extractBrowsingDestination(Uri uri) {
    final query = uri.queryParameters;
    if (uri.fragment.isNotEmpty) return null;
    if (((uri.path == '/' || uri.path == '/index.php') &&
            _hasOnly(uri, {'mobile'})) ||
        (uri.path == '/forum.php' &&
            query['mod'] == 'index' &&
            _hasOnly(uri, {'mod', 'mobile'}))) {
      return YamiboForumLinkDestination(
        kind: YamiboForumLinkKind.home,
        uri: uri,
      );
    }
    final prettyForum = RegExp(
      r'^/forum-([1-9]\d*)-([1-9]\d*)\.html$',
    ).firstMatch(uri.path);
    final isForum =
        uri.path == '/forum.php' &&
        query['mod'] == 'forumdisplay' &&
        _hasOnly(uri, {'mod', 'fid', 'page', 'mobile'});
    final fid = isForum ? query['fid'] : prettyForum?.group(1);
    final page = isForum
        ? (query.containsKey('page') ? _parsePositiveInt(query['page']) : 1)
        : _parsePositiveInt(prettyForum?.group(2));
    if (fid != null &&
        RegExp(r'^[1-9]\d*$').hasMatch(fid) &&
        page != null &&
        (isForum || (prettyForum != null && _hasOnly(uri, {'mobile'})))) {
      return YamiboForumLinkDestination(
        kind: YamiboForumLinkKind.forumDisplay,
        uri: uri,
        forumId: fid,
        page: page,
      );
    }
    if (uri.path == '/search.php' &&
        {'forum', 'curforum'}.contains(query['mod']) &&
        _hasOnly(uri, {'mod', 'srhfid', 'mobile'})) {
      final fid = query['srhfid'];
      if (fid != null && !RegExp(r'^[1-9]\d*$').hasMatch(fid)) return null;
      if (query['mod'] == 'curforum' && fid == null) return null;
      return YamiboForumLinkDestination(
        kind: YamiboForumLinkKind.search,
        uri: uri,
        forumId: fid,
        searchScope: fid == null
            ? ForumSearchScope.allForums
            : ForumSearchScope.currentForum,
      );
    }
    return null;
  }

  bool _supportsNativeThread(Uri uri) {
    if (!_hasOnly(uri, {
      'mod',
      'tid',
      'page',
      'mobile',
      'extra',
      'fromuid',
      'goto',
      'ptid',
      'pid',
      'authorid',
      'ordertype',
      'viewpid',
      'ppp',
    })) {
      return false;
    }
    final query = uri.queryParameters;
    if (const [
      'authorid',
      'ordertype',
      'viewpid',
      'ppp',
    ].any(query.containsKey)) {
      // An explicit floor identity is re-located through the shared locator;
      // view filters and page hints are never mistaken for proof of location.
      if (_extractFragmentPid(uri) == null ||
          (query.containsKey('authorid') &&
              !RegExp(r'^[1-9]\d*$').hasMatch(query['authorid'] ?? '')) ||
          (query.containsKey('viewpid') &&
              !RegExp(r'^[1-9]\d*$').hasMatch(query['viewpid'] ?? '')) ||
          (query.containsKey('ppp') &&
              _parsePositiveInt(query['ppp']) == null) ||
          !{null, '1', '2'}.contains(query['ordertype'])) {
        return false;
      }
    }
    if (query.containsKey('page') && _parsePositiveInt(query['page']) == null) {
      return false;
    }
    if (uri.fragment.isNotEmpty &&
        !RegExp(
          r'^pid[1-9]\d*$',
          caseSensitive: false,
        ).hasMatch(uri.fragment)) {
      return false;
    }
    if (uri.path == '/forum.php') {
      if (query['mod'] == 'viewthread') {
        return RegExp(r'^[1-9]\d*$').hasMatch(query['tid'] ?? '') &&
            !query.containsKey('goto') &&
            !query.containsKey('ptid') &&
            !query.containsKey('pid');
      }
      return query['mod'] == 'redirect' &&
          query['goto'] == 'findpost' &&
          RegExp(r'^[1-9]\d*$').hasMatch(query['ptid'] ?? '') &&
          RegExp(r'^[1-9]\d*$').hasMatch(query['pid'] ?? '') &&
          !query.containsKey('tid');
    }
    return RegExp(
          r'^/thread-[1-9]\d*-[1-9]\d*-\d+\.html$',
          caseSensitive: false,
        ).hasMatch(uri.path) &&
        _hasOnly(uri, {'mobile', 'fromuid'});
  }

  YamiboForumLinkDestination? _extractFriendFeed(
    Uri uri,
    String? viewerUserId,
  ) {
    if (uri.path != '/home.php' ||
        !{'https', 'http'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80)) ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    final query = uri.queryParameters;
    if (query['mod'] != 'space' || query['do'] != 'friend') return null;
    const supportedKeys = {
      'mod',
      'do',
      'uid',
      'view',
      'type',
      'page',
      'mobile',
      'order',
    };
    if (query.keys.any((key) => !supportedKeys.contains(key)) ||
        uri.queryParametersAll.values.any((values) => values.length != 1) ||
        !{null, '', 'dateline'}.contains(query['order'])) {
      return null;
    }
    final uid = query['uid'];
    // The native feed is account-bound. Another user's public friend list
    // must never silently become the current account's private directory.
    if (uid != null &&
        (!RegExp(r'^[1-9]\d*$').hasMatch(uid) || uid != viewerUserId)) {
      return null;
    }
    final scope = switch (query['view']) {
      null || '' || 'me' => ForumFriendFeedScope.friends,
      'online' => ForumFriendFeedScope.online,
      'visitor' => ForumFriendFeedScope.visitors,
      'trace' => ForumFriendFeedScope.footprints,
      _ => null,
    };
    if (scope == null) return null;
    // Online's omitted type includes guests; the native tab shows members.
    if (scope == ForumFriendFeedScope.online
        ? query['type'] != 'member'
        : !{null, ''}.contains(query['type'])) {
      return null;
    }
    final rawPage = query['page'];
    final page = rawPage == null ? 1 : _parsePositiveInt(rawPage);
    if (page == null) return null;
    return YamiboForumLinkDestination(
      kind: YamiboForumLinkKind.friendFeed,
      uri: uri,
      userId: uid,
      friendScope: scope,
      page: page,
    );
  }

  YamiboForumLinkDestination? _extractUserThreadDirectory(
    Uri uri,
    String? viewerUserId,
  ) {
    if (uri.path != '/home.php' ||
        !{'https', 'http'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
      return null;
    }
    final query = uri.queryParameters;
    if (query['mod'] != 'space' || query['do'] != 'thread') return null;
    // Only map the personal/target-user directory. Other views, filters and
    // comment directories must retain their source behavior in the browser.
    const supportedKeys = {
      'mod',
      'do',
      'uid',
      'view',
      'type',
      'page',
      'mobile',
      'order',
    };
    if (query.keys.any((key) => !supportedKeys.contains(key)) ||
        uri.queryParametersAll.values.any((values) => values.length != 1) ||
        !{null, '', 'me'}.contains(query['view']) ||
        !{null, '', 'dateline'}.contains(query['order'])) {
      return null;
    }
    final uid = query['uid'];
    if (uid == null) {
      if (query['view'] != 'me') return null;
    } else if (!RegExp(r'^[1-9]\d*$').hasMatch(uid)) {
      return null;
    }
    // Unlike other-user spaces, Discuz defaults the viewer's own space to
    // the friends view. Only an explicit view=me identifies their directory.
    if (uid == viewerUserId && query['view'] != 'me') return null;
    final type = switch (query['type']) {
      null || '' || 'thread' => UserThreadDirectoryType.threads,
      'reply' => UserThreadDirectoryType.replies,
      _ => null,
    };
    if (type == null) return null;
    final page = _parsePositiveInt(query['page']);
    if (query.containsKey('page') && page == null) return null;
    return YamiboForumLinkDestination(
      kind: YamiboForumLinkKind.userThreadDirectory,
      uri: uri,
      userId: uid,
      userThreadType: type,
      page: page ?? 1,
    );
  }

  _ThreadPostTarget? _extractThreadPostTarget(Uri uri, String normalizedUrl) {
    if (!uri.path.toLowerCase().endsWith('forum.php')) {
      return _extractPrettyThreadPostTarget(uri, normalizedUrl);
    }
    final mod = uri.queryParameters['mod']?.toLowerCase();
    final goto = uri.queryParameters['goto']?.toLowerCase();
    if (mod == 'redirect' && goto == 'findpost') {
      final tid = uri.queryParameters['ptid']?.trim();
      final pid = uri.queryParameters['pid']?.trim();
      if (tid == null || tid.isEmpty || pid == null || pid.isEmpty) {
        return null;
      }
      return _ThreadPostTarget(tid: tid, pid: pid);
    }
    if (mod == 'viewthread') {
      final tid = uri.queryParameters['tid']?.trim();
      final pid = _extractFragmentPid(uri);
      if (tid == null || tid.isEmpty || pid == null || pid.isEmpty) {
        return null;
      }
      return _ThreadPostTarget(
        tid: tid,
        pid: pid,
        page: _parsePositiveInt(uri.queryParameters['page']),
      );
    }
    return null;
  }

  _ThreadPostTarget? _extractPrettyThreadPostTarget(
    Uri uri,
    String normalizedUrl,
  ) {
    final pid = _extractFragmentPid(uri);
    if (pid == null || pid.isEmpty) {
      return null;
    }
    final match = RegExp(
      r'thread-(\d+)-(\d+)-\d+\.html',
      caseSensitive: false,
    ).firstMatch(normalizedUrl);
    final tid = match?.group(1);
    if (tid == null || tid.isEmpty) {
      return null;
    }
    return _ThreadPostTarget(
      tid: tid,
      pid: pid,
      page: _parsePositiveInt(match?.group(2)),
    );
  }

  String? _extractFragmentPid(Uri uri) {
    final fragment = uri.fragment.trim();
    if (fragment.isEmpty) {
      return null;
    }
    return RegExp(
      r'pid(\d+)',
      caseSensitive: false,
    ).firstMatch(fragment)?.group(1);
  }

  int? _parsePositiveInt(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    return parsed == null || parsed <= 0 ? null : parsed;
  }

  String? _extractTagId(Uri uri) {
    if (uri.path != '/misc.php' ||
        !_hasOnly(uri, {'mod', 'id', 'type', 'page', 'mobile'}) ||
        !{null, '', 'thread'}.contains(uri.queryParameters['type']) ||
        uri.fragment.isNotEmpty ||
        (uri.queryParameters.containsKey('page') &&
            _parsePositiveInt(uri.queryParameters['page']) == null)) {
      return null;
    }
    if (uri.queryParameters['mod']?.toLowerCase() != 'tag') {
      return null;
    }
    return _references.extractTagId(uri.toString());
  }

  bool _isYamiboSite(Uri uri) {
    final siteHost = Uri.parse(AppConfig.siteBaseUrl).host.toLowerCase();
    return uri.host.toLowerCase() == siteHost;
  }
}

class _ThreadPostTarget {
  const _ThreadPostTarget({required this.tid, required this.pid, this.page});

  final String tid;
  final String pid;
  final int? page;
}

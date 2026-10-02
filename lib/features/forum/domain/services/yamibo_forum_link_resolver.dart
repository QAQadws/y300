import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

enum YamiboForumLinkKind {
  thread,
  threadPost,
  tagThreadPage,
  userThreadDirectory,
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
  });

  final YamiboForumLinkKind kind;
  final Uri uri;
  final String? tid;
  final String? pid;
  final int? page;
  final String? tagId;
  final String? userId;
  final UserThreadDirectoryType? userThreadType;
}

class YamiboForumLinkResolver {
  const YamiboForumLinkResolver({
    SiteUrlResolver siteUrlResolver = const SiteUrlResolver(),
    ForumReferenceResolver references = const ForumReferenceResolver(),
  }) : _siteUrlResolver = siteUrlResolver,
       _references = references;

  final SiteUrlResolver _siteUrlResolver;
  final ForumReferenceResolver _references;

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

    final userThreads = _extractUserThreadDirectory(uri, viewerUserId);
    if (userThreads != null) return userThreads;

    final postTarget = _extractThreadPostTarget(uri, normalizedUrl);
    if (postTarget != null) {
      return YamiboForumLinkDestination(
        kind: YamiboForumLinkKind.threadPost,
        uri: uri,
        tid: postTarget.tid,
        pid: postTarget.pid,
        page: postTarget.page,
      );
    }

    final threadTid = _references.extractTid(normalizedUrl);
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

    return YamiboForumLinkDestination(
      kind: YamiboForumLinkKind.managedWebView,
      uri: uri,
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
    if (!uri.path.toLowerCase().endsWith('misc.php')) {
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

import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/tags/domain/services/yamibo_tag_page_parsing.dart';
import 'package:y300/features/thread/domain/services/forum_thread_url_parser.dart';

enum YamiboForumLinkKind {
  thread,
  threadPost,
  tagThreadPage,
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
  });

  final YamiboForumLinkKind kind;
  final Uri uri;
  final String? tid;
  final String? pid;
  final int? page;
  final String? tagId;
}

class YamiboForumLinkResolver {
  const YamiboForumLinkResolver({
    SiteUrlResolver siteUrlResolver = const SiteUrlResolver(),
    ForumThreadUrlParser threadUrlParser = const ForumThreadUrlParser(),
    YamiboTagPageParsing tagPageParsing = const YamiboTagPageParsing(),
  }) : _siteUrlResolver = siteUrlResolver,
       _threadUrlParser = threadUrlParser,
       _tagPageParsing = tagPageParsing;

  final SiteUrlResolver _siteUrlResolver;
  final ForumThreadUrlParser _threadUrlParser;
  final YamiboTagPageParsing _tagPageParsing;

  YamiboForumLinkDestination? resolve(String rawUrl) {
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

    final threadTid = _threadUrlParser.extractTid(normalizedUrl);
    if (threadTid != null && threadTid.isNotEmpty) {
      return YamiboForumLinkDestination(
        kind: YamiboForumLinkKind.thread,
        uri: uri,
        tid: threadTid,
      );
    }

    final tagId = _extractTagId(uri);
    if (tagId != null) {
      final tagUrl = _tagPageParsing.normalizeCatalogEntryUrl(normalizedUrl);
      return YamiboForumLinkDestination(
        kind: YamiboForumLinkKind.tagThreadPage,
        uri: Uri.parse(tagUrl),
        tagId: tagId,
      );
    }

    return YamiboForumLinkDestination(
      kind: YamiboForumLinkKind.managedWebView,
      uri: uri,
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
    final id = uri.queryParameters['id']?.trim();
    return id == null || id.isEmpty ? null : id;
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

import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/tags/domain/services/yamibo_tag_page_parsing.dart';
import 'package:y300/features/thread/domain/services/forum_thread_url_parser.dart';

enum YamiboForumLinkKind { thread, tagThreadPage, managedWebView, external }

class YamiboForumLinkDestination {
  const YamiboForumLinkDestination({
    required this.kind,
    required this.uri,
    this.tid,
    this.tagId,
  });

  final YamiboForumLinkKind kind;
  final Uri uri;
  final String? tid;
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

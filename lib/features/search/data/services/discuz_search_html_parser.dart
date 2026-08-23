import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/search/domain/models/forum_search_models.dart';

final class DiscuzSearchHtmlParseException implements Exception {
  const DiscuzSearchHtmlParseException(this.code);

  final String code;

  @override
  String toString() => code;
}

final class DiscuzSearchUnauthorizedException implements Exception {
  const DiscuzSearchUnauthorizedException();
}

final class DiscuzSearchParsedPage {
  const DiscuzSearchParsedPage({
    required this.topics,
    required this.currentPage,
    required this.searchContextId,
    this.nextPageUri,
  });

  final List<ForumSearchTopicSummary> topics;
  final int currentPage;
  final String searchContextId;
  final Uri? nextPageUri;
}

final class DiscuzSearchHtmlParser {
  const DiscuzSearchHtmlParser();

  DiscuzSearchParsedPage parse({
    required String html,
    required Uri pageUri,
    required ForumSearchQuery query,
    required int requestedPage,
    required String expectedSearchContextId,
  }) {
    if (_looksLikeLoginPage(html)) {
      throw const DiscuzSearchUnauthorizedException();
    }
    if (requestedPage < 1) {
      throw const DiscuzSearchHtmlParseException('search_page_invalid');
    }

    final context = _validatePageUri(
      pageUri,
      query: query,
      expectedSearchContextId: expectedSearchContextId,
      requestedPage: requestedPage,
    );
    final document = html_parser.parse(html);
    final root = document.querySelector('.threadlist');
    if (root == null) {
      throw const DiscuzSearchHtmlParseException('search_root_missing');
    }

    final topics = <ForumSearchTopicSummary>[];
    final topicIds = <String>{};
    for (final row in root.querySelectorAll('li.list')) {
      final topic = _parseTopic(row, query);
      if (!topicIds.add(topic.tid)) {
        throw const DiscuzSearchHtmlParseException('search_topic_duplicated');
      }
      topics.add(topic);
    }

    final nextPageUri = _parseNextPageUri(
      document,
      query: query,
      expectedSearchContextId: context.searchContextId,
      currentPage: context.currentPage,
    );
    return DiscuzSearchParsedPage(
      topics: List<ForumSearchTopicSummary>.unmodifiable(topics),
      currentPage: context.currentPage,
      searchContextId: context.searchContextId,
      nextPageUri: nextPageUri,
    );
  }

  ForumSearchTopicSummary _parseTopic(
    html_dom.Element row,
    ForumSearchQuery query,
  ) {
    final threadAnchor = row.querySelector('a[href*="mod=viewthread"]');
    if (threadAnchor == null) {
      throw const DiscuzSearchHtmlParseException('search_topic_link_missing');
    }
    final threadUri = _parseThreadUri(threadAnchor.attributes['href']);
    final tidValues = threadUri.queryParametersAll['tid'] ?? const <String>[];
    final tid = tidValues.length == 1 ? tidValues.single.trim() : '';
    if (!_isPositiveInteger(tid)) {
      throw const DiscuzSearchHtmlParseException(
        'search_topic_identity_invalid',
      );
    }

    final title = _cleanText(
      (row.querySelector('.threadlist_tit em') ??
                  row.querySelector('.threadlist_tit'))
              ?.text ??
          '',
    );
    if (title.isEmpty) {
      throw const DiscuzSearchHtmlParseException('search_topic_title_missing');
    }

    final forumAnchor = row.querySelector(
      '.threadlist_foot a[href*="mod=forumdisplay"]',
    );
    final forum = _parseOptionalForum(forumAnchor);
    if (query.scope == ForumSearchScope.currentForum &&
        (forum?.id != query.normalizedForumId)) {
      throw const DiscuzSearchHtmlParseException(
        'search_forum_identity_mismatch',
      );
    }

    return ForumSearchTopicSummary(
      tid: tid,
      title: title,
      forumId: forum?.id,
      forumName: forum?.name,
      authorName: _emptyToNull(
        _cleanText(row.querySelector('.muser .mmc')?.text ?? ''),
      ),
      publishedAtText: _emptyToNull(
        _cleanText(row.querySelector('.muser .mtime')?.text ?? ''),
      ),
    );
  }

  _ForumSummary? _parseOptionalForum(html_dom.Element? anchor) {
    if (anchor == null) {
      return null;
    }
    final uri = _parseForumUri(anchor.attributes['href']);
    final forumIdValues = uri.queryParametersAll['fid'] ?? const <String>[];
    final forumId = forumIdValues.length == 1
        ? forumIdValues.single.trim()
        : '';
    if (!_isPositiveInteger(forumId)) {
      throw const DiscuzSearchHtmlParseException(
        'search_forum_identity_invalid',
      );
    }
    return _ForumSummary(
      id: forumId,
      name: _emptyToNull(_cleanText(anchor.text)),
    );
  }

  Uri _parseThreadUri(String? rawHref) {
    final uri = _resolveSameSite(rawHref);
    if (uri == null ||
        !uri.path.toLowerCase().endsWith('/forum.php') ||
        uri.queryParameters['mod']?.toLowerCase() != 'viewthread') {
      throw const DiscuzSearchHtmlParseException('search_topic_link_invalid');
    }
    return uri;
  }

  Uri _parseForumUri(String? rawHref) {
    final uri = _resolveSameSite(rawHref);
    if (uri == null ||
        !uri.path.toLowerCase().endsWith('/forum.php') ||
        uri.queryParameters['mod']?.toLowerCase() != 'forumdisplay') {
      throw const DiscuzSearchHtmlParseException('search_forum_link_invalid');
    }
    return uri;
  }

  Uri? _parseNextPageUri(
    html_dom.Document document, {
    required ForumSearchQuery query,
    required String expectedSearchContextId,
    required int currentPage,
  }) {
    final anchor = document.querySelector('.pg a.nxt');
    if (anchor == null) {
      return null;
    }
    final uri = _resolveSameSite(anchor.attributes['href']);
    if (uri == null || !uri.path.toLowerCase().endsWith('/search.php')) {
      throw const DiscuzSearchHtmlParseException('search_next_link_invalid');
    }
    final searchIdValues =
        uri.queryParametersAll['searchid'] ?? const <String>[];
    final pageValues = uri.queryParametersAll['page'] ?? const <String>[];
    final searchId = searchIdValues.length == 1
        ? searchIdValues.single.trim()
        : '';
    final pageText = pageValues.length == 1 ? pageValues.single.trim() : '';
    final page = int.tryParse(pageText);
    if (searchId != expectedSearchContextId ||
        page == null ||
        page < 1 ||
        page != currentPage + 1 ||
        !_matchesScope(uri, query)) {
      throw const DiscuzSearchHtmlParseException('search_next_context_invalid');
    }
    return uri;
  }

  _SearchPageContext _validatePageUri(
    Uri uri, {
    required ForumSearchQuery query,
    required String expectedSearchContextId,
    required int requestedPage,
  }) {
    final origin = Uri.parse('${AppConfig.siteBaseUrl}/');
    if (uri.scheme.toLowerCase() != origin.scheme ||
        uri.host.toLowerCase() != origin.host.toLowerCase() ||
        !uri.path.toLowerCase().endsWith('/search.php')) {
      throw const DiscuzSearchHtmlParseException('search_context_invalid');
    }
    final searchContextValues =
        uri.queryParametersAll['searchid'] ?? const <String>[];
    final searchContextId = searchContextValues.length == 1
        ? searchContextValues.single.trim()
        : '';
    if (searchContextId.isEmpty || searchContextId != expectedSearchContextId) {
      throw const DiscuzSearchHtmlParseException('search_context_missing');
    }
    final pageValues = uri.queryParametersAll['page'] ?? const <String>[];
    final pageText = pageValues.length > 1
        ? null
        : pageValues.isEmpty
        ? null
        : pageValues.single.trim();
    final page = pageText == null || pageText.isEmpty
        ? 1
        : int.tryParse(pageText);
    if (page == null || page < 1 || page != requestedPage) {
      throw const DiscuzSearchHtmlParseException('search_page_invalid');
    }
    if (!_matchesScope(uri, query)) {
      throw const DiscuzSearchHtmlParseException('search_scope_invalid');
    }
    return _SearchPageContext(
      searchContextId: searchContextId,
      currentPage: page,
    );
  }

  bool _matchesScope(Uri uri, ForumSearchQuery query) {
    final mod = uri.queryParameters['mod']?.toLowerCase();
    final forumIds = uri.queryParametersAll['srhfid'] ?? const <String>[];
    if (forumIds.length > 1) {
      return false;
    }
    return switch (query.scope) {
      ForumSearchScope.allForums => mod == 'forum',
      ForumSearchScope.currentForum => mod == 'curforum' || mod == 'forum',
        } &&
        (query.scope != ForumSearchScope.currentForum ||
            uri.queryParameters['srhfid'] == null ||
            uri.queryParameters['srhfid'] == query.normalizedForumId);
  }

  Uri? _resolveSameSite(String? rawHref) {
    var href = rawHref?.trim() ?? '';
    if (href.isEmpty) {
      return null;
    }
    while (href.contains('&amp;')) {
      href = href.replaceAll('&amp;', '&');
    }
    final parsed = Uri.tryParse(href);
    if (parsed == null) {
      return null;
    }
    final origin = Uri.parse('${AppConfig.siteBaseUrl}/');
    final resolved = parsed.hasScheme ? parsed : origin.resolveUri(parsed);
    if (resolved.scheme.toLowerCase() != origin.scheme ||
        resolved.host.toLowerCase() != origin.host.toLowerCase()) {
      return null;
    }
    return resolved;
  }

  bool _looksLikeLoginPage(String html) {
    final document = html_parser.parse(html);
    return document.querySelector(
          'form[action*="logging"], #lsform, .loginbox, input[name="password"]',
        ) !=
        null;
  }

  bool _isPositiveInteger(String value) {
    final parsed = int.tryParse(value);
    return parsed != null && parsed > 0;
  }

  String _cleanText(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String? _emptyToNull(String value) => value.isEmpty ? null : value;
}

final class _ForumSummary {
  const _ForumSummary({required this.id, this.name});

  final String id;
  final String? name;
}

final class _SearchPageContext {
  const _SearchPageContext({
    required this.searchContextId,
    required this.currentPage,
  });

  final String searchContextId;
  final int currentPage;
}

// ignore_for_file: public_member_api_docs

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../contracts/forum_search.dart';
import '../url/forum_uri_resolver.dart';
import 'discuz_search_context_validator.dart';

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
  DiscuzSearchHtmlParser({required Uri siteOrigin})
    : _resolver = ForumUriResolver(siteOrigin: siteOrigin),
      _contextValidator = DiscuzSearchContextValidator(siteOrigin: siteOrigin);

  final ForumUriResolver _resolver;
  final DiscuzSearchContextValidator _contextValidator;

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
    final ids = <String>{};
    for (final row in root.querySelectorAll('li.list')) {
      final topic = _parseTopic(row, query);
      if (!ids.add(topic.tid)) {
        throw const DiscuzSearchHtmlParseException('search_topic_duplicated');
      }
      topics.add(topic);
    }
    return DiscuzSearchParsedPage(
      topics: List.unmodifiable(topics),
      currentPage: context.currentPage,
      searchContextId: context.searchContextId,
      nextPageUri: _parseNextPageUri(
        document,
        query: query,
        expectedSearchContextId: context.searchContextId,
        currentPage: context.currentPage,
      ),
    );
  }

  ForumSearchTopicSummary _parseTopic(
    html_dom.Element row,
    ForumSearchQuery query,
  ) {
    final anchor = row.querySelector('a[href*="mod=viewthread"]');
    if (anchor == null) {
      throw const DiscuzSearchHtmlParseException('search_topic_link_missing');
    }
    final uri = _threadUri(anchor.attributes['href']);
    final values = uri.queryParametersAll['tid'] ?? const <String>[];
    final tid = values.length == 1 ? values.single.trim() : '';
    if (!_positive(tid)) {
      throw const DiscuzSearchHtmlParseException(
        'search_topic_identity_invalid',
      );
    }
    final title = _clean(
      (row.querySelector('.threadlist_tit em') ??
                  row.querySelector('.threadlist_tit'))
              ?.text ??
          '',
    );
    if (title.isEmpty) {
      throw const DiscuzSearchHtmlParseException('search_topic_title_missing');
    }
    final forum = _optionalForum(
      row.querySelector('.threadlist_foot a[href*="mod=forumdisplay"]'),
    );
    if (query.scope == ForumSearchScope.currentForum &&
        forum?.id != query.normalizedForumId) {
      throw const DiscuzSearchHtmlParseException(
        'search_forum_identity_mismatch',
      );
    }
    return ForumSearchTopicSummary(
      tid: tid,
      title: title,
      forumId: forum?.id,
      forumName: forum?.name,
      authorName: _nullable(
        _clean(row.querySelector('.muser .mmc')?.text ?? ''),
      ),
      publishedAtText: _nullable(
        _clean(row.querySelector('.muser .mtime')?.text ?? ''),
      ),
    );
  }

  _ForumSummary? _optionalForum(html_dom.Element? anchor) {
    if (anchor == null) return null;
    final uri = _forumUri(anchor.attributes['href']);
    final values = uri.queryParametersAll['fid'] ?? const <String>[];
    final id = values.length == 1 ? values.single.trim() : '';
    if (!_positive(id)) {
      throw const DiscuzSearchHtmlParseException(
        'search_forum_identity_invalid',
      );
    }
    return _ForumSummary(id: id, name: _nullable(_clean(anchor.text)));
  }

  Uri _threadUri(String? raw) {
    final uri = _sameSite(raw);
    if (uri == null ||
        uri.path.toLowerCase() != '/forum.php' ||
        uri.queryParameters['mod']?.toLowerCase() != 'viewthread') {
      throw const DiscuzSearchHtmlParseException('search_topic_link_invalid');
    }
    return uri;
  }

  Uri _forumUri(String? raw) {
    final uri = _sameSite(raw);
    if (uri == null ||
        uri.path.toLowerCase() != '/forum.php' ||
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
    if (anchor == null) return null;
    final uri = _sameSite(anchor.attributes['href']);
    if (uri == null || uri.path.toLowerCase() != '/search.php') {
      throw const DiscuzSearchHtmlParseException('search_next_link_invalid');
    }
    final validation = _contextValidator.validate(
      uri,
      query: query,
      expectedSearchId: expectedSearchContextId,
      expectedPage: currentPage + 1,
    );
    if (validation.context == null) {
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
    final validation = _contextValidator.validate(
      uri,
      query: query,
      expectedSearchId: expectedSearchContextId,
      expectedPage: requestedPage,
      allowImplicitFirstPage: true,
    );
    final context = validation.context;
    if (context != null) {
      return _SearchPageContext(
        searchContextId: context.searchId,
        currentPage: context.page,
      );
    }
    throw DiscuzSearchHtmlParseException(switch (validation.failure) {
      DiscuzSearchContextFailure.invalidUri => 'search_context_invalid',
      DiscuzSearchContextFailure.invalidSearchId => 'search_context_missing',
      DiscuzSearchContextFailure.invalidPage ||
      DiscuzSearchContextFailure.scopeMismatch => 'search_page_invalid',
      null => 'search_context_invalid',
    });
  }

  Uri? _sameSite(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    try {
      final uri = _resolver.resolve(value);
      return _resolver.isSameSite(uri) ? uri : null;
    } on FormatException {
      return null;
    }
  }

  bool _looksLikeLoginPage(String html) =>
      html_parser
          .parse(html)
          .querySelector(
            'form[action*="logging"], #lsform, .loginbox, input[name="password"]',
          ) !=
      null;
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

bool _positive(String value) {
  final parsed = int.tryParse(value);
  return parsed != null && parsed > 0;
}

String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
String? _nullable(String value) => value.isEmpty ? null : value;

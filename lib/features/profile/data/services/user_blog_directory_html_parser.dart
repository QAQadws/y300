import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/profile/domain/models/user_blog_models.dart';

final class ParsedUserBlogDirectory {
  const ParsedUserBlogDirectory({
    required this.data,
    required this.paginationPrecision,
  });

  final UserBlogDirectoryData data;
  final PaginationPrecision paginationPrecision;
}

final class UserBlogDirectoryHtmlParser {
  const UserBlogDirectoryHtmlParser();

  ParsedUserBlogDirectory parse({
    required String html,
    required UserBlogDirectoryQuery query,
    required String siteOrigin,
  }) {
    final document = html_parser.parse(html);
    final root = document.querySelector('.threadlist');
    if (root == null) {
      throw const FormatException('User blog directory root is missing.');
    }
    final activeScope = _parseActiveScope(document, siteOrigin);
    final activeOrder = activeScope == UserBlogFeedScope.public
        ? _parseActiveOrder(document, siteOrigin)
        : null;
    final expectedOrder = query.scope == UserBlogFeedScope.public
        ? (query.order ?? UserBlogOrder.latest)
        : null;
    if (activeScope != query.scope || activeOrder != expectedOrder) {
      throw const FormatException('User blog directory identity mismatch.');
    }

    final resolver = SiteUrlResolver(siteOrigin: siteOrigin);
    final items = <UserBlogSummary>[];
    final blogIds = <String>{};
    for (final row in _directListRows(root)) {
      final item = _parseItem(row, resolver, siteOrigin);
      if (!blogIds.add(item.blogId)) {
        throw const FormatException('Duplicate user blog identity.');
      }
      items.add(item);
    }
    final parsedPagination = _parsePagination(
      document,
      query: query,
      siteOrigin: siteOrigin,
    );
    return ParsedUserBlogDirectory(
      data: UserBlogDirectoryData(
        scope: activeScope,
        order: activeOrder,
        items: List<UserBlogSummary>.unmodifiable(items),
        pagination: parsedPagination.$1,
      ),
      paginationPrecision: parsedPagination.$2,
    );
  }

  UserBlogFeedScope _parseActiveScope(
    html_dom.Document document,
    String siteOrigin,
  ) {
    final active = document.querySelector('.dhnv a.mon, .dhnv .mon a');
    final uri = _validBlogUri(
      active?.attributes['href'],
      siteOrigin: siteOrigin,
    );
    return switch (uri?.queryParameters['view']) {
      'we' => UserBlogFeedScope.friends,
      'me' => UserBlogFeedScope.self,
      'all' => UserBlogFeedScope.public,
      _ => throw const FormatException('Active user blog scope is missing.'),
    };
  }

  UserBlogOrder _parseActiveOrder(
    html_dom.Document document,
    String siteOrigin,
  ) {
    final active = document.querySelector(
      '#dhnavs_li li.mon a, #dhnavs_li a.mon',
    );
    final uri = _validBlogUri(
      active?.attributes['href'],
      siteOrigin: siteOrigin,
    );
    if (uri == null) {
      throw const FormatException('Active user blog order is missing.');
    }
    return switch (uri.queryParameters['order']) {
      null || '' || 'dateline' => UserBlogOrder.latest,
      'hot' => UserBlogOrder.recommended,
      _ => throw const FormatException('Active user blog order is invalid.'),
    };
  }

  UserBlogSummary _parseItem(
    html_dom.Element row,
    SiteUrlResolver resolver,
    String siteOrigin,
  ) {
    final blogAnchor = row.querySelector('a[href*="do=blog"][href*="id="]');
    final blogUri = _validBlogUri(
      blogAnchor?.attributes['href'],
      siteOrigin: siteOrigin,
    );
    final blogId = blogUri?.queryParameters['id']?.trim() ?? '';
    final ownerUserId = blogUri?.queryParameters['uid']?.trim() ?? '';
    final title = _cleanText(row.querySelector('.threadlist_tit')?.text ?? '');
    if (blogId.isEmpty || ownerUserId.isEmpty || title.isEmpty) {
      throw const FormatException('User blog entry identity is invalid.');
    }

    final authorAnchor = row.querySelector('.muser h3 a');
    final authorUserId = _userIdFromProfileUrl(
      authorAnchor?.attributes['href'],
      siteOrigin: siteOrigin,
    );
    if (authorUserId != null &&
        authorUserId.isNotEmpty &&
        authorUserId != ownerUserId) {
      throw const FormatException('User blog owner identity mismatch.');
    }
    return UserBlogSummary(
      blogId: blogId,
      ownerUserId: ownerUserId,
      title: title,
      authorName: _optionalText(authorAnchor?.text),
      excerpt: _optionalText(row.querySelector('.threadlist_mes')?.text),
      avatarUrl: _resolve(
        resolver,
        row.querySelector('.avatar img')?.attributes['src'],
      ),
      publishedAtText: _optionalText(row.querySelector('.mtime span')?.text),
    );
  }

  (UserBlogPagination, PaginationPrecision) _parsePagination(
    html_dom.Document document, {
    required UserBlogDirectoryQuery query,
    required String siteOrigin,
  }) {
    final container = document.querySelector('.pg');
    if (container == null) {
      if (query.page != 1) {
        throw const FormatException('User blog current page is unverified.');
      }
      return (
        const UserBlogPagination(currentPage: 1),
        PaginationPrecision.unknown,
      );
    }
    final currentPage = _strictPositiveInt(
      _cleanText(container.querySelector('strong')?.text ?? ''),
      field: 'current page',
    );
    if (currentPage != query.page) {
      throw const FormatException('User blog page identity mismatch.');
    }
    final totalNode = container.querySelector('label span');
    int? totalPages;
    if (totalNode != null) {
      final match = RegExp(r'(\d+)\s*页').firstMatch(_cleanText(totalNode.text));
      if (match == null) {
        throw const FormatException('User blog total pages are invalid.');
      }
      totalPages = _strictPositiveInt(match.group(1)!, field: 'total pages');
      if (currentPage > totalPages) {
        throw const FormatException('User blog pagination is inconsistent.');
      }
    }

    final previous = container.querySelector('a.prev');
    final next = container.querySelector('a.nxt');
    if (previous != null) {
      _validatePageLink(
        previous,
        query: query,
        siteOrigin: siteOrigin,
        expectedPage: currentPage - 1,
      );
    }
    if (next != null) {
      _validatePageLink(
        next,
        query: query,
        siteOrigin: siteOrigin,
        expectedPage: currentPage + 1,
      );
    }
    final hasPrevious = totalPages != null
        ? currentPage > 1
        : previous == null
        ? null
        : true;
    final hasNext = totalPages != null
        ? currentPage < totalPages
        : next == null
        ? null
        : true;
    final precision = totalPages != null
        ? PaginationPrecision.exact
        : previous != null || next != null
        ? PaginationPrecision.directional
        : PaginationPrecision.unknown;
    return (
      UserBlogPagination(
        currentPage: currentPage,
        totalPages: totalPages,
        hasPrevious: hasPrevious,
        hasNext: hasNext,
      ),
      precision,
    );
  }

  void _validatePageLink(
    html_dom.Element anchor, {
    required UserBlogDirectoryQuery query,
    required String siteOrigin,
    required int expectedPage,
  }) {
    final uri = _validBlogUri(
      anchor.attributes['href'],
      siteOrigin: siteOrigin,
    );
    final page = int.tryParse(uri?.queryParameters['page'] ?? '');
    final scope = switch (uri?.queryParameters['view']) {
      'we' => UserBlogFeedScope.friends,
      'me' => UserBlogFeedScope.self,
      'all' => UserBlogFeedScope.public,
      _ => null,
    };
    final order = switch (uri?.queryParameters['order']) {
      null || '' || 'dateline' => UserBlogOrder.latest,
      'hot' => UserBlogOrder.recommended,
      _ => null,
    };
    final expectedOrder = query.scope == UserBlogFeedScope.public
        ? (query.order ?? UserBlogOrder.latest)
        : UserBlogOrder.latest;
    final hasOrderParameter =
        uri?.queryParameters.containsKey('order') ?? false;
    if (uri == null ||
        page == null ||
        page != expectedPage ||
        scope != query.scope ||
        (query.scope == UserBlogFeedScope.public && order != expectedOrder) ||
        (query.scope != UserBlogFeedScope.public && hasOrderParameter)) {
      throw const FormatException('User blog pagination link is invalid.');
    }
  }

  Iterable<html_dom.Element> _directListRows(html_dom.Element root) sync* {
    for (final child in root.children) {
      if (child.localName != 'ul') {
        continue;
      }
      for (final row in child.children) {
        if (row.localName == 'li' && row.classes.contains('list')) {
          yield row;
        }
      }
    }
  }

  Uri? _validBlogUri(String? raw, {required String siteOrigin}) {
    final uri = _sameOriginUri(raw, siteOrigin: siteOrigin);
    if (uri == null ||
        !uri.path.endsWith('home.php') ||
        uri.queryParameters['mod'] != 'space' ||
        uri.queryParameters['do'] != 'blog') {
      return null;
    }
    return uri;
  }

  String? _userIdFromProfileUrl(String? raw, {required String siteOrigin}) {
    final uri = _sameOriginUri(raw, siteOrigin: siteOrigin);
    if (uri == null ||
        !uri.path.endsWith('home.php') ||
        uri.queryParameters['mod'] != 'space') {
      return null;
    }
    final value = uri.queryParameters['uid']?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Uri? _sameOriginUri(String? raw, {required String siteOrigin}) {
    final resolved = SiteUrlResolver(
      siteOrigin: siteOrigin,
    ).resolve(raw?.replaceAll('&amp;', '&') ?? '');
    final uri = Uri.tryParse(resolved ?? '');
    final expected = Uri.tryParse(siteOrigin);
    if (uri == null ||
        expected == null ||
        !uri.hasScheme ||
        uri.origin != expected.origin) {
      return null;
    }
    return uri;
  }

  int _strictPositiveInt(String value, {required String field}) {
    if (!RegExp(r'^\d+$').hasMatch(value)) {
      throw FormatException('User blog $field is invalid.');
    }
    final parsed = int.tryParse(value);
    if (parsed == null || parsed < 1) {
      throw FormatException('User blog $field is invalid.');
    }
    return parsed;
  }

  String? _resolve(SiteUrlResolver resolver, String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return resolver.resolve(raw);
  }

  String? _optionalText(String? value) {
    final normalized = _cleanText(value ?? '');
    return normalized.isEmpty ? null : normalized;
  }

  String _cleanText(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

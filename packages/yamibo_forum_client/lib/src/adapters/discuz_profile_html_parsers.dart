import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../contracts/data_read_contract.dart';
import '../contracts/profile_and_blog.dart';
import '../url/forum_uri_resolver.dart';

abstract final class DiscuzProfileAuthPageDetector {
  static bool isLoginPage(String html) {
    final document = html_parser.parse(html);
    return document.querySelector(
          'form#loginform, form[name="login"], .loginbox',
        ) !=
        null;
  }
}

final class ForumUserProfileHtmlParser {
  const ForumUserProfileHtmlParser({required this.siteOrigin});

  final Uri siteOrigin;

  ForumUserProfileData parse({
    required String html,
    required String expectedUserId,
  }) {
    final document = html_parser.parse(html);
    final root = document.querySelector('.userinfo');
    if (root == null) {
      throw const FormatException('profile_root_missing');
    }
    final username = _clean(root.querySelector('h2.name')?.text ?? '');
    if (username.isEmpty) {
      throw const FormatException('profile_name_missing');
    }
    final details = _details(root);
    final ids = details
        .where((item) => item.label.toUpperCase() == 'UID')
        .map((item) => item.value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (ids.length != 1 || ids.single != expectedUserId.trim()) {
      throw const FormatException('profile_identity_mismatch');
    }
    final resolver = ForumUriResolver(siteOrigin: siteOrigin);
    return ForumUserProfileData(
      identity: ProfileUserIdentity(userId: ids.single, displayName: username),
      avatarUrl: _optionalUri(
        resolver,
        root.querySelector('.avatar_m img')?.attributes['src'],
      ),
      coverUrl: _cover(document, resolver),
      signatureHtml: _optionalMarkup(
        root.querySelector('.myinfo_list li.sig')?.innerHtml,
      ),
      metrics: List.unmodifiable(_metrics(root)),
      details: List.unmodifiable(details),
    );
  }

  List<ForumUserProfileMetric> _metrics(html_dom.Element root) => root
      .querySelectorAll('.user_box li')
      .map((item) {
        final valueNode = item.querySelector('span');
        final value = _clean(valueNode?.text ?? '');
        final label = _clean(item.text.replaceFirst(value, ''));
        if (label.isEmpty || value.isEmpty) {
          throw const FormatException('profile_metric_invalid');
        }
        return ForumUserProfileMetric(label: label, value: value);
      })
      .toList(growable: false);

  List<ForumUserProfileDetail> _details(html_dom.Element root) {
    html_dom.Element? section;
    for (final candidate in root.querySelectorAll('.myinfo_list')) {
      if (candidate.querySelectorAll('li').any((item) {
        final valueNode = item.querySelector('span');
        final label = _clean(
          item.nodes
              .takeWhile((node) => node != valueNode)
              .map((node) => node.text)
              .join(),
        );
        return label.toUpperCase() == 'UID';
      })) {
        section = candidate;
        break;
      }
    }
    if (section == null) {
      throw const FormatException('profile_details_missing');
    }
    final output = <ForumUserProfileDetail>[];
    for (final item in section.querySelectorAll('li')) {
      if (item.querySelector('b') != null) continue;
      final valueNode = item.querySelector('span');
      final value = _clean(valueNode?.text ?? '');
      final label = _clean(
        item.nodes
            .takeWhile((node) => node != valueNode)
            .map((node) => node.text)
            .join(),
      );
      if (label.isEmpty || value.isEmpty) {
        throw const FormatException('profile_detail_invalid');
      }
      output.add(ForumUserProfileDetail(label: label, value: value));
    }
    return output;
  }

  String? _cover(html_dom.Document document, ForumUriResolver resolver) {
    for (final style in document.querySelectorAll('style')) {
      for (final rule in RegExp(
        r'([^{}]+)\{([^{}]*)\}',
      ).allMatches(style.text)) {
        final targetsAvatar = rule
            .group(1)!
            .split(',')
            .any(
              (selector) => RegExp(
                r'(^|[^\w-])\.user_avatar(?![\w-])',
                caseSensitive: false,
              ).hasMatch(selector),
            );
        if (!targetsAvatar) continue;
        final match = RegExp(
          r'background-image:\s*url\(([^)]+)\)',
          caseSensitive: false,
        ).firstMatch(rule.group(2)!);
        final value = match
            ?.group(1)
            ?.trim()
            .replaceAll('"', '')
            .replaceAll("'", '');
        final resolved = _optionalUri(resolver, value);
        if (resolved != null) return resolved;
      }
    }
    return null;
  }
}

final class ParsedUserBlogDirectory {
  const ParsedUserBlogDirectory({
    required this.data,
    required this.paginationPrecision,
  });

  final UserBlogDirectoryData data;
  final PaginationPrecision paginationPrecision;
}

final class UserBlogDirectoryHtmlParser {
  const UserBlogDirectoryHtmlParser({required this.siteOrigin});

  final Uri siteOrigin;

  ParsedUserBlogDirectory parse({
    required String html,
    required UserBlogDirectoryQuery query,
  }) {
    final document = html_parser.parse(html);
    final root = document.querySelector('.threadlist');
    if (root == null) {
      throw const FormatException('blog_directory_root_missing');
    }
    final scope = _activeScope(document);
    final order = scope == UserBlogFeedScope.public
        ? _activeOrder(document)
        : null;
    final expectedOrder = query.scope == UserBlogFeedScope.public
        ? (query.order ?? UserBlogOrder.latest)
        : null;
    if (scope != query.scope || order != expectedOrder) {
      throw const FormatException('blog_directory_identity_mismatch');
    }
    final resolver = ForumUriResolver(siteOrigin: siteOrigin);
    final items = <UserBlogSummary>[];
    final ids = <String>{};
    for (final row in _directRows(root)) {
      final item = _item(row, resolver);
      if (!ids.add(item.blogId)) {
        throw const FormatException('blog_identity_duplicate');
      }
      items.add(item);
    }
    final pagination = _pagination(document, query);
    return ParsedUserBlogDirectory(
      data: UserBlogDirectoryData(
        scope: scope,
        order: order,
        items: List.unmodifiable(items),
        pagination: pagination.$1,
      ),
      paginationPrecision: pagination.$2,
    );
  }

  UserBlogFeedScope _activeScope(html_dom.Document document) {
    final uri = _validBlogUri(
      document.querySelector('.dhnv a.mon, .dhnv .mon a')?.attributes['href'],
    );
    return switch (uri?.queryParameters['view']) {
      'we' => UserBlogFeedScope.friends,
      'me' => UserBlogFeedScope.self,
      'all' => UserBlogFeedScope.public,
      _ => throw const FormatException('blog_scope_missing'),
    };
  }

  UserBlogOrder _activeOrder(html_dom.Document document) {
    final uri = _validBlogUri(
      document
          .querySelector('#dhnavs_li li.mon a, #dhnavs_li a.mon')
          ?.attributes['href'],
    );
    if (uri == null) throw const FormatException('blog_order_missing');
    return switch (uri.queryParameters['order']) {
      null || '' || 'dateline' => UserBlogOrder.latest,
      'hot' => UserBlogOrder.recommended,
      _ => throw const FormatException('blog_order_invalid'),
    };
  }

  UserBlogSummary _item(html_dom.Element row, ForumUriResolver resolver) {
    final uri = _validBlogUri(
      row.querySelector('a[href*="do=blog"][href*="id="]')?.attributes['href'],
    );
    final blogId = uri?.queryParameters['id']?.trim() ?? '';
    final ownerId = uri?.queryParameters['uid']?.trim() ?? '';
    final title = _clean(row.querySelector('.threadlist_tit')?.text ?? '');
    if (blogId.isEmpty || ownerId.isEmpty || title.isEmpty) {
      throw const FormatException('blog_entry_identity_invalid');
    }
    final author = row.querySelector('.muser h3 a');
    final authorId = _profileUserId(author?.attributes['href']);
    if (authorId != null && authorId != ownerId) {
      throw const FormatException('blog_owner_identity_mismatch');
    }
    return UserBlogSummary(
      blogId: blogId,
      ownerUserId: ownerId,
      title: title,
      authorName: _optionalText(author?.text),
      excerpt: _optionalText(row.querySelector('.threadlist_mes')?.text),
      avatarUrl: _optionalUri(
        resolver,
        row.querySelector('.avatar img')?.attributes['src'],
      ),
      publishedAtText: _optionalText(row.querySelector('.mtime span')?.text),
    );
  }

  (UserBlogPagination, PaginationPrecision) _pagination(
    html_dom.Document document,
    UserBlogDirectoryQuery query,
  ) {
    final container = document.querySelector('.pg');
    if (container == null) {
      if (query.page != 1) {
        throw const FormatException('blog_page_unverified');
      }
      return (
        const UserBlogPagination(currentPage: 1),
        PaginationPrecision.unknown,
      );
    }
    final current = _positiveInt(
      _clean(container.querySelector('strong')?.text ?? ''),
    );
    if (current != query.page) {
      throw const FormatException('blog_page_identity_mismatch');
    }
    int? total;
    final totalNode = container.querySelector('label span');
    if (totalNode != null) {
      final match = RegExp(r'(\d+)\s*页').firstMatch(_clean(totalNode.text));
      if (match == null) throw const FormatException('blog_total_invalid');
      total = _positiveInt(match.group(1)!);
      if (current > total) {
        throw const FormatException('blog_pagination_inconsistent');
      }
    }
    final previous = container.querySelector('a.prev');
    final next = container.querySelector('a.nxt');
    if (previous != null) {
      _validatePageLink(previous, query, current - 1);
    }
    if (next != null) _validatePageLink(next, query, current + 1);
    return (
      UserBlogPagination(
        currentPage: current,
        totalPages: total,
        hasPrevious: total != null
            ? current > 1
            : previous == null
            ? null
            : true,
        hasNext: total != null
            ? current < total
            : next == null
            ? null
            : true,
      ),
      total != null
          ? PaginationPrecision.exact
          : previous != null || next != null
          ? PaginationPrecision.directional
          : PaginationPrecision.unknown,
    );
  }

  void _validatePageLink(
    html_dom.Element anchor,
    UserBlogDirectoryQuery query,
    int expectedPage,
  ) {
    final uri = _validBlogUri(anchor.attributes['href']);
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
    final hasOrder = uri?.queryParameters.containsKey('order') ?? false;
    if (uri == null ||
        page != expectedPage ||
        scope != query.scope ||
        (query.scope == UserBlogFeedScope.public && order != expectedOrder) ||
        (query.scope != UserBlogFeedScope.public && hasOrder)) {
      throw const FormatException('blog_pagination_link_invalid');
    }
  }

  Iterable<html_dom.Element> _directRows(html_dom.Element root) sync* {
    for (final child in root.children) {
      if (child.localName != 'ul') continue;
      for (final row in child.children) {
        if (row.localName == 'li' && row.classes.contains('list')) yield row;
      }
    }
  }

  Uri? _validBlogUri(String? raw) {
    final uri = _sameSite(raw, siteOrigin);
    if (uri == null ||
        !uri.path.endsWith('home.php') ||
        uri.queryParameters['mod'] != 'space' ||
        uri.queryParameters['do'] != 'blog') {
      return null;
    }
    return uri;
  }

  String? _profileUserId(String? raw) {
    final uri = _sameSite(raw, siteOrigin);
    if (uri == null ||
        !uri.path.endsWith('home.php') ||
        uri.queryParameters['mod'] != 'space') {
      return null;
    }
    return _optionalText(uri.queryParameters['uid']);
  }
}

final class UserBlogDetailHtmlParser {
  const UserBlogDetailHtmlParser({required this.siteOrigin});

  final Uri siteOrigin;

  UserBlogDetailData parse({
    required String html,
    required UserBlogDetailQuery query,
  }) {
    final document = html_parser.parse(html);
    final root = document.querySelector('.viewthread');
    final post = root?.querySelector('.plc');
    final message = post?.querySelector('.message');
    if (root == null || post == null || message == null) {
      throw const FormatException('blog_detail_root_missing');
    }
    final title = _clean(root.querySelector('.view_tit')?.text ?? '');
    final body = message.innerHtml.trim();
    if (title.isEmpty || body.isEmpty) {
      throw const FormatException('blog_detail_content_missing');
    }
    final author = post.querySelector('.authi .mtit a[href*="uid="]');
    final ownerId = _profileUserId(author?.attributes['href']);
    if (ownerId == null || ownerId != query.ownerUserId.trim()) {
      throw const FormatException('blog_owner_identity_mismatch');
    }
    final observedIds = <String>{
      for (final anchor in post.querySelectorAll('.threadlist_foot a[href]'))
        if (_blogId(anchor.attributes['href']) case final String id) id,
      if (root.querySelector('input[name="id"]')?.attributes['value']?.trim()
          case final String id when id.isNotEmpty)
        id,
    };
    if (observedIds.length != 1 || observedIds.single != query.blogId.trim()) {
      throw const FormatException('blog_detail_identity_mismatch');
    }
    final stats = post.querySelector('.authi .mtime');
    final viewCount = _displayedCount(stats, 'dm-eye');
    final commentCount = _displayedCount(stats, 'dm-chat-s');
    final resolver = ForumUriResolver(siteOrigin: siteOrigin);
    final comments = <UserBlogComment>[];
    final commentIds = <String>{};
    for (final row in root.querySelectorAll('li.doing_list_li')) {
      final comment = _comment(row, resolver);
      if (!commentIds.add(comment.commentId)) {
        throw const FormatException('blog_comment_duplicate');
      }
      comments.add(comment);
    }
    if (commentCount != null && commentCount < comments.length) {
      throw const FormatException('blog_comment_count_inconsistent');
    }
    if (commentCount != null &&
        commentCount > 0 &&
        root.querySelector('.doing_list_box') == null) {
      throw const FormatException('blog_comments_root_missing');
    }
    final form = root.querySelector('form[id^="quickcommentform"]');
    if (form != null &&
        (form.querySelector('input[name="id"]')?.attributes['value']?.trim() !=
                query.blogId.trim() ||
            form
                    .querySelector('input[name="idtype"]')
                    ?.attributes['value']
                    ?.trim() !=
                'blogid')) {
      throw const FormatException('blog_comment_form_invalid');
    }
    return UserBlogDetailData(
      blogId: observedIds.single,
      ownerUserId: ownerId,
      title: title,
      bodyHtml: body,
      authorName: _optionalText(author?.text),
      avatarUrl: _optionalUri(
        resolver,
        post.querySelector('.avatar img')?.attributes['src'],
      ),
      publishedAtText: _publishedAt(stats),
      viewCount: viewCount,
      commentCount: commentCount,
      comments: List.unmodifiable(comments),
      commentsOpen: form == null ? null : true,
    );
  }

  UserBlogComment _comment(html_dom.Element row, ForumUriResolver resolver) {
    final id = RegExp(
      r'^comment_(\d+)_li$',
    ).firstMatch(row.id.trim())?.group(1);
    final author = row.querySelector('.muser h3 a');
    final authorName = _clean(author?.text ?? '');
    final body = row.querySelector('.do_comment')?.innerHtml.trim() ?? '';
    if (id == null || authorName.isEmpty || body.isEmpty) {
      throw const FormatException('blog_comment_invalid');
    }
    return UserBlogComment(
      commentId: id,
      authorName: authorName,
      bodyHtml: body,
      authorUserId: _profileUserId(author?.attributes['href']),
      avatarUrl: _optionalUri(
        resolver,
        row.querySelector('.avatar img')?.attributes['src'],
      ),
      publishedAtText: _optionalText(row.querySelector('.mtime span')?.text),
    );
  }

  int? _displayedCount(html_dom.Element? stats, String iconClass) {
    final icon = stats?.querySelector('i.$iconClass');
    if (icon == null) return null;
    final value = _clean(icon.nextElementSibling?.text ?? '');
    if (!RegExp(r'^\d+$').hasMatch(value)) {
      throw const FormatException('blog_statistic_invalid');
    }
    return int.parse(value);
  }

  String? _publishedAt(html_dom.Element? stats) {
    if (stats == null) return null;
    final metric = stats.querySelector('span.y');
    return _optionalText(
      stats.nodes
          .where((node) => node != metric)
          .map((node) => node.text)
          .join(' '),
    );
  }

  String? _blogId(String? raw) {
    final uri = _sameSite(raw, siteOrigin);
    if (uri == null) return null;
    final isSpaceAction =
        uri.path.endsWith('home.php') &&
        uri.queryParameters['mod'] == 'spacecp' &&
        uri.queryParameters['type'] == 'blog';
    final isInviteAction =
        uri.path.endsWith('misc.php') &&
        uri.queryParameters['mod'] == 'invite' &&
        uri.queryParameters['action'] == 'blog';
    return isSpaceAction || isInviteAction
        ? _optionalText(uri.queryParameters['id'])
        : null;
  }

  String? _profileUserId(String? raw) {
    final uri = _sameSite(raw, siteOrigin);
    if (uri == null ||
        !uri.path.endsWith('home.php') ||
        uri.queryParameters['mod'] != 'space') {
      return null;
    }
    return _optionalText(uri.queryParameters['uid']);
  }
}

Uri? _sameSite(String? raw, Uri siteOrigin) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;
  try {
    final resolver = ForumUriResolver(siteOrigin: siteOrigin);
    final uri = resolver.resolve(value);
    return resolver.isSameSite(uri) ? uri : null;
  } on FormatException {
    return null;
  }
}

String? _optionalUri(ForumUriResolver resolver, String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;
  try {
    final uri = resolver.resolve(value);
    return resolver.isSameSite(uri) ? uri.toString() : null;
  } on FormatException {
    return null;
  }
}

String? _optionalText(String? value) {
  final normalized = _clean(value ?? '');
  return normalized.isEmpty ? null : normalized;
}

String? _optionalMarkup(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

int _positiveInt(String value) {
  if (!RegExp(r'^\d+$').hasMatch(value)) {
    throw const FormatException('positive_integer_invalid');
  }
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < 1) {
    throw const FormatException('positive_integer_invalid');
  }
  return parsed;
}

String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

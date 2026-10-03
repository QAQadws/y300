// ignore_for_file: public_member_api_docs

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;

import '../contracts/data_read_contract.dart';
import '../contracts/profile_and_blog.dart';
import '../contracts/user_blog_comments.dart';
import '../url/forum_uri_resolver.dart';
import 'discuz_blog_heading_parser.dart';
import 'discuz_blog_social_links.dart';
import 'discuz_blog_pagination.dart';
import 'discuz_profile_action_links.dart';

abstract final class DiscuzProfileAuthPageDetector {
  static bool isLoginPage(String html) {
    final document = html_parser.parse(html);
    return document.querySelector(
          'form#loginform, form[name="login"], .loginbox',
        ) !=
        null;
  }
}

final class ForumUserProfileUnauthorized implements Exception {
  const ForumUserProfileUnauthorized();
}

final class ForumUserProfileHtmlParser {
  const ForumUserProfileHtmlParser({required this.siteOrigin});

  final Uri siteOrigin;

  bool isExpectedSelfResponseUri({
    required Uri uri,
    required String expectedUserId,
  }) {
    if (!_sameOrigin(uri) || uri.path != '/home.php' || uri.hasFragment) {
      return false;
    }
    return _matchesQuery(uri, {
      'mod': 'space',
      'uid': expectedUserId,
      'do': 'profile',
      'mobile': '2',
      'mycenter': '1',
    });
  }

  ForumUserProfileData parse({
    required String html,
    required String expectedUserId,
    ForumUserProfileView view = ForumUserProfileView.public,
    String? expectedViewerUserId,
  }) {
    final document = html_parser.parse(html);
    final signedInUserId = _optionalSignedInUserId(document);
    if (view == ForumUserProfileView.self) {
      if (signedInUserId == '0') {
        throw const ForumUserProfileUnauthorized();
      }
      if (signedInUserId != expectedUserId) {
        throw const FormatException('profile_session_identity_mismatch');
      }
    }
    if (expectedViewerUserId != null &&
        signedInUserId != expectedViewerUserId) {
      throw const FormatException('profile_viewer_identity_mismatch');
    }
    final roots = document.querySelectorAll('.userinfo');
    final scope = document.body;
    if (roots.length != 1 || scope == null) {
      throw const FormatException('profile_root_missing');
    }
    final root = roots.single;
    final username = _clean(root.querySelector('h2.name')?.text ?? '');
    if (username.isEmpty) {
      throw const FormatException('profile_name_missing');
    }
    // Discuz renders metrics and details as siblings of `.userinfo`.
    final details = _details(scope);
    final ids = details
        .where((item) => item.label.toUpperCase() == 'UID')
        .map((item) => item.value.trim())
        .toList(growable: false);
    if (ids.length != 1 ||
        !RegExp(r'^[1-9]\d*$').hasMatch(ids.single) ||
        ids.single != expectedUserId.trim()) {
      throw const FormatException('profile_identity_mismatch');
    }
    final resolver = ForumUriResolver(siteOrigin: siteOrigin);
    final actionLinks = DiscuzProfileActionLinks(
      siteOrigin,
    ).parse(scope, userId: ids.single, viewerUserId: signedInUserId);
    return ForumUserProfileData(
      identity: ProfileUserIdentity(userId: ids.single, displayName: username),
      avatarUrl: _optionalUri(
        resolver,
        root.querySelector('.avatar_m img')?.attributes['src'],
      ),
      coverUrl: _cover(document, resolver),
      signatureHtml: _optionalMarkup(
        scope.querySelector('.myinfo_list li.sig')?.innerHtml,
      ),
      metrics: List.unmodifiable(_metrics(scope)),
      details: List.unmodifiable(details),
      viewerUserId: signedInUserId == '0' ? null : signedInUserId,
      groupName: _detailValue(details, _groupLabels),
      customTitle: _detailValue(details, _customTitleLabels),
      isOnline: _onlineState(scope),
      actions: List.unmodifiable(actionLinks.map((link) => link.kind)),
      actionLinks: actionLinks,
    );
  }

  String? _optionalSignedInUserId(html_dom.Document document) {
    final matches = document
        .querySelectorAll('script')
        .expand(
          (script) => RegExp(
            r'''(?:^|[,;\s])discuz_uid\s*=\s*(['"])(\d+)\1''',
          ).allMatches(script.text),
        )
        .toList(growable: false);
    if (matches.length != 1) return null;
    final id = matches.single.group(2)!;
    return id == '0' || RegExp(r'^[1-9]\d*$').hasMatch(id) ? id : null;
  }

  List<ForumUserProfileMetric> _metrics(html_dom.Element root) => root
      .querySelectorAll('.user_box li')
      .map((item) {
        final valueNode = item.querySelector('span');
        final value = _clean(valueNode?.text ?? '');
        final label = _clean(item.text.replaceFirst(value, ''));
        return label.isEmpty || value.isEmpty
            ? null
            : ForumUserProfileMetric(label: label, value: value);
      })
      .whereType<ForumUserProfileMetric>()
      .toList(growable: false);

  List<ForumUserProfileDetail> _details(html_dom.Element root) {
    html_dom.Element? section;
    var uidRows = 0;
    for (final candidate in root.querySelectorAll('.myinfo_list')) {
      for (final item in candidate.querySelectorAll('li')) {
        if (_detailLabel(item).toUpperCase() == 'UID') {
          uidRows++;
          section = candidate;
        }
      }
    }
    if (section == null || uidRows != 1) {
      throw const FormatException('profile_uid_missing_or_repeated');
    }
    final output = <ForumUserProfileDetail>[];
    for (final item in section.querySelectorAll('li')) {
      if (item.querySelector('b') != null) continue;
      final valueNode = item.querySelector('span');
      final value = _clean(valueNode?.text ?? '');
      final label = _detailLabel(item);
      if (label.isEmpty || value.isEmpty) {
        if (label.toUpperCase() == 'UID') {
          throw const FormatException('profile_uid_invalid');
        }
        continue;
      }
      output.add(
        ForumUserProfileDetail(
          label: label,
          value: value,
          section: _detailSection(label),
        ),
      );
    }
    return output;
  }

  String _detailLabel(html_dom.Element item) {
    final valueNode = item.querySelector('span');
    return _clean(
      item.nodes
          .takeWhile((node) => node != valueNode)
          .where((node) => node is! html_dom.Element || node.localName != 'em')
          .map((node) => node.text)
          .join(),
    );
  }

  static const _groupLabels = {'用户组', '用戶組', 'user group', 'usergroup'};
  static const _customTitleLabels = {
    '自定义头衔',
    '自定義頭銜',
    'custom title',
    'custom status',
  };
  static const _accountLabels = {
    'uid',
    '用户组',
    '用戶組',
    'user group',
    'usergroup',
    '管理组',
    '管理組',
    'management team',
    '扩展用户组',
    '擴展用戶組',
    'extended user groups',
  };
  static const _activityLabels = {
    '注册时间',
    '註冊時間',
    '注册日期',
    '註冊日期',
    'registration date',
    'registered',
    '最后访问',
    '最後訪問',
    'last visit',
    '在线时间',
    '在線時間',
    'online time',
  };

  ForumUserProfileDetailSection _detailSection(String label) {
    final normalized = label.toLowerCase();
    if (_accountLabels.contains(normalized)) {
      return ForumUserProfileDetailSection.account;
    }
    if (_activityLabels.contains(normalized)) {
      return ForumUserProfileDetailSection.activity;
    }
    return ForumUserProfileDetailSection.personal;
  }

  String? _detailValue(
    List<ForumUserProfileDetail> details,
    Set<String> labels,
  ) {
    final matches = details.where(
      (item) => labels.contains(item.label.toLowerCase()),
    );
    return matches.length == 1 ? matches.single.value : null;
  }

  bool? _onlineState(html_dom.Element scope) {
    for (final status in scope.querySelectorAll('.myinfo_list li .mtxt')) {
      if (status.querySelector('a') != null) continue;
      if ({'在线', '在線', 'online'}.contains(_clean(status.text).toLowerCase())) {
        return true;
      }
    }
    return null;
  }

  bool _sameOrigin(Uri uri) =>
      uri.scheme == siteOrigin.scheme &&
      uri.host.toLowerCase() == siteOrigin.host.toLowerCase() &&
      uri.port == siteOrigin.port &&
      uri.userInfo.isEmpty;

  bool _matchesQuery(Uri uri, Map<String, String> expected) {
    final actual = uri.queryParametersAll;
    return actual.length == expected.length &&
        expected.entries.every(
          (entry) =>
              actual[entry.key]?.length == 1 &&
              actual[entry.key]!.single == entry.value,
        );
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
    final activeScope = _validBlogUri(
      document.querySelector('.dhnv a.mon, .dhnv .mon a')?.attributes['href'],
    );
    if (query.ownerUserId != null &&
        _activeOwner(document, activeScope) != query.ownerUserId) {
      throw const FormatException('blog_directory_owner_mismatch');
    }
    final selectedFilters = document
        .querySelectorAll('#dhnavs_li li.mon a, #dhnavs_li a.mon')
        .map((node) => _validBlogUri(node.attributes['href']))
        .whereType<Uri>();
    final selectedCategory = selectedFilters
        .map((uri) => _filterId(uri.queryParameters['catid']))
        .whereType<String>()
        .toSet();
    final selectedPersonal = selectedFilters
        .map((uri) => _filterId(uri.queryParameters['classid']))
        .whereType<String>()
        .toSet();
    if (!_matchesFilter(selectedCategory, query.categoryId) ||
        !_matchesFilter(selectedPersonal, query.personalCategoryId)) {
      throw const FormatException('blog_directory_category_mismatch');
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
        categories: _categories(document, query),
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

  String? _activeOwner(html_dom.Document document, Uri? scopeUri) {
    if (scopeUri == null) return null;
    if (scopeUri.queryParameters.containsKey('uid')) {
      return scopeUri.queryParameters['uid'];
    }
    if (scopeUri.queryParameters['view'] != 'me') return null;

    // The touch template omits uid only on the current user's own tab.
    // Verify that owner against the header, never against article content.
    final pattern = RegExp(
      r'''(?:^|[,;])\s*(?:var\s+)?discuz_uid\s*=\s*['"]([^'"]*)['"]''',
      multiLine: true,
    );
    final owners = document
        .querySelectorAll('head script')
        .expand((script) => pattern.allMatches(script.text))
        .map((match) => match.group(1)!)
        .toSet();
    if (owners.length != 1 || !RegExp(r'^[1-9]\d*$').hasMatch(owners.single)) {
      return null;
    }
    return owners.single;
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
    final (title, categoryNames) = DiscuzBlogHeadingParser(
      siteOrigin,
    ).summary(row.querySelector('.threadlist_tit'));
    if (!RegExp(r'^[1-9]\d*$').hasMatch(blogId) ||
        !RegExp(r'^[1-9]\d*$').hasMatch(ownerId) ||
        title.isEmpty) {
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
      categoryNames: categoryNames,
      authorName: _optionalText(author?.text),
      excerpt: _optionalText(row.querySelector('.threadlist_mes')?.text),
      avatarUrl: _optionalUri(
        resolver,
        row.querySelector('.avatar img')?.attributes['src'],
      ),
      publishedAtText: _optionalText(row.querySelector('.mtime span')?.text),
      actions: _blogActions(
        row.querySelectorAll('.doing_listgl a[href]'),
        blogId,
        siteOrigin,
      ),
    );
  }

  (UserBlogPagination, PaginationPrecision) _pagination(
    html_dom.Document document,
    UserBlogDirectoryQuery query,
  ) => DiscuzBlogPagination(siteOrigin).parse(
    document,
    requestedPage: query.page,
    matchesContext: (uri) {
      if (_validBlogUri(uri.toString()) == null ||
          uri.queryParameters.containsKey('id')) {
        return false;
      }
      final values = uri.queryParameters;
      final scope = switch (query.scope) {
        UserBlogFeedScope.friends => 'we',
        UserBlogFeedScope.self => 'me',
        UserBlogFeedScope.public => 'all',
      };
      final order = values['order'] ?? 'dateline';
      return values['view'] == scope &&
          order ==
              (query.order == UserBlogOrder.recommended ? 'hot' : 'dateline') &&
          (query.ownerUserId == null || values['uid'] == query.ownerUserId) &&
          _filterId(values['catid']) == query.categoryId &&
          _filterId(values['classid']) == query.personalCategoryId;
    },
  );

  List<UserBlogCategory> _categories(
    html_dom.Document document,
    UserBlogDirectoryQuery query,
  ) {
    final field = query.scope == UserBlogFeedScope.public ? 'catid' : 'classid';
    final categories = <String, UserBlogCategory>{};
    for (final anchor in document.querySelectorAll('#dhnavs_li a[href]')) {
      final uri = _validBlogUri(anchor.attributes['href']);
      final id = _filterId(uri?.queryParameters[field]);
      final name = _optionalText(anchor.text);
      if (uri == null || id == null || name == null) continue;
      if (query.ownerUserId != null &&
          uri.queryParameters['uid'] != query.ownerUserId) {
        continue;
      }
      categories[id] = UserBlogCategory(id: id, name: name);
    }
    return List.unmodifiable(categories.values);
  }

  String? _filterId(String? value) =>
      value == null || value.isEmpty || value == '0' ? null : value;

  bool _matchesFilter(Set<String> observed, String? expected) =>
      expected == null
      ? observed.isEmpty
      : observed.length == 1 && observed.single == expected;

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
    final (title, categoryLinks) = DiscuzBlogHeadingParser(siteOrigin).article(
      root.querySelector('.view_tit'),
      ownerUserId: query.ownerUserId.trim(),
    );
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
    if (query.commentId != null &&
        comments.any((comment) => comment.commentId != query.commentId)) {
      throw const FormatException('blog_comment_identity_mismatch');
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
      categoryLinks: categoryLinks,
      socialActions: DiscuzBlogSocialLinks(siteOrigin).parse(
        post.querySelectorAll('.threadlist_foot a[href]'),
        blogId: query.blogId,
        ownerUserId: ownerId,
      ),
      authorName: _optionalText(author?.text),
      avatarUrl: _optionalUri(
        resolver,
        post.querySelector('.avatar img')?.attributes['src'],
      ),
      publishedAtText: _publishedAt(stats),
      viewCount: viewCount,
      commentCount: commentCount,
      comments: List.unmodifiable(comments),
      actions: _blogActions(
        post.querySelectorAll('.threadlist_foot a[href]'),
        query.blogId,
        siteOrigin,
      ),
      commentsOpen:
          form != null &&
          form.querySelector('textarea[name="message"]') != null,
      commentPagination: DiscuzBlogPagination(siteOrigin)
          .parse(
            document,
            requestedPage: query.page,
            lastPage: query.lastCommentPage,
            singleComment: query.commentId != null,
            matchesContext: (uri) =>
                uri.path.endsWith('/home.php') &&
                uri.queryParameters['mod'] == 'space' &&
                uri.queryParameters['do'] == 'blog' &&
                uri.queryParameters['uid'] == query.ownerUserId &&
                uri.queryParameters['id'] == query.blogId &&
                !uri.queryParameters.containsKey('cid') &&
                !uri.queryParameters.containsKey('goto'),
          )
          .$1,
    );
  }

  UserBlogComment _comment(html_dom.Element row, ForumUriResolver resolver) {
    final id = RegExp(
      r'^comment_(\d+)_li$',
    ).firstMatch(row.id.trim())?.group(1);
    final author = row.querySelector('.muser h3 a');
    final authorName = _clean(row.querySelector('.muser h3')?.text ?? '');
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
      actions: _commentActions(row, id),
    );
  }

  Set<UserBlogCommentAction> _commentActions(
    html_dom.Element row,
    String commentId,
  ) {
    final result = <UserBlogCommentAction>{};
    for (final anchor in row.querySelectorAll('.doing_listgl a[href]')) {
      final uri = _sameSite(anchor.attributes['href'], siteOrigin);
      if (uri == null ||
          !uri.path.endsWith('/home.php') ||
          uri.queryParameters['mod'] != 'spacecp' ||
          uri.queryParameters['ac'] != 'comment' ||
          uri.queryParameters['cid'] != commentId) {
        continue;
      }
      final action = switch (uri.queryParameters['op']) {
        'reply' => UserBlogCommentAction.reply,
        'edit' => UserBlogCommentAction.edit,
        'delete' => UserBlogCommentAction.delete,
        _ => null,
      };
      if (action != null) result.add(action);
    }
    return Set.unmodifiable(result);
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
    if (uri == null ||
        uri.scheme != siteOrigin.scheme ||
        uri.port != siteOrigin.port ||
        uri.userInfo.isNotEmpty ||
        uri.queryParametersAll.values.any((values) => values.length != 1)) {
      return null;
    }
    final isSpaceAction =
        uri.path.endsWith('home.php') &&
        uri.queryParameters['mod'] == 'spacecp' &&
        uri.queryParameters['type'] == 'blog';
    final isInviteAction =
        uri.path.endsWith('misc.php') &&
        uri.queryParameters['mod'] == 'invite' &&
        uri.queryParameters['action'] == 'blog';
    if (uri.path.endsWith('home.php') &&
        uri.queryParameters['mod'] == 'spacecp' &&
        uri.queryParameters['ac'] == 'blog') {
      return _optionalText(uri.queryParameters['blogid']);
    }
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

String _clean(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

Set<UserBlogAction> _blogActions(
  Iterable<html_dom.Element> anchors,
  String blogId,
  Uri origin,
) {
  final actions = <UserBlogAction>{};
  for (final anchor in anchors) {
    final uri = _sameSite(anchor.attributes['href'], origin);
    if (uri == null ||
        uri.path != '/home.php' ||
        uri.scheme != origin.scheme ||
        uri.port != origin.port ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.queryParameters['mod'] != 'spacecp' ||
        uri.queryParameters['ac'] != 'blog' ||
        uri.queryParameters['blogid'] != blogId ||
        uri.queryParametersAll.values.any((values) => values.length != 1) ||
        uri.queryParameters.keys.any(
          (key) => !{
            'mod',
            'ac',
            'op',
            'blogid',
            'stickflag',
            'mobile',
            'handlekey',
          }.contains(key),
        )) {
      continue;
    }
    final action = switch (uri.queryParameters['op']) {
      'edit' => UserBlogAction.edit,
      'delete' => UserBlogAction.delete,
      'stick' => switch (uri.queryParameters['stickflag']) {
        '1' => UserBlogAction.pin,
        '0' => UserBlogAction.unpin,
        _ => null,
      },
      _ => null,
    };
    if (action != null) actions.add(action);
  }
  return Set.unmodifiable(actions);
}

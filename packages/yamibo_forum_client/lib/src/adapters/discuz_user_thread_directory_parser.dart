// ignore_for_file: public_member_api_docs

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../contracts/user_thread_directory.dart';
import '../url/forum_uri_resolver.dart';

final class UserThreadDirectoryUnauthorized implements Exception {
  const UserThreadDirectoryUnauthorized();
}

/// Parses the touch/home/space_thread template without counting topic groups
/// as posts: Discuz groups an already paginated reply batch by topic.
final class DiscuzUserThreadDirectoryParser {
  const DiscuzUserThreadDirectoryParser({required this.siteOrigin});

  final Uri siteOrigin;

  bool isExpectedResponseUri(Uri uri, UserThreadDirectoryQuery query) =>
      _matchesContext(uri, query) &&
      _value(uri, 'mobile') == '2' &&
      _page(uri) == query.page;

  UserThreadDirectoryData parse({
    required String source,
    required UserThreadDirectoryQuery query,
  }) {
    final document = html.parse(source);
    _verifyViewer(document, query.userId);
    _verifyDirectory(document, query);
    final items = <UserThreadSummary>[];
    final ids = <String>{};
    // Nested image/footer lists also contain li elements; they are not rows.
    for (final row in document.querySelectorAll('.threadlist > ul > li.list')) {
      final item = _row(row, query);
      if (!ids.add(item.threadId)) {
        throw const FormatException('user_thread_duplicate_group');
      }
      items.add(item);
    }
    return UserThreadDirectoryData(
      items: List.unmodifiable(items),
      pagination: _pagination(document, query),
    );
  }

  void _verifyViewer(dom.Document document, String expectedUserId) {
    final identities =
        document.head
            ?.querySelectorAll('script')
            .expand(
              (script) => RegExp(
                r'''(?:^|[,;\s])discuz_uid\s*=\s*(['"])(\d+)\1''',
              ).allMatches(script.text).map((match) => match.group(2)!),
            )
            .toSet() ??
        <String>{};
    if (identities.length == 1 && identities.single == '0') {
      throw const UserThreadDirectoryUnauthorized();
    }
    if (identities.length != 1 || identities.single != expectedUserId) {
      throw const FormatException('user_thread_account_mismatch');
    }
  }

  void _verifyDirectory(dom.Document document, UserThreadDirectoryQuery query) {
    final tabs = document.querySelector('.dhnv');
    if (tabs != null) {
      final active = tabs.querySelectorAll('a.mon, .mon a');
      if (active.length != 1 || !_matchesContext(_link(active.single), query)) {
        throw const FormatException('user_thread_directory_context_invalid');
      }
      return;
    }
    // The stock touch template has no tabs, including on a valid empty page.
    final heading = _text(document.querySelector('.header h2')?.text);
    final expected = query.type == UserThreadDirectoryType.replies
        ? '\u6211\u7684\u56de\u590d'
        : '\u6211\u7684\u4e3b\u9898';
    if (heading != expected &&
        !(query.type == UserThreadDirectoryType.replies &&
            heading == '\u6211\u7684\u56de\u8986')) {
      throw const FormatException('user_thread_directory_context_missing');
    }
  }

  UserThreadSummary _row(dom.Element row, UserThreadDirectoryQuery query) {
    final titleNodes = row.querySelectorAll('.threadlist_tit em');
    if (titleNodes.length != 1) {
      throw const FormatException('user_thread_title_missing');
    }
    final title = _text(titleNodes.single.text);
    final target = _threadTarget(_link(_ancestorLink(titleNodes.single)));
    if (title.isEmpty || target == null) {
      throw const FormatException('user_thread_target_invalid');
    }
    final (threadId, _) = target;
    final previews = <UserThreadReplyPreview>[];
    final postIds = <String>{};
    for (final quote in row.querySelectorAll('.quote')) {
      final uri = _link(_ancestorLink(quote));
      final replyTarget = _threadTarget(uri);
      final postId = uri == null ? null : _value(uri, 'pid');
      if (replyTarget == null ||
          replyTarget.$1 != threadId ||
          uri!.path != '/forum.php' ||
          _value(uri, 'mod') != 'redirect' ||
          _value(uri, 'goto') != 'findpost' ||
          !_id(postId) ||
          !postIds.add(postId!)) {
        throw const FormatException('user_thread_reply_target_invalid');
      }
      previews.add(
        UserThreadReplyPreview(
          postId: postId,
          excerpt: _text(quote.querySelector('blockquote')?.text ?? quote.text),
          uri: uri,
        ),
      );
    }
    if (query.type == UserThreadDirectoryType.replies && previews.isEmpty) {
      throw const FormatException('user_thread_reply_preview_missing');
    }
    if (query.type == UserThreadDirectoryType.threads && previews.isNotEmpty) {
      throw const FormatException('user_thread_directory_type_mismatch');
    }
    final author = row.querySelector('.threadlist_top .muser h3 a');
    final authorUri = _link(author);
    final authorId =
        authorUri?.path == '/home.php' && _value(authorUri!, 'mod') == 'space'
        ? _value(authorUri, 'uid')
        : null;
    if (author != null && (!_id(authorId) || authorId != query.userId)) {
      throw const FormatException('user_thread_author_mismatch');
    }
    final forum = row.querySelector('.threadlist_foot li.mr a');
    final forumUri = _link(forum);
    final forumId =
        forumUri?.path == '/forum.php' &&
            _value(forumUri!, 'mod') == 'forumdisplay'
        ? _value(forumUri, 'fid')
        : null;
    return UserThreadSummary(
      threadId: threadId,
      title: title,
      uri: siteOrigin.replace(
        path: '/forum.php',
        queryParameters: {'mod': 'viewthread', 'tid': threadId, 'mobile': '2'},
      ),
      authorName: _optionalText(author?.text),
      authorUserId: _id(authorId) ? authorId : null,
      avatarUrl: _image(
        row.querySelector('.threadlist_top .mimg img')?.attributes['src'],
      ),
      publishedAtText: _optionalText(
        row.querySelector('.threadlist_top .mtime')?.text,
      ),
      excerpt: _optionalText(row.querySelector('.threadlist_mes')?.text),
      forumId: _id(forumId) ? forumId : null,
      forumName: _optionalText(forum?.text.replaceFirst(RegExp(r'^\s*#'), '')),
      views: _count(row, '.dm-eye-fill'),
      replies: _count(row, '.dm-chat-s-fill'),
      images: List.unmodifiable(
        row
            .querySelectorAll('.threadlist_imgs1 img, .threadlist_imgs img')
            .map((image) => _image(image.attributes['src']))
            .whereType<String>()
            .toSet(),
      ),
      replyPreviews: List.unmodifiable(previews),
    );
  }

  UserThreadDirectoryPagination _pagination(
    dom.Document document,
    UserThreadDirectoryQuery query,
  ) {
    final pagers = document.querySelectorAll('.pg');
    var hasNext = false;
    var hasPrevious = false;
    for (final pager in pagers) {
      final current = pager.querySelector('strong');
      if (current != null && int.tryParse(_text(current.text)) != query.page) {
        throw const FormatException('user_thread_page_mismatch');
      }
      for (final anchor in pager.querySelectorAll('a[href]')) {
        final uri = _link(anchor);
        if (!_matchesContext(uri, query)) {
          throw const FormatException('user_thread_pager_context_invalid');
        }
        final page = _page(uri!);
        if (page == null) {
          throw const FormatException('user_thread_pager_page_invalid');
        }
        if (anchor.classes.contains('nxt')) {
          if (page != query.page + 1) {
            throw const FormatException('user_thread_next_page_invalid');
          }
          hasNext = true;
        } else if (anchor.classes.contains('prev') ||
            anchor.parent?.classes.contains('pgb') == true) {
          if (page != query.page - 1) {
            throw const FormatException('user_thread_previous_page_invalid');
          }
          hasPrevious = true;
        }
      }
    }
    return UserThreadDirectoryPagination(
      currentPage: query.page,
      hasNext: hasNext,
      hasPrevious: hasPrevious,
    );
  }

  bool _matchesContext(Uri? uri, UserThreadDirectoryQuery query) {
    if (uri == null ||
        !_sameOrigin(uri) ||
        uri.path != '/home.php' ||
        uri.hasFragment) {
      return false;
    }
    final type = _value(uri, 'type');
    final order = _value(uri, 'order');
    return _value(uri, 'mod') == 'space' &&
        _value(uri, 'do') == 'thread' &&
        _value(uri, 'uid') == query.userId &&
        _value(uri, 'view') == 'me' &&
        (order == null || order.isEmpty || order == 'dateline') &&
        (query.type == UserThreadDirectoryType.replies
            ? type == 'reply'
            : type == null || type == 'thread') &&
        uri.queryParametersAll.keys.every(
          {
            'mod',
            'do',
            'uid',
            'view',
            'type',
            'mobile',
            'page',
            'order',
          }.contains,
        );
  }

  (String, Uri)? _threadTarget(Uri? uri) {
    if (uri == null || !_sameOrigin(uri)) return null;
    final rewritten = RegExp(
      r'^/thread-([1-9]\d*)-\d+-\d+\.html$',
    ).firstMatch(uri.path);
    if (rewritten != null) return (rewritten.group(1)!, uri);
    if (uri.path != '/forum.php') return null;
    final mod = _value(uri, 'mod');
    final tid = mod == 'viewthread'
        ? _value(uri, 'tid')
        : mod == 'redirect' && _value(uri, 'goto') == 'findpost'
        ? _value(uri, 'ptid')
        : null;
    return _id(tid) ? (tid!, uri) : null;
  }

  String? _value(Uri uri, String key) {
    final values = uri.queryParametersAll[key];
    if (values == null) return null;
    if (values.length != 1) {
      throw const FormatException('user_thread_ambiguous_query');
    }
    return values.single;
  }

  int? _page(Uri uri) {
    final value = _value(uri, 'page');
    if (value == null) return 1;
    final page = int.tryParse(value);
    return page != null && page > 0 ? page : null;
  }

  Uri? _link(dom.Element? element) {
    final value = element?.attributes['href'];
    if (value == null) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    final resolved = siteOrigin.resolveUri(uri);
    return _sameOrigin(resolved) ? resolved : null;
  }

  bool _sameOrigin(Uri uri) =>
      uri.scheme == siteOrigin.scheme &&
      uri.host.toLowerCase() == siteOrigin.host.toLowerCase() &&
      uri.port == siteOrigin.port &&
      uri.userInfo.isEmpty;

  String? _image(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      final uri = ForumUriResolver(siteOrigin: siteOrigin).resolve(value);
      return {'http', 'https'}.contains(uri.scheme) &&
              uri.host.isNotEmpty &&
              uri.userInfo.isEmpty
          ? uri.toString()
          : null;
    } on FormatException {
      return null;
    }
  }

  int? _count(dom.Element row, String selector) => int.tryParse(
    _text(row.querySelector(selector)?.parent?.text).replaceAll(',', ''),
  );

  dom.Element? _ancestorLink(dom.Element element) {
    for (
      dom.Element? current = element;
      current != null;
      current = current.parent
    ) {
      if (current.localName == 'a') return current;
    }
    return null;
  }

  bool _id(String? value) =>
      value != null && RegExp(r'^[1-9]\d*$').hasMatch(value);
  String _text(String? value) =>
      (value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  String? _optionalText(String? value) {
    final text = _text(value);
    return text.isEmpty ? null : text;
  }
}

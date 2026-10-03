import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../contracts/friend_feed.dart';
import '../url/forum_uri_resolver.dart';

/// Touch friend-page parser with explicit account, list, and page validation.
final class DiscuzFriendFeedParser {
  /// Creates a parser bound to the managed site authority.
  const DiscuzFriendFeedParser({required this.siteOrigin});

  /// Managed origin used to resolve and validate member and pager links.
  final Uri siteOrigin;

  /// Verifies a response's requested account, scope and one-based page.
  bool isExpectedResponseUri(Uri uri, ForumFriendFeedQuery query) =>
      _context(uri, query) &&
      _value(uri, 'uid') == query.accountUserId &&
      _value(uri, 'mobile') == '2' &&
      _page(uri) == query.page;

  /// Projects rows only after the response proves the current account/list.
  ForumFriendFeedPage parse(String source, ForumFriendFeedQuery query) {
    final document = html.parse(source);
    if (!discuzFriendActorMatches(document, query.accountUserId)) {
      throw const FormatException('friend_feed_account_unverified');
    }
    final headings = document.querySelectorAll('.header h2');
    if (headings.length != 1 || _text(headings.single.text).isEmpty) {
      throw const FormatException('friend_feed_heading_missing');
    }
    final tabs = document.querySelectorAll('.dhnv');
    if (tabs.length != 1) {
      throw const FormatException('friend_feed_navigation_missing');
    }
    final active = tabs.single.querySelectorAll('a.mon, .mon a');
    if (active.length != 1 || !_context(_link(active.single), query)) {
      throw const FormatException('friend_feed_scope_unverified');
    }
    final containers = document.querySelectorAll('#friend_ul');
    if (containers.length > 1 ||
        containers.any((container) => !container.classes.contains('imglist'))) {
      // Desktop recommendations deliberately reuse #friend_ul. A touch read
      // must never promote those suggestions into established relationships.
      throw const FormatException('friend_feed_rows_unrecognized');
    }
    if (containers.isNotEmpty &&
        (containers.single.children.length != 1 ||
            containers.single.children.single.localName != 'ul' ||
            containers.single.children.single.children.any(
              (child) => child.localName != 'li',
            ))) {
      throw const FormatException('friend_feed_rows_unrecognized');
    }
    final items = <ForumFriendFeedItem>[];
    final ids = <String>{};
    for (final row in document.querySelectorAll('#friend_ul > ul > li')) {
      final item = _row(row, query);
      if (item.userId.isNotEmpty && !ids.add(item.userId)) {
        throw const FormatException('friend_feed_duplicate_member');
      }
      items.add(item);
    }
    var hasNext = false;
    int? totalPages;
    int? count;
    for (final pager in document.querySelectorAll('.pg')) {
      final current = pager.querySelector('strong');
      if (current != null && int.tryParse(_text(current.text)) != query.page) {
        throw const FormatException('friend_feed_page_mismatch');
      }
      final input = pager.querySelector('input[name="custompage"]');
      if (input != null &&
          input.attributes['value'] != null &&
          int.tryParse(input.attributes['value']!) != query.page) {
        throw const FormatException('friend_feed_page_mismatch');
      }
      final summary = pager.querySelector('label span');
      final total = summary == null
          ? null
          : RegExp(r'/\s*(\d+)').firstMatch(summary.text);
      if (total != null) {
        final pages = int.parse(total.group(1)!);
        if (pages < query.page || (totalPages != null && totalPages != pages)) {
          throw const FormatException('friend_feed_total_pages_invalid');
        }
        totalPages = pages;
      }
      final totalCount = pager.querySelector('em');
      if (totalCount != null) {
        final value = int.tryParse(_text(totalCount.text));
        if (value == null || value < 0 || (count != null && count != value)) {
          throw const FormatException('friend_feed_count_invalid');
        }
        count = value;
      }
      for (final anchor in pager.querySelectorAll('a[href]')) {
        final uri = _link(anchor);
        if (!_context(uri, query) || _page(uri!) == null) {
          throw const FormatException('friend_feed_pager_context_invalid');
        }
        if (anchor.classes.contains('nxt')) {
          if (_page(uri) != query.page + 1) {
            throw const FormatException('friend_feed_next_page_invalid');
          }
          hasNext = true;
        }
      }
    }
    if (totalPages != null && hasNext != (query.page < totalPages)) {
      throw const FormatException('friend_feed_pagination_inconsistent');
    }
    return ForumFriendFeedPage(
      scope: query.scope,
      currentUserId: query.accountUserId,
      items: List.unmodifiable(items),
      page: query.page,
      hasNext: hasNext,
      totalPages: totalPages,
      count: count,
    );
  }

  ForumFriendFeedItem _row(dom.Element row, ForumFriendFeedQuery query) {
    final title = row.querySelector('.mtit');
    if (title == null) throw const FormatException('friend_feed_title_missing');
    final identities = <String, dom.Element>{};
    for (final anchor in title.querySelectorAll('a[href]')) {
      final uri = _link(anchor);
      if (uri == null ||
          uri.path != '/home.php' ||
          _value(uri, 'mod') != 'space' ||
          !{null, 'profile'}.contains(_value(uri, 'do'))) {
        continue;
      }
      final id = _value(uri, 'uid');
      if (id == '0') continue;
      if (!discuzFriendPositiveId(id)) {
        throw const FormatException('friend_feed_member_invalid');
      }
      final previous = identities[id];
      if (previous != null && _link(previous) != uri) {
        throw const FormatException('friend_feed_member_link_ambiguous');
      }
      // Exact duplicate links share one destination; retain the first label.
      identities.putIfAbsent(id!, () => anchor);
    }
    // An anonymous visitor has only a javascript label and no actionable ID.
    if (identities.isEmpty &&
        row.querySelector('img[src*="/magic/hidden.gif"]') != null) {
      return const ForumFriendFeedItem(userId: '', username: '');
    }
    if (identities.length != 1) {
      throw const FormatException('friend_feed_member_ambiguous');
    }
    final id = identities.keys.single;
    final username = _text(identities.values.single.text);
    if (username.isEmpty) {
      throw const FormatException('friend_feed_username_missing');
    }
    for (final anchor in row.querySelectorAll('.mimg a[href]')) {
      final uri = _link(anchor);
      if (uri == null ||
          uri.path != '/home.php' ||
          _value(uri, 'mod') != 'space' ||
          !{null, 'profile'}.contains(_value(uri, 'do')) ||
          _value(uri, 'uid') != id) {
        throw const FormatException('friend_feed_avatar_member_mismatch');
      }
    }
    // The title is the card's source destination. The avatar may carry its
    // own display parameters, but must prove the same member identity.
    final profileUrl = _link(identities.values.single)!.toString();
    var canRemove = false;
    for (final anchor in title.querySelectorAll('a[href]')) {
      final uri = _link(anchor);
      if (uri?.path == '/home.php' &&
          _value(uri!, 'mod') == 'spacecp' &&
          _value(uri, 'ac') == 'friend' &&
          _value(uri, 'op') == 'ignore') {
        if (query.scope != ForumFriendFeedScope.friends ||
            _value(uri, 'uid') != id ||
            id == query.accountUserId) {
          throw const FormatException('friend_feed_removal_target_invalid');
        }
        canRemove = true;
      }
    }
    return ForumFriendFeedItem(
      userId: id,
      username: username,
      profileUrl: profileUrl,
      avatarUrl: _image(row.querySelector('.mimg img')?.attributes['src']),
      note: _optional(row.querySelector('.mtxt')?.text),
      isOnline:
          query.scope == ForumFriendFeedScope.online ||
              row.querySelector('.gol, img[alt="online"]') != null
          ? true
          : null,
      canRemove: canRemove,
    );
  }

  bool _context(Uri? uri, ForumFriendFeedQuery query) {
    if (uri == null ||
        !discuzFriendSameSite(uri, siteOrigin) ||
        uri.path != '/home.php' ||
        uri.hasFragment ||
        _value(uri, 'mod') != 'space' ||
        _value(uri, 'do') != 'friend' ||
        !uri.queryParametersAll.keys.every(
          {'mod', 'do', 'uid', 'view', 'type', 'page', 'mobile'}.contains,
        ) ||
        (_value(uri, 'uid') != null &&
            _value(uri, 'uid') != query.accountUserId)) {
      return false;
    }
    final view = _value(uri, 'view');
    final type = _value(uri, 'type');
    return switch (query.scope) {
      ForumFriendFeedScope.friends =>
        (view == null || view == 'me') && type == null,
      ForumFriendFeedScope.online => view == 'online' && type == 'member',
      ForumFriendFeedScope.visitors => view == 'visitor' && type == null,
      ForumFriendFeedScope.footprints => view == 'trace' && type == null,
    };
  }

  Uri? _link(dom.Element element) {
    final raw = element.attributes['href'];
    final uri = raw == null ? null : Uri.tryParse(raw);
    if (uri == null) return null;
    final resolved = siteOrigin.resolveUri(uri);
    return discuzFriendSameSite(resolved, siteOrigin) ? resolved : null;
  }

  String? _image(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final uri = ForumUriResolver(siteOrigin: siteOrigin).resolve(raw);
      return {'http', 'https'}.contains(uri.scheme) &&
              uri.host.isNotEmpty &&
              uri.userInfo.isEmpty
          ? uri.toString()
          : null;
    } on FormatException {
      return null;
    }
  }
}

/// Proves one authenticated header identity without reading user content.
bool discuzFriendActorMatches(dom.Document document, String actor) {
  final actors = (document.head?.querySelectorAll('script') ?? <dom.Element>[])
      .expand(
        (script) => RegExp(
          r'''(?:^|[,;\s])discuz_uid\s*=\s*(['"])(\d+)\1''',
        ).allMatches(script.text).map((match) => match.group(2)!),
      )
      .toSet();
  return actors.length == 1 && actors.single == actor;
}

/// Requires the exact managed authority without credentials or downgrades.
bool discuzFriendSameSite(Uri uri, Uri origin) =>
    uri.scheme == origin.scheme &&
    uri.host.toLowerCase() == origin.host.toLowerCase() &&
    uri.port == origin.port &&
    uri.userInfo.isEmpty;

/// Validates a stable, positive Discuz member ID.
bool discuzFriendPositiveId(String? id) =>
    id != null && RegExp(r'^[1-9]\d*$').hasMatch(id);

String? _value(Uri uri, String key) {
  final values = uri.queryParametersAll[key];
  if (values == null) return null;
  if (values.length != 1) {
    throw const FormatException('friend_feed_query_ambiguous');
  }
  return values.single;
}

int? _page(Uri uri) {
  final value = _value(uri, 'page');
  if (value == null) return 1;
  final page = int.tryParse(value);
  return page != null && page > 0 ? page : null;
}

String _text(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();
String? _optional(String? text) {
  final value = text == null ? '' : _text(text);
  return value.isEmpty ? null : value;
}

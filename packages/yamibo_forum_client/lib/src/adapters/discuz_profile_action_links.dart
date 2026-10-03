import 'package:html/dom.dart';

import '../contracts/profile_and_blog.dart';

/// Reads only profile toolbar destinations with exact source authority.
final class DiscuzProfileActionLinks {
  /// Creates a validator for one managed forum origin.
  const DiscuzProfileActionLinks(this.origin);

  /// Managed forum origin.
  final Uri origin;

  /// Preserves server order and never derives permissions from body links.
  List<ForumUserProfileActionLink> parse(
    Element scope, {
    required String userId,
    required String? viewerUserId,
  }) {
    final links = <ForumUserProfileActionLink>[];
    for (final element in scope.querySelectorAll(
      '.user_box, .myinfo_list_ico a[href], .myinfo_list .mtxt a[href]',
    )) {
      final raw = element.classes.contains('user_box')
          ? RegExp(
              r'''^\s*window\.location\.href\s*=\s*(['"])([^'"]+)\1\s*;?\s*$''',
            ).firstMatch(element.attributes['onclick'] ?? '')?.group(2)
          : element.attributes['href'];
      if (raw == null || raw.trim().isEmpty) continue;
      try {
        final uri = origin.resolve(raw);
        final kind = classify(uri, userId: userId, viewerUserId: viewerUserId);
        if (kind != null && !links.any((item) => item.kind == kind)) {
          links.add(ForumUserProfileActionLink(kind: kind, uri: uri));
        }
      } on FormatException {
        continue;
      }
    }
    return List.unmodifiable(links);
  }

  /// Validates an advertised destination without sending any request.
  ForumUserProfileActionKind? classify(
    Uri uri, {
    required String userId,
    required String? viewerUserId,
  }) {
    if (uri.scheme != origin.scheme ||
        uri.host.toLowerCase() != origin.host.toLowerCase() ||
        uri.port != origin.port ||
        uri.userInfo.isNotEmpty ||
        uri.path != '/home.php' ||
        uri.hasFragment ||
        uri.queryParametersAll.values.any((values) => values.length != 1)) {
      return null;
    }
    final query = Map<String, String>.of(uri.queryParameters);
    final mobile = query.remove('mobile');
    if (mobile != null && mobile != '2') return null;
    final signedIn =
        viewerUserId != null && RegExp(r'^[1-9]\d*$').hasMatch(viewerUserId);
    final self = signedIn && viewerUserId == userId;
    bool matches(Map<String, String> expected) =>
        query.length == expected.length &&
        expected.entries.every((item) => query[item.key] == item.value);

    if (query['mod'] == 'space' && query['uid'] == userId) {
      final view = query.remove('view');
      if (view != null && (view != 'me' || !self)) return null;
      final type = query.remove('type');
      if (matches({'mod': 'space', 'uid': userId, 'do': 'thread'})) {
        return switch (type) {
          null || 'thread' => ForumUserProfileActionKind.threads,
          'reply' => ForumUserProfileActionKind.replies,
          _ => null,
        };
      }
      if (type == null &&
          matches({'mod': 'space', 'uid': userId, 'do': 'blog'})) {
        return ForumUserProfileActionKind.blogs;
      }
      if (self &&
          view == 'me' &&
          type == 'thread' &&
          matches({'mod': 'space', 'uid': userId, 'do': 'favorite'})) {
        return ForumUserProfileActionKind.forumFavorites;
      }
      return null;
    }
    if (self) {
      if (matches({'mod': 'space', 'do': 'pm'})) {
        return ForumUserProfileActionKind.messages;
      }
      if (matches({'mod': 'space', 'do': 'friend'})) {
        return ForumUserProfileActionKind.friends;
      }
      if (matches({'mod': 'spacecp'}) ||
          matches({'mod': 'spacecp', 'ac': 'profile'})) {
        return ForumUserProfileActionKind.settings;
      }
      if (matches({'mod': 'spacecp', 'ac': 'credit', 'op': 'log'})) {
        return ForumUserProfileActionKind.creditHistory;
      }
    } else if (signedIn) {
      if (matches({
        'mod': 'space',
        'do': 'pm',
        'subop': 'view',
        'touid': userId,
      })) {
        return ForumUserProfileActionKind.sendMessage;
      }
      final handleKey = query.remove('handlekey');
      final op = query['op'];
      if ((op == 'add' || op == 'ignore') &&
          matches({
            'mod': 'spacecp',
            'ac': 'friend',
            'op': op!,
            'uid': userId,
          }) &&
          (handleKey == null ||
              handleKey ==
                  '${op == 'add' ? 'addfriendhk' : 'ignorefriendhk'}_$userId')) {
        return op == 'add'
            ? ForumUserProfileActionKind.addFriend
            : ForumUserProfileActionKind.removeFriend;
      }
    }
    return null;
  }
}

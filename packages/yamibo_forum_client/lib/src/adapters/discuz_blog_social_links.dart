import 'package:html/dom.dart';
import '../contracts/profile_and_blog.dart';

/// Accepts only source-owned article toolbar destinations, never body links.
final class DiscuzBlogSocialLinks {
  /// Creates an exact-authority parser for the current source.
  const DiscuzBlogSocialLinks(this.origin);

  /// Managed forum root.
  final Uri origin;

  /// Reads toolbar capabilities without issuing requests or inferring permission.
  Set<UserBlogSocialAction> parse(
    Iterable<Element> anchors, {
    required String blogId,
    required String ownerUserId,
  }) {
    final actions = <UserBlogSocialAction>{};
    for (final anchor in anchors) {
      final raw = anchor.attributes['href'];
      if (raw == null) continue;
      try {
        final uri = origin.resolve(raw);
        if (uri.scheme != origin.scheme ||
            uri.host != origin.host ||
            uri.port != origin.port ||
            uri.userInfo.isNotEmpty ||
            uri.hasFragment ||
            uri.queryParametersAll.values.any((values) => values.length != 1)) {
          continue;
        }
        final query = uri.queryParameters;
        if (query['id'] != blogId ||
            (query.containsKey('mobile') && query['mobile'] != '2')) {
          continue;
        }
        if (uri.path == '/misc.php' &&
            query['mod'] == 'invite' &&
            query['action'] == 'blog' &&
            query.keys.every({'mod', 'action', 'id', 'mobile'}.contains)) {
          actions.add(UserBlogSocialAction.invite);
          continue;
        }
        if (uri.path != '/home.php' ||
            query['mod'] != 'spacecp' ||
            query['type'] != 'blog') {
          continue;
        }
        final action = switch (query['ac']) {
          'favorite' when query['spaceuid'] == ownerUserId =>
            UserBlogSocialAction.favorite,
          'share' => UserBlogSocialAction.share,
          _ => null,
        };
        if (action == null ||
            !query.keys.every(
              {
                'mod',
                'ac',
                'type',
                'id',
                'mobile',
                'handlekey',
                if (action == UserBlogSocialAction.favorite) 'spaceuid',
              }.contains,
            )) {
          continue;
        }
        if (query.containsKey('handlekey') &&
            query['handlekey'] != '${query['ac']}bloghk_$blogId') {
          continue;
        }
        actions.add(action);
      } on FormatException {
        continue;
      }
    }
    return Set.unmodifiable(actions);
  }
}

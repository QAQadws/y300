import '../contracts/profile_and_blog.dart';
import '../contracts/user_blog_comments.dart';
import '../contracts/user_blog_navigation.dart';
import '../contracts/user_blog_operations.dart';

/// Canonical browser destinations, kept out of Host widgets and controllers.
final class DiscuzBlogNavigation implements UserBlogNavigation {
  /// Uses the same source root as the configured journal repositories.
  const DiscuzBlogNavigation({required this.siteOrigin});

  /// Configured forum origin, shared with the journal read adapters.
  final Uri siteOrigin;

  @override
  Uri? directory(UserBlogDirectoryQuery query) {
    if (query.page < 1 ||
        (query.categoryId != null && !_id(query.categoryId)) ||
        (query.personalCategoryId != null && !_id(query.personalCategoryId))) {
      return null;
    }
    final scope = query.scope;
    if (query.ownerUserId != null && !_id(query.ownerUserId)) return null;
    if (scope != UserBlogFeedScope.self && query.ownerUserId != null) {
      return null;
    }
    if (scope != UserBlogFeedScope.public && query.categoryId != null) {
      return null;
    }
    if (scope != UserBlogFeedScope.self && query.personalCategoryId != null) {
      return null;
    }
    return _home({
      'mod': 'space',
      'do': 'blog',
      'view': switch (scope) {
        UserBlogFeedScope.public => 'all',
        UserBlogFeedScope.friends => 'we',
        UserBlogFeedScope.self => 'me',
      },
      if (query.ownerUserId != null) 'uid': query.ownerUserId!,
      if (scope == UserBlogFeedScope.public)
        'order': query.order == UserBlogOrder.recommended ? 'hot' : 'dateline',
      if (query.categoryId != null) 'catid': query.categoryId!,
      if (query.personalCategoryId != null)
        'classid': query.personalCategoryId!,
      'page': '${query.page}',
      'mobile': '2',
    });
  }

  @override
  Uri? detail(UserBlogDetailQuery query) {
    if (!_id(query.ownerUserId) ||
        !_id(query.blogId) ||
        query.page < 1 ||
        (query.commentId != null && !_id(query.commentId)) ||
        (query.commentId != null && query.lastCommentPage)) {
      return null;
    }
    return _home({
      'mod': 'space',
      'uid': query.ownerUserId,
      'do': 'blog',
      'id': query.blogId,
      if (query.commentId != null) 'cid': query.commentId!,
      if (query.lastCommentPage) 'goto': 'last' else 'page': '${query.page}',
      'mobile': '2',
    });
  }

  @override
  Uri? editor(UserBlogTarget target) {
    if (!_id(target.actorUserId) || !_id(target.ownerUserId)) return null;
    if (target.action == UserBlogAction.create) {
      if (target.actorUserId != target.ownerUserId || target.blogId != null) {
        return null;
      }
    } else if (target.action != UserBlogAction.edit || !_id(target.blogId)) {
      return null;
    }
    // The touch editor omits friend/password/noreply. The complete form is also
    // required in browser fallback so saving never resets those policies.
    return _home({
      'mod': 'spacecp',
      'ac': 'blog',
      if (target.blogId != null) 'blogid': target.blogId!,
      if (target.action == UserBlogAction.edit) 'op': 'edit',
      'mobile': 'no',
    });
  }

  @override
  Uri? comment(UserBlogCommentTarget target) {
    if (!_id(target.actorUserId) ||
        !_id(target.ownerUserId) ||
        !_id(target.blogId)) {
      return null;
    }
    if (target.action == UserBlogCommentAction.add) {
      if (target.commentId != null) return null;
      return detail(
        UserBlogDetailQuery(
          ownerUserId: target.ownerUserId,
          blogId: target.blogId,
        ),
      )?.replace(fragment: 'quickcommentform_${target.blogId}');
    }
    if (!_id(target.commentId)) return null;
    return _home({
      'mod': 'spacecp',
      'ac': 'comment',
      'op': target.action.name,
      'cid': target.commentId!,
      'mobile': '2',
    });
  }

  Uri? _home(Map<String, String> query) {
    if (!{'https', 'http'}.contains(siteOrigin.scheme) ||
        siteOrigin.host.isEmpty ||
        siteOrigin.userInfo.isNotEmpty ||
        siteOrigin.hasQuery ||
        siteOrigin.hasFragment ||
        (siteOrigin.path.isNotEmpty && siteOrigin.path != '/')) {
      return null;
    }
    return siteOrigin.replace(path: '/home.php', queryParameters: query);
  }
}

bool _id(String? value) =>
    value != null && RegExp(r'^[1-9]\d*$').hasMatch(value);

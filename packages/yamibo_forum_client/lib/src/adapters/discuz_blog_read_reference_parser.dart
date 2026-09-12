import '../contracts/profile_and_blog.dart';
import '../contracts/user_blog_navigation.dart';

/// Mirrors the read routes in space_blog.php and the touch comment template.
/// Unsupported filters remain browser destinations instead of being discarded.
final class DiscuzBlogReadReferenceParser {
  /// Shares the source root of the configured blog adapters.
  const DiscuzBlogReadReferenceParser(this.origin);

  /// Configured forum origin.
  final Uri origin;

  /// Parses references synchronously without acquiring any remote state.
  UserBlogReadReference? resolve(
    String reference, {
    Uri? baseUri,
    String? actorUserId,
  }) {
    if (!_validOrigin || reference.trim().isEmpty) return null;
    try {
      final base = baseUri ?? origin.replace(path: '/');
      if (!_sameSite(base)) return null;
      final uri = base.resolve(reference.trim().replaceAll('&amp;', '&'));
      if (!_sameSite(uri) || uri.path != '/home.php') return null;
      final pairs = uri.queryParametersAll;
      if (pairs.values.any((values) => values.length != 1)) return null;
      final query = uri.queryParameters;
      if (query['mod'] != 'space') return null;
      final uid = query['uid'];
      if (uid != null && !_id(uid)) return null;
      if (query['do'] == 'profile') {
        if (uid == null ||
            uri.fragment.isNotEmpty ||
            !_only(query, {'mod', 'do', 'uid', 'mobile'})) {
          return null;
        }
        return UserBlogAuthorReference(uid);
      }
      if (query['do'] != 'blog') return null;
      final rawPage = query['page'];
      final page = rawPage == null ? 1 : _number(rawPage);
      if (page == null) return null;
      if (query.containsKey('id')) {
        return _article(uri, query, uid, page);
      }
      if (uri.fragment.isNotEmpty ||
          !_only(query, {
            'mod',
            'do',
            'uid',
            'view',
            'order',
            'catid',
            'classid',
            'page',
            'mobile',
            'fuid',
            'clickid',
            'searchkey',
            'from',
            'friend',
          })) {
        return null;
      }
      // Pagination may retain empty filter slots from the server. Nonempty
      // filters that the native query cannot represent must not change meaning.
      for (final name in ['fuid', 'clickid', 'searchkey', 'from', 'friend']) {
        if ((query[name] ?? '').isNotEmpty) return null;
      }
      final category = _filter(query['catid']);
      final personal = _filter(query['classid']);
      if (category == '' || personal == '') return null;
      final order = query['order'];
      if (order != null && order != 'dateline' && order != 'hot') return null;
      switch (query['view']) {
        case 'all':
          if (personal != null) return null;
          return UserBlogDirectoryReference(
            UserBlogDirectoryQuery.public(
              page: page,
              categoryId: category,
              order: order == 'hot'
                  ? UserBlogOrder.recommended
                  : UserBlogOrder.latest,
            ),
          );
        case 'me':
          if (category != null || order == 'hot') return null;
          return UserBlogDirectoryReference(
            UserBlogDirectoryQuery.self(
              ownerUserId: uid,
              page: page,
              personalCategoryId: personal,
            ),
          );
        case 'we':
          if (category != null ||
              personal != null ||
              order == 'hot' ||
              (uid != null && uid != actorUserId)) {
            return null;
          }
          return UserBlogDirectoryReference(
            UserBlogDirectoryQuery.friends(page: page),
          );
        default:
          // Missing view depends on the current space/session in Discuz.
          return null;
      }
    } on FormatException {
      return null;
    }
  }

  UserBlogDetailReference? _article(
    Uri uri,
    Map<String, String> query,
    String? uid,
    int page,
  ) {
    if (uid == null ||
        !_id(query['id']) ||
        !_only(query, {
          'mod',
          'do',
          'uid',
          'id',
          'page',
          'cid',
          'goto',
          'mobile',
        })) {
      return null;
    }
    var commentId = query['cid'];
    if (commentId != null && !_id(commentId)) return null;
    final last = query['goto'] == 'last';
    if (query.containsKey('goto') && !last) return null;
    final fragment = uri.fragment;
    var focusComments = commentId != null || last;
    if (fragment.isNotEmpty) {
      focusComments = true;
      if (fragment != 'comment' &&
          fragment != 'quickcommentform_${query['id']}') {
        final fragmentId = RegExp(
          r'^comment_([1-9]\d*)(?:_li)?$',
        ).firstMatch(fragment)?.group(1);
        if (fragmentId == null ||
            (commentId != null && commentId != fragmentId)) {
          return null;
        }
        commentId = fragmentId;
      }
    }
    if (last && commentId != null) return null;
    return UserBlogDetailReference(
      UserBlogDetailQuery(
        ownerUserId: uid,
        blogId: query['id']!,
        page: page,
        commentId: commentId,
        lastCommentPage: last,
      ),
      focusComments: focusComments,
    );
  }

  bool get _validOrigin =>
      {'https', 'http'}.contains(origin.scheme) &&
      origin.host.isNotEmpty &&
      origin.userInfo.isEmpty &&
      !origin.hasQuery &&
      !origin.hasFragment &&
      (origin.path.isEmpty || origin.path == '/');

  bool _sameSite(Uri uri) =>
      {'https', 'http'}.contains(uri.scheme) &&
      uri.userInfo.isEmpty &&
      uri.host == origin.host &&
      (uri.port == origin.port || (!uri.hasPort && !origin.hasPort));

  bool _only(Map<String, String> query, Set<String> names) =>
      query.keys.every(names.contains);
  bool _id(String? value) =>
      value != null && RegExp(r'^[1-9]\d*$').hasMatch(value);
  int? _number(String value) => _id(value) ? int.tryParse(value) : null;
  // null means no filter, empty means malformed, otherwise the exact ID.
  String? _filter(String? value) =>
      value == null || value.isEmpty || value == '0'
      ? null
      : _id(value)
      ? value
      : '';
}

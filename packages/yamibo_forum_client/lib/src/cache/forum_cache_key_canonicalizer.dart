import 'forum_cache.dart';

/// Source-neutral forum cache key canonicalizer.
final class ForumCacheKeyCanonicalizer {
  /// Creates a [ForumCacheKeyCanonicalizer].
  const ForumCacheKeyCanonicalizer({required this.siteOrigin});

  /// Forum display snapshot type.
  static const forumDisplaySnapshotType = 'forum.display';

  /// Forum home snapshot type.
  static const forumHomeSnapshotType = 'forum.home';

  /// Thread detail snapshot type.
  static const threadDetailSnapshotType = 'thread.detail';

  /// Site origin.
  final Uri siteOrigin;

  /// Builds the canonical forum-home document descriptor.
  ForumDocumentDescriptor forumHome({
    ForumDocumentRequestProfile requestProfile =
        ForumDocumentRequestProfile.loggedIn,
  }) {
    final uri = siteOrigin.replace(
      path: '/index.php',
      queryParameters: _canonicalParameters(const {'mobile': '2'}),
    );
    return _document(
      ownerType: 'forum',
      ownerId: 'home',
      uri: uri,
      requestProfile: requestProfile,
    );
  }

  /// Builds a canonical forum-display document descriptor.
  ForumDocumentDescriptor forumDisplay({
    required String fid,
    required int page,
    Map<String, String> queryParameters = const {},
    ForumDocumentRequestProfile requestProfile =
        ForumDocumentRequestProfile.loggedIn,
  }) {
    final parameters = _canonicalParameters({
      ...queryParameters,
      'mod': 'forumdisplay',
      'fid': fid,
      'mobile': '2',
      if (page > 1) 'page': '$page',
    });
    final ownerId = <String>[
      'fid=$fid',
      'page=$page',
      for (final entry in parameters.entries)
        if (!const {'mod', 'mobile', 'fid', 'page'}.contains(entry.key))
          '${entry.key}=${entry.value}',
    ].join('&');
    return _document(
      ownerType: 'forum_display',
      ownerId: ownerId,
      uri: siteOrigin.replace(path: '/forum.php', queryParameters: parameters),
      requestProfile: requestProfile,
    );
  }

  /// Builds a canonical thread-detail document descriptor.
  ForumDocumentDescriptor threadDetail({
    required String tid,
    required int page,
    Map<String, String> queryParameters = const {},
    ForumDocumentRequestProfile requestProfile =
        ForumDocumentRequestProfile.loggedIn,
  }) {
    final parameters = _canonicalParameters({
      ...queryParameters,
      'mod': 'viewthread',
      'tid': tid,
      'page': '$page',
      'mobile': '2',
    });
    final ownerId = <String>[
      'tid=$tid',
      'page=$page',
      if (parameters.containsKey('authorid'))
        'authorid=${parameters['authorid']}',
      if (parameters.containsKey('ordertype'))
        'ordertype=${parameters['ordertype']}',
    ].join('&');
    return _document(
      ownerType: 'thread',
      ownerId: ownerId,
      uri: siteOrigin.replace(path: '/forum.php', queryParameters: parameters),
      requestProfile: requestProfile,
    );
  }

  /// Builds the snapshot descriptor paired with the forum-home document.
  ForumSnapshotDescriptor forumHomeSnapshot({
    ForumDocumentRequestProfile requestProfile =
        ForumDocumentRequestProfile.loggedIn,
  }) => _snapshot(
    forumHome(requestProfile: requestProfile),
    forumHomeSnapshotType,
  );

  /// Builds the snapshot descriptor paired with a forum-display document.
  ForumSnapshotDescriptor forumDisplaySnapshot({
    required String fid,
    required int page,
    Map<String, String> queryParameters = const {},
    ForumDocumentRequestProfile requestProfile =
        ForumDocumentRequestProfile.loggedIn,
  }) => _snapshot(
    forumDisplay(
      fid: fid,
      page: page,
      queryParameters: queryParameters,
      requestProfile: requestProfile,
    ),
    forumDisplaySnapshotType,
  );

  /// Builds the snapshot descriptor paired with a thread-detail document.
  ForumSnapshotDescriptor threadDetailSnapshot({
    required String tid,
    required int page,
    Map<String, String> queryParameters = const {},
    ForumDocumentRequestProfile requestProfile =
        ForumDocumentRequestProfile.loggedIn,
  }) => _snapshot(
    threadDetail(
      tid: tid,
      page: page,
      queryParameters: queryParameters,
      requestProfile: requestProfile,
    ),
    threadDetailSnapshotType,
  );

  ForumDocumentDescriptor _document({
    required String ownerType,
    required String ownerId,
    required Uri uri,
    required ForumDocumentRequestProfile requestProfile,
  }) => ForumDocumentDescriptor(
    cacheKey: <Object>[
      'document',
      ownerType,
      ownerId,
      requestProfile.id,
      uri.replace(queryParameters: _canonicalParameters(uri.queryParameters)),
    ].join('|'),
    ownerType: ownerType,
    ownerId: ownerId,
    sourceUri: uri,
    requestProfile: requestProfile,
  );

  ForumSnapshotDescriptor _snapshot(
    ForumDocumentDescriptor document,
    String snapshotType,
  ) => ForumSnapshotDescriptor(
    cacheKey: document.cacheKey.replaceFirst('document|', 'snapshot|'),
    ownerType: document.ownerType,
    ownerId: document.ownerId,
    snapshotType: snapshotType,
    sourceDocumentKey: document.cacheKey,
  );

  Map<String, String> _canonicalParameters(Map<String, String> input) {
    final normalized = <String, String>{};
    for (final entry in input.entries) {
      final key = entry.key.trim();
      final value = entry.value.trim();
      if (key.isNotEmpty && value.isNotEmpty) normalized[key] = value;
    }
    final keys = normalized.keys.toList()..sort();
    return {for (final key in keys) key: normalized[key]!};
  }
}

import '../contracts/cache_load_policy.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/favorite_directories.dart';
import '../contracts/forum_directory.dart';
import '../contracts/profile_and_blog.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import 'discuz_api_client.dart';

final class DiscuzForumDirectoryRepository implements ForumDirectoryRepository {
  const DiscuzForumDirectoryRepository(this._api);
  final DiscuzApiClient _api;

  @override
  ForumDirectorySourceCapabilities get capabilities => _forumCapabilities;

  @override
  Future<DataReadResult<ForumDirectoryData, ForumDirectoryReadCapabilities>>
  load(
    ForumDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final response = await _api.get(module: 'forumindex');
    if (response case ForumTransportError<ForumResponse<DiscuzApiEnvelope>>(
      :final failure,
    )) {
      return _failure<ForumDirectoryData, ForumDirectoryReadCapabilities>(
        failure,
      );
    }
    try {
      final envelope =
          (response as ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>)
              .response
              .body;
      final data = _mapForumDirectory(envelope.variables);
      final issue = _validateForumDirectory(data);
      if (issue != null) {
        return DataReadFailure(
          kind: DataReadFailureKind.parse,
          code: 'forum_directory_identity_invalid',
          diagnosticMessage: issue,
        );
      }
      return DataReadSuccess(
        data: data,
        capabilities: capabilities.toReadCapabilities(),
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'forum_directory_parse_failed',
        diagnosticMessage: 'forum_directory_parse_failed',
      );
    }
  }
}

final class DiscuzFavoriteForumDirectoryRepository
    implements FavoriteForumDirectoryRepository {
  const DiscuzFavoriteForumDirectoryRepository(this._api);
  final DiscuzApiClient _api;

  @override
  FavoriteForumDirectorySourceCapabilities get capabilities =>
      _favoriteForumCapabilities;

  @override
  Future<
    DataReadResult<
      FavoriteForumDirectoryData,
      FavoriteForumDirectoryReadCapabilities
    >
  >
  load(
    FavoriteForumDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final response = await _api.get(module: 'myfavforum');
    if (response case ForumTransportError<ForumResponse<DiscuzApiEnvelope>>(
      :final failure,
    )) {
      return _failure<
        FavoriteForumDirectoryData,
        FavoriteForumDirectoryReadCapabilities
      >(failure);
    }
    try {
      final variables =
          (response as ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>)
              .response
              .body
              .variables;
      return DataReadSuccess(
        data: _mapFavoriteForums(variables),
        capabilities: capabilities.toReadCapabilities(),
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'favorite_forum_directory_parse_failed',
        diagnosticMessage: 'favorite_forum_directory_parse_failed',
      );
    }
  }
}

final class DiscuzFavoriteThreadDirectoryRepository
    implements FavoriteThreadDirectoryRepository {
  const DiscuzFavoriteThreadDirectoryRepository(this._api);
  final DiscuzApiClient _api;

  @override
  FavoriteThreadDirectorySourceCapabilities get capabilities =>
      _favoriteThreadCapabilities;

  @override
  Future<
    DataReadResult<
      FavoriteThreadDirectoryData,
      FavoriteThreadDirectoryReadCapabilities
    >
  >
  load(
    FavoriteThreadDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    if (query.page < 1) {
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        code: 'favorite_thread_directory_query_invalid',
        diagnosticMessage: 'favorite_thread_directory_query_invalid',
      );
    }
    final response = await _api.get(
      module: 'myfavthread',
      queryParameters: {'version': '4', 'page': query.page},
    );
    if (response case ForumTransportError<ForumResponse<DiscuzApiEnvelope>>(
      :final failure,
    )) {
      return _failure<
        FavoriteThreadDirectoryData,
        FavoriteThreadDirectoryReadCapabilities
      >(failure);
    }
    try {
      final variables =
          (response as ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>)
              .response
              .body
              .variables;
      return DataReadSuccess(
        data: _mapFavoriteThreads(variables, query.page),
        capabilities: capabilities.toReadCapabilities(),
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'favorite_thread_directory_parse_failed',
        diagnosticMessage: 'favorite_thread_directory_parse_failed',
      );
    }
  }
}

final class DiscuzCurrentUserProfileRepository
    implements CurrentUserProfileRepository {
  const DiscuzCurrentUserProfileRepository(this._api);
  final DiscuzApiClient _api;

  @override
  CurrentUserProfileSourceCapabilities get capabilities =>
      _currentProfileCapabilities;

  @override
  Future<
    DataReadResult<CurrentUserProfileData, CurrentUserProfileReadCapabilities>
  >
  load(
    CurrentUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final response = await _api.get(module: 'profile');
    if (response case ForumTransportError<ForumResponse<DiscuzApiEnvelope>>(
      :final failure,
    )) {
      return _failure<
        CurrentUserProfileData,
        CurrentUserProfileReadCapabilities
      >(failure);
    }
    try {
      final variables =
          (response as ForumTransportSuccess<ForumResponse<DiscuzApiEnvelope>>)
              .response
              .body
              .variables;
      final data = _mapCurrentProfile(variables);
      var values = capabilities.values;
      DataCapabilitySupport optional(bool present) => present
          ? DataCapabilitySupport.supported
          : DataCapabilitySupport.unsupported;
      values = values
          .withSupport(
            CurrentUserProfileCapability.avatarReference,
            optional(data.avatarUrl != null),
          )
          .withSupport(
            CurrentUserProfileCapability.groupIdentity,
            optional(data.groupId != null),
          )
          .withSupport(
            CurrentUserProfileCapability.creditTotal,
            optional(data.creditTotal != null),
          )
          .withSupport(
            CurrentUserProfileCapability.postCount,
            optional(data.postCount != null),
          )
          .withSupport(
            CurrentUserProfileCapability.threadCount,
            optional(data.threadCount != null),
          );
      return DataReadSuccess(
        data: data,
        capabilities: CurrentUserProfileReadCapabilities(values: values),
        metadata: const DataReadMetadata.network(),
      );
    } on _ProfileUnauthorized {
      return const DataReadFailure(
        kind: DataReadFailureKind.unauthorized,
        code: 'current_user_profile_unauthorized',
        diagnosticMessage: 'current_user_profile_unauthorized',
      );
    } on FormatException {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'current_user_profile_parse_failed',
        diagnosticMessage: 'current_user_profile_parse_failed',
      );
    }
  }
}

DataReadFailure<T, C> _failure<T, C>(ForumTransportFailure failure) =>
    DataReadFailure<T, C>(
      kind: toReadFailureKind(failure.kind),
      code: failure.code,
      statusCode: failure.statusCode,
      diagnosticMessage: failure.code,
    );

ForumDirectoryData _mapForumDirectory(Map<String, Object?> variables) {
  final categories = _list(variables['catlist'], 'forum_categories_missing');
  final rawForums = _list(variables['forumlist'], 'forum_list_missing');
  final forums = rawForums.map((item) => _mapForum(_map(item))).toList();
  final byId = <String, ForumDirectoryForum>{};
  for (final forum in forums) {
    if (byId[forum.fid] != null) throw const FormatException('duplicate_fid');
    byId[forum.fid] = forum;
  }
  final assigned = <String>{};
  final sections = <ForumDirectorySection>[];
  for (final raw in categories) {
    final json = _map(raw);
    final identity = _requiredText(json['fid'], 'category_identity_missing');
    final title = _requiredText(json['name'], 'category_title_missing');
    final sectionForums = <ForumDirectoryForum>[];
    for (final rawFid in _list(json['forums'], 'category_forums_missing')) {
      final fid = rawFid.toString().trim();
      final forum = byId[fid];
      if (forum == null) throw const FormatException('unknown_forum');
      assigned.add(fid);
      sectionForums.add(forum);
    }
    sections.add(
      ForumDirectorySection(
        identity: identity,
        title: title,
        forums: sectionForums,
      ),
    );
  }
  final uncategorized = forums
      .where((forum) => !assigned.contains(forum.fid))
      .toList();
  if (uncategorized.isNotEmpty) {
    sections.add(
      ForumDirectorySection(
        identity: 'api-uncategorized',
        title: '',
        forums: uncategorized,
        kind: ForumDirectorySectionKind.uncategorized,
      ),
    );
  }
  return ForumDirectoryData(sections: sections);
}

ForumDirectoryForum _mapForum(Map<String, Object?> json) => ForumDirectoryForum(
  fid: _requiredText(json['fid'], 'forum_identity_missing'),
  title: _requiredText(json['name'], 'forum_title_missing'),
  description: _text(json['description']),
  todayPosts: _nullableNonNegativeInt(json['todayposts']),
  children: json['sublist'] == null
      ? const []
      : _list(
          json['sublist'],
          'forum_sublist_invalid',
        ).map((item) => _mapForum(_map(item))).toList(),
);

String? _validateForumDirectory(ForumDirectoryData data) {
  final sections = <String>{};
  final forums = <String>{};
  for (final section in data.sections) {
    if (section.identity.trim().isEmpty || !sections.add(section.identity)) {
      return 'forum_directory_section_identity_invalid';
    }
    for (final forum in section.forums) {
      if (forum.fid.trim().isEmpty || !forums.add(forum.fid)) {
        return 'forum_directory_forum_identity_invalid';
      }
    }
  }
  return null;
}

FavoriteForumDirectoryData _mapFavoriteForums(Map<String, Object?> variables) {
  final ids = <String>{};
  final remoteIds = <String>{};
  final items = <FavoriteForumEntry>[];
  for (final raw in _list(variables['list'], 'favorite_forum_list_missing')) {
    final json = _map(raw);
    final item = FavoriteForumEntry(
      fid: _requiredText(json['id'], 'favorite_forum_fid_missing'),
      title: _requiredText(json['title'], 'favorite_forum_title_missing'),
      remoteFavoriteId: _nullableText(json['favid']),
      description: _nullableText(json['description']),
      threadCount: _nullableNonNegativeInt(json['threads']),
      postCount: _nullableNonNegativeInt(json['posts']),
      todayPostCount: _nullableNonNegativeInt(json['todayposts']),
    );
    if (!ids.add(item.fid) ||
        (item.remoteFavoriteId != null &&
            !remoteIds.add(item.remoteFavoriteId!))) {
      throw const FormatException('favorite_forum_identity_duplicated');
    }
    items.add(item);
  }
  return FavoriteForumDirectoryData(items: items);
}

FavoriteThreadDirectoryData _mapFavoriteThreads(
  Map<String, Object?> variables,
  int page,
) {
  final rawItems = _list(variables['list'], 'favorite_thread_list_missing');
  final perPage = _requiredNonNegativeInt(variables['perpage']);
  final total = _requiredNonNegativeInt(variables['count']);
  if (perPage == 0) throw const FormatException('page_size_invalid');
  final totalPages = total == 0 ? 1 : (total / perPage).ceil();
  if (page > totalPages) throw const FormatException('page_out_of_range');
  final expected = total == 0
      ? 0
      : page < totalPages
      ? perPage
      : total - ((page - 1) * perPage);
  if (rawItems.length != expected) {
    throw const FormatException('pagination_inconsistent');
  }
  final ids = <String>{};
  final remoteIds = <String>{};
  final items = <FavoriteThreadReference>[];
  for (final raw in rawItems) {
    final json = _map(raw);
    final seconds = _nullableNonNegativeInt(json['dateline']);
    final item = FavoriteThreadReference(
      tid: _requiredText(json['id'], 'favorite_thread_tid_missing'),
      title: _requiredText(json['title'], 'favorite_thread_title_missing'),
      remoteFavoriteId: _nullableText(json['favid']),
      description: _nullableText(json['description']),
      authorName: _nullableText(json['author']),
      replyCount: _nullableNonNegativeInt(json['replies']),
      favoritedAt: seconds == null || seconds == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
    );
    if (!ids.add(item.tid) ||
        (item.remoteFavoriteId != null &&
            !remoteIds.add(item.remoteFavoriteId!))) {
      throw const FormatException('favorite_thread_identity_duplicated');
    }
    items.add(item);
  }
  return FavoriteThreadDirectoryData(
    items: items,
    pagination: FavoriteThreadPagination(
      currentPage: page,
      pageSize: perPage,
      totalItems: total,
      totalPages: totalPages,
      hasPrevious: page > 1,
      hasNext: page * perPage < total,
    ),
  );
}

CurrentUserProfileData _mapCurrentProfile(Map<String, Object?> variables) {
  final memberId = _nullableText(variables['member_uid']);
  if (memberId == null || memberId == '0') throw const _ProfileUnauthorized();
  final space = _map(variables['space']);
  final spaceId = _nullableText(space['uid']);
  if (spaceId != null && spaceId != memberId) {
    throw const FormatException('profile_identity_mismatch');
  }
  final memberName = _nullableText(variables['member_username']);
  final spaceName = _nullableText(space['username']);
  if (memberName != null && spaceName != null && memberName != spaceName) {
    throw const FormatException('profile_name_mismatch');
  }
  final displayName = spaceName ?? memberName;
  if (displayName == null) throw const FormatException('profile_name_missing');
  return CurrentUserProfileData(
    identity: ProfileUserIdentity(userId: memberId, displayName: displayName),
    avatarUrl: _nullableText(variables['member_avatar']),
    groupId: _nullableText(variables['groupid']),
    creditTotal: _nullableSignedInt(space['credits']),
    postCount: _nullableNonNegativeInt(space['posts']),
    threadCount: _nullableNonNegativeInt(space['threads']),
  );
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map) throw const FormatException('map_expected');
  return {for (final entry in value.entries) entry.key.toString(): entry.value};
}

List<Object?> _list(Object? value, String code) {
  if (value is! List) throw FormatException(code);
  return List<Object?>.from(value);
}

String _text(Object? value) => value?.toString().trim() ?? '';
String _requiredText(Object? value, String code) {
  final result = _text(value);
  if (result.isEmpty) throw FormatException(code);
  return result;
}

String? _nullableText(Object? value) {
  final result = _text(value);
  return result.isEmpty ? null : result;
}

int _requiredNonNegativeInt(Object? value) {
  final result = _nullableNonNegativeInt(value);
  if (result == null) throw const FormatException('integer_missing');
  return result;
}

int? _nullableNonNegativeInt(Object? value) {
  if (value == null || value.toString().trim().isEmpty) return null;
  final raw = value.toString().trim();
  if (!RegExp(r'^\d+$').hasMatch(raw)) {
    throw const FormatException('integer_invalid');
  }
  return int.tryParse(raw);
}

int? _nullableSignedInt(Object? value) {
  if (value == null || value.toString().trim().isEmpty) return null;
  final raw = value.toString().trim();
  if (!RegExp(r'^-?\d+$').hasMatch(raw)) {
    throw const FormatException('integer_invalid');
  }
  return int.tryParse(raw);
}

final class _ProfileUnauthorized implements Exception {
  const _ProfileUnauthorized();
}

final _forumCapabilities = ForumDirectorySourceCapabilities(
  values: DataCapabilitySet.supported(ForumDirectoryCapability.values),
);
final _favoriteForumCapabilities = FavoriteForumDirectorySourceCapabilities(
  values: DataCapabilitySet.supported(FavoriteForumDirectoryCapability.values),
);
final _favoriteThreadCapabilities = FavoriteThreadDirectorySourceCapabilities(
  values: DataCapabilitySet.supported(FavoriteThreadDirectoryCapability.values),
  paginationPrecision: PaginationPrecision.exact,
);
final _currentProfileCapabilities = CurrentUserProfileSourceCapabilities(
  values: DataCapabilitySet.supported(CurrentUserProfileCapability.values),
);

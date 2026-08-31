// ignore_for_file: public_member_api_docs

import '../client/forum_client_config.dart';
import '../contracts/cache_load_policy.dart';
import '../contracts/data_read_contract.dart';
import '../contracts/profile_and_blog.dart';
import '../network/forum_network.dart';
import '../network/forum_request.dart';
import '../network/forum_request_profile.dart';
import '../network/forum_response.dart';
import '../network/forum_transport.dart';
import 'discuz_profile_html_parsers.dart';

final class DiscuzForumUserProfileRepository
    implements ForumUserProfileRepository {
  DiscuzForumUserProfileRepository({
    required ForumClientConfig config,
    required this.network,
    required this.requestProfiles,
    ForumUserProfileHtmlParser? parser,
  }) : _config = config,
       _parser =
           parser ?? ForumUserProfileHtmlParser(siteOrigin: config.siteOrigin);

  final ForumClientConfig _config;
  final ForumClientNetwork network;
  final ForumRequestProfileResolver requestProfiles;
  final ForumUserProfileHtmlParser _parser;

  @override
  ForumUserProfileSourceCapabilities get capabilities => _profileCapabilities;

  @override
  Future<DataReadResult<ForumUserProfileData, ForumUserProfileReadCapabilities>>
  load(
    ForumUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final userId = query.userId.trim();
    if (userId.isEmpty) {
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        code: 'forum_user_profile_query_invalid',
        diagnosticMessage: 'forum_user_profile_query_invalid',
      );
    }
    final uri = _config.siteOrigin.replace(
      path: '/home.php',
      queryParameters: <String, String>{
        'mod': 'space',
        'uid': userId,
        'do': 'profile',
        'mobile': '2',
        if (query.view == ForumUserProfileView.self) 'mycenter': '1',
      },
    );
    final result = await network.send(
      ForumRequest(
        method: ForumRequestMethod.get,
        uri: uri,
        context: ForumRequestContext(
          operation: query.view == ForumUserProfileView.self
              ? 'profile.user.self.html'
              : 'profile.user.public.html',
          module: 'profile',
          pageKind: 'profile.user',
        ),
        headers: requestProfiles
            .resolve(ForumRequestProfileKind.mobileHtml)
            .headers,
      ),
    );
    final body =
        _textOrFailure<ForumUserProfileData, ForumUserProfileReadCapabilities>(
          result,
        );
    if (body case DataReadFailure<String, Object?> failure) {
      return failure.retype();
    }
    final html = (body as DataReadSuccess<String, Object?>).data;
    if (query.view == ForumUserProfileView.self &&
        DiscuzProfileAuthPageDetector.isLoginPage(html)) {
      return const DataReadFailure(
        kind: DataReadFailureKind.unauthorized,
        code: 'forum_user_profile_unauthorized',
        diagnosticMessage: 'forum_user_profile_unauthorized',
      );
    }
    try {
      final data = _parser.parse(html: html, expectedUserId: userId);
      return DataReadSuccess(
        data: data,
        capabilities: _profileReadCapabilities(data),
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'forum_user_profile_parse_failed',
        diagnosticMessage: 'forum_user_profile_parse_failed',
      );
    }
  }
}

final class DiscuzUserBlogDirectoryRepository
    implements UserBlogDirectoryRepository {
  DiscuzUserBlogDirectoryRepository({
    required ForumClientConfig config,
    required this.network,
    required this.requestProfiles,
    UserBlogDirectoryHtmlParser? parser,
  }) : _config = config,
       _parser =
           parser ?? UserBlogDirectoryHtmlParser(siteOrigin: config.siteOrigin);

  final ForumClientConfig _config;
  final ForumClientNetwork network;
  final ForumRequestProfileResolver requestProfiles;
  final UserBlogDirectoryHtmlParser _parser;

  @override
  UserBlogDirectorySourceCapabilities get capabilities =>
      _blogDirectoryCapabilities;

  @override
  Future<
    DataReadResult<UserBlogDirectoryData, UserBlogDirectoryReadCapabilities>
  >
  load(
    UserBlogDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    if (query.page < 1 ||
        (query.scope != UserBlogFeedScope.public && query.order != null)) {
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        code: 'user_blog_directory_query_invalid',
        diagnosticMessage: 'user_blog_directory_query_invalid',
      );
    }
    final order = query.scope == UserBlogFeedScope.public
        ? (query.order ?? UserBlogOrder.latest)
        : null;
    final uri = _config.siteOrigin.replace(
      path: '/home.php',
      queryParameters: <String, String>{
        'mod': 'space',
        'do': 'blog',
        'view': _scopeValue(query.scope),
        'mobile': '2',
        if (order == UserBlogOrder.recommended) 'order': 'hot',
        if (query.page > 1) 'page': '${query.page}',
      },
    );
    final result = await network.send(
      ForumRequest(
        method: ForumRequestMethod.get,
        uri: uri,
        context: ForumRequestContext(
          operation: 'profile.blog.directory.html',
          module: 'profile',
          pageKind: 'profile.blog.${_scopeValue(query.scope)}',
        ),
        headers: requestProfiles
            .resolve(ForumRequestProfileKind.mobileHtml)
            .headers,
      ),
    );
    final body =
        _textOrFailure<
          UserBlogDirectoryData,
          UserBlogDirectoryReadCapabilities
        >(result);
    if (body case DataReadFailure<String, Object?> failure) {
      return failure.retype();
    }
    final html = (body as DataReadSuccess<String, Object?>).data;
    if (query.scope != UserBlogFeedScope.public &&
        DiscuzProfileAuthPageDetector.isLoginPage(html)) {
      return const DataReadFailure(
        kind: DataReadFailureKind.unauthorized,
        code: 'user_blog_directory_unauthorized',
        diagnosticMessage: 'user_blog_directory_unauthorized',
      );
    }
    try {
      final parsed = _parser.parse(html: html, query: query);
      return DataReadSuccess(
        data: parsed.data,
        capabilities: _blogDirectoryReadCapabilities(
          parsed.data,
          parsed.paginationPrecision,
        ),
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'user_blog_directory_parse_failed',
        diagnosticMessage: 'user_blog_directory_parse_failed',
      );
    }
  }
}

final class DiscuzUserBlogDetailRepository implements UserBlogDetailRepository {
  DiscuzUserBlogDetailRepository({
    required ForumClientConfig config,
    required this.network,
    required this.requestProfiles,
    UserBlogDetailHtmlParser? parser,
  }) : _config = config,
       _parser =
           parser ?? UserBlogDetailHtmlParser(siteOrigin: config.siteOrigin);

  final ForumClientConfig _config;
  final ForumClientNetwork network;
  final ForumRequestProfileResolver requestProfiles;
  final UserBlogDetailHtmlParser _parser;

  @override
  UserBlogDetailSourceCapabilities get capabilities => _blogDetailCapabilities;

  @override
  Future<DataReadResult<UserBlogDetailData, UserBlogDetailReadCapabilities>>
  load(
    UserBlogDetailQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final ownerId = query.ownerUserId.trim();
    final blogId = query.blogId.trim();
    if (ownerId.isEmpty || blogId.isEmpty) {
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        code: 'user_blog_detail_query_invalid',
        diagnosticMessage: 'user_blog_detail_query_invalid',
      );
    }
    final uri = _config.siteOrigin.replace(
      path: '/home.php',
      queryParameters: <String, String>{
        'mod': 'space',
        'uid': ownerId,
        'do': 'blog',
        'id': blogId,
        'mobile': '2',
      },
    );
    final result = await network.send(
      ForumRequest(
        method: ForumRequestMethod.get,
        uri: uri,
        context: const ForumRequestContext(
          operation: 'profile.blog.detail.html',
          module: 'profile',
          pageKind: 'profile.blog.detail',
        ),
        headers: requestProfiles
            .resolve(ForumRequestProfileKind.mobileHtml)
            .headers,
      ),
    );
    final body =
        _textOrFailure<UserBlogDetailData, UserBlogDetailReadCapabilities>(
          result,
        );
    if (body case DataReadFailure<String, Object?> failure) {
      return failure.retype();
    }
    try {
      final data = _parser.parse(
        html: (body as DataReadSuccess<String, Object?>).data,
        query: query,
      );
      return DataReadSuccess(
        data: data,
        capabilities: _blogDetailReadCapabilities(data),
        metadata: const DataReadMetadata.network(),
      );
    } on FormatException {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'user_blog_detail_parse_failed',
        diagnosticMessage: 'user_blog_detail_parse_failed',
      );
    }
  }
}

DataReadResult<String, Object?> _textOrFailure<T, C>(
  ForumTransportResult<ForumResponse<Object?>> result,
) {
  if (result case ForumTransportError<ForumResponse<Object?>>(:final failure)) {
    return DataReadFailure(
      kind: toReadFailureKind(failure.kind),
      code: failure.code,
      statusCode: failure.statusCode,
      diagnosticMessage: failure.code,
    );
  }
  final body =
      (result as ForumTransportSuccess<ForumResponse<Object?>>).response.body;
  if (body is! String) {
    return const DataReadFailure(
      kind: DataReadFailureKind.parse,
      code: 'text_response_expected',
      diagnosticMessage: 'text_response_expected',
    );
  }
  return DataReadSuccess(
    data: body,
    capabilities: null,
    metadata: const DataReadMetadata.network(),
  );
}

String _scopeValue(UserBlogFeedScope scope) => switch (scope) {
  UserBlogFeedScope.friends => 'we',
  UserBlogFeedScope.self => 'me',
  UserBlogFeedScope.public => 'all',
};

DataCapabilitySet<T> _optional<T extends Enum>(
  DataCapabilitySet<T> values,
  T capability,
  bool supported,
) => values.withSupport(
  capability,
  supported
      ? DataCapabilitySupport.supported
      : DataCapabilitySupport.unsupported,
);

ForumUserProfileReadCapabilities _profileReadCapabilities(
  ForumUserProfileData data,
) {
  var values = _profileCapabilities.values;
  values = _optional(
    values,
    ForumUserProfileCapability.avatarReference,
    data.avatarUrl != null,
  );
  values = _optional(
    values,
    ForumUserProfileCapability.coverReference,
    data.coverUrl != null,
  );
  values = _optional(
    values,
    ForumUserProfileCapability.signatureMarkup,
    data.signatureHtml != null,
  );
  return ForumUserProfileReadCapabilities(values: values);
}

UserBlogDirectoryReadCapabilities _blogDirectoryReadCapabilities(
  UserBlogDirectoryData data,
  PaginationPrecision precision,
) {
  var values = _blogDirectoryCapabilities.values;
  final items = data.items;
  values = _optional(
    values,
    UserBlogDirectoryCapability.excerpt,
    items.any((item) => item.excerpt != null),
  );
  values = _optional(
    values,
    UserBlogDirectoryCapability.author,
    items.any((item) => item.authorName != null),
  );
  values = _optional(
    values,
    UserBlogDirectoryCapability.avatarReference,
    items.any((item) => item.avatarUrl != null),
  );
  values = _optional(
    values,
    UserBlogDirectoryCapability.publishedAtText,
    items.any((item) => item.publishedAtText != null),
  );
  values = _optional(
    values,
    UserBlogDirectoryCapability.directionalPagination,
    data.pagination.hasPrevious != null || data.pagination.hasNext != null,
  );
  values = _optional(
    values,
    UserBlogDirectoryCapability.totalPageCount,
    data.pagination.totalPages != null,
  );
  return UserBlogDirectoryReadCapabilities(
    values: values,
    paginationPrecision: precision,
  );
}

UserBlogDetailReadCapabilities _blogDetailReadCapabilities(
  UserBlogDetailData data,
) {
  var values = _blogDetailCapabilities.values;
  values = _optional(
    values,
    UserBlogDetailCapability.author,
    data.authorName != null,
  );
  values = _optional(
    values,
    UserBlogDetailCapability.avatarReference,
    data.avatarUrl != null,
  );
  values = _optional(
    values,
    UserBlogDetailCapability.publishedAtText,
    data.publishedAtText != null,
  );
  values = _optional(
    values,
    UserBlogDetailCapability.viewCount,
    data.viewCount != null,
  );
  values = _optional(
    values,
    UserBlogDetailCapability.commentCount,
    data.commentCount != null,
  );
  values = _optional(
    values,
    UserBlogDetailCapability.commentAvatarReference,
    data.comments.any((item) => item.avatarUrl != null),
  );
  values = _optional(
    values,
    UserBlogDetailCapability.commentPublishedAtText,
    data.comments.any((item) => item.publishedAtText != null),
  );
  values = _optional(
    values,
    UserBlogDetailCapability.commentingAvailability,
    data.commentsOpen != null,
  );
  return UserBlogDetailReadCapabilities(values: values);
}

final _profileCapabilities = ForumUserProfileSourceCapabilities(
  values: DataCapabilitySet.supported(ForumUserProfileCapability.values),
);

final _blogDirectoryCapabilities = UserBlogDirectorySourceCapabilities(
  values: DataCapabilitySet.supported(UserBlogDirectoryCapability.values),
  paginationPrecision: PaginationPrecision.unknown,
);

final _blogDetailCapabilities = UserBlogDetailSourceCapabilities(
  values: DataCapabilitySet.supported(UserBlogDetailCapability.values),
);

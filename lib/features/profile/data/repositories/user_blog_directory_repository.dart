import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/data_source/api_result_data_read_adapter.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/profile/data/services/discuz_profile_auth_page_detector.dart';
import 'package:y300/features/profile/data/services/user_blog_directory_html_parser.dart';
import 'package:y300/features/profile/domain/models/user_blog_models.dart';
import 'package:y300/features/profile/domain/repositories/user_blog_directory_repository.dart';

final class DiscuzUserBlogDirectoryRepository
    implements UserBlogDirectoryRepository {
  const DiscuzUserBlogDirectoryRepository({
    required YamiboHtmlClient htmlClient,
    UserBlogDirectoryHtmlParser parser = const UserBlogDirectoryHtmlParser(),
  }) : _htmlClient = htmlClient,
       _parser = parser;

  final YamiboHtmlClient _htmlClient;
  final UserBlogDirectoryHtmlParser _parser;

  @override
  UserBlogDirectorySourceCapabilities get capabilities => _capabilities;

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
        diagnosticMessage: 'User blog directory query is invalid.',
      );
    }
    final order = query.scope == UserBlogFeedScope.public
        ? (query.order ?? UserBlogOrder.latest)
        : null;
    final result = await _htmlClient.getMobilePage(
      path: '/home.php',
      queryParameters: <String, String>{
        'mod': 'space',
        'do': 'blog',
        'view': _scopeValue(query.scope),
        'mobile': '2',
        if (order == UserBlogOrder.recommended) 'order': 'hot',
        if (query.page > 1) 'page': query.page.toString(),
      },
      context: YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'profile.blog.directory.html',
        module: 'profile',
        pageKind: 'profile.blog.${_scopeValue(query.scope)}',
      ),
    );
    if (result case ApiFailure<String>(:final error)) {
      return dataReadFailureFromApiError(error);
    }
    final html = result.dataOrNull ?? '';
    if ((query.scope == UserBlogFeedScope.self ||
            query.scope == UserBlogFeedScope.friends) &&
        DiscuzProfileAuthPageDetector.isLoginPage(html)) {
      return const DataReadFailure(
        kind: DataReadFailureKind.unauthorized,
        code: 'user_blog_directory_unauthorized',
        diagnosticMessage: 'User blog directory requires authentication.',
      );
    }
    try {
      final parsed = _parser.parse(
        html: html,
        query: query,
        siteOrigin: '${AppConfig.siteBaseUrl}/',
      );
      return DataReadSuccess(
        data: parsed.data,
        capabilities: _readCapabilities(
          parsed.data,
          parsed.paginationPrecision,
        ),
        metadata: const DataReadMetadata.network(),
      );
    } catch (_) {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'user_blog_directory_parse_failed',
        diagnosticMessage: 'User blog directory HTML is invalid.',
      );
    }
  }

  String _scopeValue(UserBlogFeedScope scope) {
    return switch (scope) {
      UserBlogFeedScope.friends => 'we',
      UserBlogFeedScope.self => 'me',
      UserBlogFeedScope.public => 'all',
    };
  }

  UserBlogDirectoryReadCapabilities _readCapabilities(
    UserBlogDirectoryData data,
    PaginationPrecision precision,
  ) {
    var values = _capabilities.values;
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
}

DataCapabilitySet<UserBlogDirectoryCapability> _optional(
  DataCapabilitySet<UserBlogDirectoryCapability> values,
  UserBlogDirectoryCapability capability,
  bool supported,
) {
  return values.withSupport(
    capability,
    supported
        ? DataCapabilitySupport.supported
        : DataCapabilitySupport.unsupported,
  );
}

final _capabilities = UserBlogDirectorySourceCapabilities(
  values: DataCapabilitySet<UserBlogDirectoryCapability>.supported(
    UserBlogDirectoryCapability.values,
  ),
  paginationPrecision: PaginationPrecision.unknown,
);

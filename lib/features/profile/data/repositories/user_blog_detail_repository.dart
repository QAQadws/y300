import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/data_source/api_result_data_read_adapter.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/profile/data/services/user_blog_detail_html_parser.dart';
import 'package:y300/features/profile/domain/models/user_blog_models.dart';
import 'package:y300/features/profile/domain/repositories/user_blog_detail_repository.dart';

final class DiscuzUserBlogDetailRepository implements UserBlogDetailRepository {
  const DiscuzUserBlogDetailRepository({
    required YamiboHtmlClient htmlClient,
    UserBlogDetailHtmlParser parser = const UserBlogDetailHtmlParser(),
  }) : _htmlClient = htmlClient,
       _parser = parser;

  final YamiboHtmlClient _htmlClient;
  final UserBlogDetailHtmlParser _parser;

  @override
  UserBlogDetailSourceCapabilities get capabilities => _capabilities;

  @override
  Future<DataReadResult<UserBlogDetailData, UserBlogDetailReadCapabilities>>
  load(
    UserBlogDetailQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    final ownerUserId = query.ownerUserId.trim();
    final blogId = query.blogId.trim();
    if (ownerUserId.isEmpty || blogId.isEmpty) {
      return const DataReadFailure(
        kind: DataReadFailureKind.business,
        code: 'user_blog_detail_query_invalid',
        diagnosticMessage: 'User blog detail query is invalid.',
      );
    }
    final result = await _htmlClient.getMobilePage(
      path: '/home.php',
      queryParameters: <String, String>{
        'mod': 'space',
        'uid': ownerUserId,
        'do': 'blog',
        'id': blogId,
        'mobile': '2',
      },
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'profile.blog.detail.html',
        module: 'profile',
        pageKind: 'profile.blog.detail',
      ),
    );
    if (result case ApiFailure<String>(:final error)) {
      return dataReadFailureFromApiError(error);
    }
    try {
      final data = _parser.parse(
        html: result.dataOrNull ?? '',
        query: query,
        siteOrigin: '${AppConfig.siteBaseUrl}/',
      );
      return DataReadSuccess(
        data: data,
        capabilities: _readCapabilities(data),
        metadata: const DataReadMetadata.network(),
      );
    } catch (_) {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        code: 'user_blog_detail_parse_failed',
        diagnosticMessage: 'User blog detail HTML is invalid.',
      );
    }
  }

  UserBlogDetailReadCapabilities _readCapabilities(UserBlogDetailData data) {
    var values = _capabilities.values;
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
}

DataCapabilitySet<UserBlogDetailCapability> _optional(
  DataCapabilitySet<UserBlogDetailCapability> values,
  UserBlogDetailCapability capability,
  bool supported,
) {
  return values.withSupport(
    capability,
    supported
        ? DataCapabilitySupport.supported
        : DataCapabilitySupport.unsupported,
  );
}

final _capabilities = UserBlogDetailSourceCapabilities(
  values: DataCapabilitySet<UserBlogDetailCapability>.supported(
    UserBlogDetailCapability.values,
  ),
);

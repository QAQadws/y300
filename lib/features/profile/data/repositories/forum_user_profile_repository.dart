import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/data_source/api_result_data_read_adapter.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/profile/data/services/discuz_profile_auth_page_detector.dart';
import 'package:y300/features/profile/data/services/forum_user_profile_html_parser.dart';
import 'package:y300/features/profile/domain/models/forum_user_profile_models.dart';
import 'package:y300/features/profile/domain/repositories/forum_user_profile_repository.dart';

final class DiscuzForumUserProfileRepository
    implements ForumUserProfileRepository {
  const DiscuzForumUserProfileRepository({
    required YamiboHtmlClient htmlClient,
    ForumUserProfileHtmlParser parser = const ForumUserProfileHtmlParser(),
  }) : _htmlClient = htmlClient,
       _parser = parser;

  final YamiboHtmlClient _htmlClient;
  final ForumUserProfileHtmlParser _parser;

  @override
  ForumUserProfileSourceCapabilities get capabilities => _capabilities;

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
        diagnosticMessage: 'Forum user profile query is invalid.',
      );
    }
    final result = await _htmlClient.getMobilePage(
      path: '/home.php',
      queryParameters: <String, String>{
        'mod': 'space',
        'uid': userId,
        'do': 'profile',
        'mobile': '2',
        if (query.view == ForumUserProfileView.self) 'mycenter': '1',
      },
      context: YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: query.view == ForumUserProfileView.self
            ? 'profile.user.self.html'
            : 'profile.user.public.html',
        module: 'profile',
        pageKind: 'profile.user',
      ),
    );
    if (result case ApiFailure<String>(:final error)) {
      return dataReadFailureFromApiError(error);
    }
    final html = result.dataOrNull ?? '';
    if (query.view == ForumUserProfileView.self &&
        DiscuzProfileAuthPageDetector.isLoginPage(html)) {
      return const DataReadFailure(
        kind: DataReadFailureKind.unauthorized,
        code: 'forum_user_profile_unauthorized',
        diagnosticMessage: 'Forum user profile requires authentication.',
      );
    }
    try {
      final data = _parser.parse(
        html: html,
        expectedUserId: userId,
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
        code: 'forum_user_profile_parse_failed',
        diagnosticMessage: 'Forum user profile HTML is invalid.',
      );
    }
  }

  ForumUserProfileReadCapabilities _readCapabilities(
    ForumUserProfileData data,
  ) {
    var values = _capabilities.values;
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
}

DataCapabilitySet<ForumUserProfileCapability> _optional(
  DataCapabilitySet<ForumUserProfileCapability> values,
  ForumUserProfileCapability capability,
  bool supported,
) {
  return values.withSupport(
    capability,
    supported
        ? DataCapabilitySupport.supported
        : DataCapabilitySupport.unsupported,
  );
}

final _capabilities = ForumUserProfileSourceCapabilities(
  values: DataCapabilitySet<ForumUserProfileCapability>.supported(
    ForumUserProfileCapability.values,
  ),
);

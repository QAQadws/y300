import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/profile/data/models/user_profile_models.dart';
import 'package:y300/features/profile/data/user_profile_html_parser.dart';

abstract class UserProfileRepository {
  Future<ApiResult<UserProfileData>> getUserProfile({required String uid});
}

class UserProfileHtmlRepository implements UserProfileRepository {
  const UserProfileHtmlRepository({
    required YamiboHtmlClient htmlClient,
    UserProfileHtmlParser parser = const UserProfileHtmlParser(),
  }) : _htmlClient = htmlClient,
       _parser = parser;

  final YamiboHtmlClient _htmlClient;
  final UserProfileHtmlParser _parser;

  @override
  Future<ApiResult<UserProfileData>> getUserProfile({
    required String uid,
  }) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      return const ApiFailure<UserProfileData>(
        ApiError(type: ApiErrorType.business, message: '用户 UID 缺失'),
      );
    }
    final htmlResult = await _htmlClient.getMobilePage(
      path: '/home.php',
      queryParameters: <String, String>{
        'mod': 'space',
        'uid': normalizedUid,
        'do': 'profile',
        'mobile': '2',
      },
      context: const YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: 'profile.user.mobile',
        module: 'profile',
        pageKind: 'user.profile',
      ),
    );
    return htmlResult.when(
      success: (html) {
        try {
          return ApiSuccess<UserProfileData>(
            _parser.parse(html, fallbackUid: normalizedUid),
          );
        } catch (error) {
          return ApiFailure<UserProfileData>(
            ApiError(
              type: ApiErrorType.parse,
              message: '个人页解析失败: $error',
              raw: error,
            ),
          );
        }
      },
      failure: (error) => ApiFailure<UserProfileData>(
        ApiError(
          type: error.type,
          message: '个人页加载失败: ${error.message}',
          code: error.code,
          statusCode: error.statusCode,
          raw: error.raw,
        ),
      ),
    );
  }
}

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  return UserProfileHtmlRepository(
    htmlClient: ref.watch(yamiboHtmlClientProvider),
  );
});

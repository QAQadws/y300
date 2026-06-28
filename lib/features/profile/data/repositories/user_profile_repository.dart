import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_request_context.dart';
import 'package:y300/features/profile/data/models/user_profile_models.dart';
import 'package:y300/features/profile/data/services/user_profile_html_parser.dart';

abstract class UserProfileRepository {
  Future<ApiResult<UserProfileData>> getUserProfile({required String uid});

  Future<ApiResult<UserProfileData>> getMyProfile({required String uid});
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
  Future<ApiResult<UserProfileData>> getUserProfile({required String uid}) {
    return _getProfile(
      uid: uid,
      queryParameters: const <String, String>{},
      operation: 'profile.user.mobile',
      pageKind: 'user.profile',
      missingUidMessage: '用户 UID 缺失',
      failurePrefix: '个人页加载失败',
      parseFailurePrefix: '个人页解析失败',
    );
  }

  @override
  Future<ApiResult<UserProfileData>> getMyProfile({required String uid}) {
    return _getProfile(
      uid: uid,
      queryParameters: const <String, String>{'mycenter': '1'},
      operation: 'profile.my.mobile',
      pageKind: 'profile.my',
      missingUidMessage: '当前用户 UID 缺失，请先登录',
      failurePrefix: '我的资料加载失败',
      parseFailurePrefix: '我的资料解析失败',
    );
  }

  Future<ApiResult<UserProfileData>> _getProfile({
    required String uid,
    required Map<String, String> queryParameters,
    required String operation,
    required String pageKind,
    required String missingUidMessage,
    required String failurePrefix,
    required String parseFailurePrefix,
  }) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      return ApiFailure<UserProfileData>(
        ApiError(type: ApiErrorType.business, message: missingUidMessage),
      );
    }
    final htmlResult = await _htmlClient.getMobilePage(
      path: '/home.php',
      queryParameters: <String, String>{
        'mod': 'space',
        'uid': normalizedUid,
        'do': 'profile',
        'mobile': '2',
        ...queryParameters,
      },
      context: YamiboRequestContext(
        kind: YamiboRequestKind.html,
        operation: operation,
        module: 'profile',
        pageKind: pageKind,
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
              message: '$parseFailurePrefix: $error',
              raw: error,
            ),
          );
        }
      },
      failure: (error) => ApiFailure<UserProfileData>(
        ApiError(
          type: error.type,
          message: '$failurePrefix: ${error.message}',
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

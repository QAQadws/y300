import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/utils/parse_utils.dart';

/// 会话快照，来自 profile 接口可稳定获取的最小字段集。
class SessionInfo {
  SessionInfo({
    required this.uid,
    required this.username,
    required this.formhash,
    required this.isLoggedIn,
  });

  final String uid;
  final String username;
  final String formhash;
  final bool isLoggedIn;

  factory SessionInfo.fromVariables(Map<String, dynamic> variables) {
    final uid = ParseUtils.asString(variables['member_uid']);
    return SessionInfo(
      uid: uid,
      username: ParseUtils.asString(variables['member_username']),
      formhash: ParseUtils.asString(variables['formhash']),
      isLoggedIn: uid.isNotEmpty && uid != '0',
    );
  }
}

class AuthRepository {
  AuthRepository(this._apiClient);

  final ApiClient _apiClient;

  /// 通过 profile 探活当前登录态。
  Future<ApiResult<SessionInfo>> refreshSession() {
    return _apiClient.getParsed<SessionInfo>(
      module: 'profile',
      parser: (response) => SessionInfo.fromVariables(response.variables),
    );
  }

  /// 通过 forumindex 校验 cookie 中 auth 是否已经生效。
  /// Discuz 在未登录时通常返回 `auth: null`。
  Future<ApiResult<bool>> verifyAuthByForumIndex() async {
    final result = await _apiClient.getDiscuz(module: 'forumindex');
    return result.when(
      success: (response) {
        final auth = response.variables['auth'];
        final authText = ParseUtils.asString(auth);
        return ApiSuccess<bool>(authText.isNotEmpty);
      },
      failure: ApiFailure.new,
    );
  }

  /// 通过 Discuz 网页表单登录，并在成功后立即校验会话是否生效。
  Future<ApiResult<SessionInfo>> login({
    required String username,
    required String password,
    String questionId = '0',
    String answer = '',
  }) async {
    final loginResult = await _apiClient.loginWithWebCredentials(
      username: username,
      password: password,
      questionId: questionId,
      answer: answer,
    );

    if (loginResult.isFailure) {
      return ApiFailure(loginResult.errorOrNull!);
    }

    // 登录后优先通过 forumindex 的 auth 字段校验会话是否真正生效。
    final authResult = await verifyAuthByForumIndex();
    final authValid = authResult.when(
      success: (ok) => ok,
      failure: (_) => false,
    );
    if (!authValid) {
      return ApiFailure(
        ApiError(
          type: ApiErrorType.unauthorized,
          message: '登录请求已发送，但 forumindex.auth 仍为空',
        ),
      );
    }

    final sessionResult = await refreshSession();
    return sessionResult.when(
      success: (session) {
        if (session.isLoggedIn) {
          return ApiSuccess(session);
        }

        return ApiFailure(
          ApiError(
            type: ApiErrorType.unauthorized,
            message: '登录请求已发送，但会话未生效',
            raw: {
              'uid': session.uid,
              'username': session.username,
              'formhash': session.formhash,
            },
          ),
        );
      },
      failure: ApiFailure.new,
    );
  }

  Future<void> logout() {
    return _apiClient.clearSession();
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider));
});

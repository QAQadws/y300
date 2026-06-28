import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/utils/parse_utils.dart';
import 'package:y300/features/auth/data/models/auth_session_models.dart';

abstract class SessionVerifier {
  Future<ApiResult<bool>> verifyAuthByForumIndex();

  Future<ApiResult<SessionInfo>> refreshSession();

  Future<ApiResult<SessionInfo>> verifyLoggedIn();
}

class ApiSessionVerifier implements SessionVerifier {
  ApiSessionVerifier(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<ApiResult<bool>> verifyAuthByForumIndex() async {
    final result = await _apiClient.getDiscuz(module: 'forumindex');
    return result.when(
      success: (response) {
        final auth = ParseUtils.asString(response.variables['auth']);
        return ApiSuccess<bool>(auth.isNotEmpty);
      },
      failure: ApiFailure.new,
    );
  }

  @override
  Future<ApiResult<SessionInfo>> refreshSession() {
    return _apiClient.getParsed<SessionInfo>(
      module: 'profile',
      parser: (response) => SessionInfo.fromVariables(response.variables),
    );
  }

  @override
  Future<ApiResult<SessionInfo>> verifyLoggedIn() async {
    final sessionResult = await refreshSession();
    return sessionResult.when(
      success: (session) {
        if (session.isLoggedIn) {
          return ApiSuccess<SessionInfo>(session);
        }

        return ApiFailure<SessionInfo>(
          ApiError(
            type: ApiErrorType.unauthorized,
            message: '登录请求已发送，但会话未生效',
            raw: <String, String>{
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
}


import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/discuz_response.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/auth/data/auth_formhash_provider.dart';
import 'package:y300/features/auth/data/auth_remote_data_source.dart';
import 'package:y300/features/auth/data/auth_session_models.dart';
import 'package:y300/features/auth/data/session_verifier.dart';

export 'package:y300/features/auth/data/auth_session_models.dart';

abstract class AuthRepository {
  Future<ApiResult<SessionInfo>> refreshSession();

  Future<ApiResult<bool>> verifyAuthByForumIndex();

  Future<ApiResult<SessionInfo>> login({
    required String username,
    required String password,
    String questionId = '0',
    String answer = '',
  });

  Future<void> logout();
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(
    this._apiClient, {
    AuthRemoteDataSource? remoteDataSource,
    FormhashProvider? formhashProvider,
    SessionVerifier? sessionVerifier,
  })  : _remoteDataSource = remoteDataSource ?? DiscuzMobileAuthApi(_apiClient),
        _formhashProvider = formhashProvider ?? ApiFormhashProvider(_apiClient),
        _sessionVerifier = sessionVerifier ?? ApiSessionVerifier(_apiClient);

  final ApiClient _apiClient;
  final AuthRemoteDataSource _remoteDataSource;
  final FormhashProvider _formhashProvider;
  final SessionVerifier _sessionVerifier;

  /// 通过 profile 探活当前登录态。
  @override
  Future<ApiResult<SessionInfo>> refreshSession() {
    return _sessionVerifier.refreshSession();
  }

  /// 通过 forumindex 校验 cookie 中 auth 是否已经生效。
  /// Discuz 在未登录时通常返回 `auth: null`。
  @override
  Future<ApiResult<bool>> verifyAuthByForumIndex() {
    return _sessionVerifier.verifyAuthByForumIndex();
  }

  /// 通过 Discuz 移动端 API 登录，并在成功后立即校验会话是否生效。
  @override
  Future<ApiResult<SessionInfo>> login({
    required String username,
    required String password,
    String questionId = '0',
    String answer = '',
  }) async {
    final normalizedUsername = username.trim();
    if (normalizedUsername.isEmpty || password.isEmpty) {
      return const ApiFailure<SessionInfo>(
        ApiError(type: ApiErrorType.business, message: '用户名和密码不能为空'),
      );
    }

    final formhashResult = await _formhashProvider.loadFormhash();
    if (formhashResult case ApiFailure<String>(:final error)) {
      return ApiFailure<SessionInfo>(error);
    }

    final loginResult = await _remoteDataSource.login(
      LoginRequest(
        username: normalizedUsername,
        password: password,
        formhash: (formhashResult as ApiSuccess<String>).data,
        questionId: questionId,
        answer: answer,
      ),
    );

    if (loginResult.isFailure) {
      return ApiFailure(loginResult.errorOrNull!);
    }

    return _sessionVerifier.verifyLoggedIn();
  }

  @override
  Future<void> logout() async {
    final formhashResult = await _formhashProvider.loadFormhash(
      preferProfile: true,
    );
    if (formhashResult case ApiFailure<String>(:final error)) {
      throw StateError(error.message);
    }

    final formhash = (formhashResult as ApiSuccess<String>).data;
    final standard = await _remoteDataSource.logout(formhash: formhash);
    final logoutResult = standard.isSuccess
        ? standard
        : await _remoteDataSource.logout(
            formhash: formhash,
            mode: LogoutMode.mobileHash,
          );
    if (logoutResult case ApiFailure<DiscuzResponse>(:final error)) {
      throw StateError(error.message);
    }

    await _apiClient.clearSession();
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ApiAuthRepository(
    apiClient,
    remoteDataSource: ref.watch(authRemoteDataSourceProvider),
    formhashProvider: ref.watch(formhashProvider),
    sessionVerifier: ref.watch(sessionVerifierProvider),
  );
});

final formhashProvider = Provider<FormhashProvider>((ref) {
  return ApiFormhashProvider(ref.watch(apiClientProvider));
});

final sessionVerifierProvider = Provider<SessionVerifier>((ref) {
  return ApiSessionVerifier(ref.watch(apiClientProvider));
});

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  return DiscuzMobileAuthApi(ref.watch(apiClientProvider));
});

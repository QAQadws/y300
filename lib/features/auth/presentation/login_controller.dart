import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/auth/data/repositories/auth_repository.dart';
import 'package:y300/features/auth/presentation/login_state.dart';

final loginControllerProvider =
    AsyncNotifierProvider.autoDispose<LoginController, LoginPageState>(
      LoginController.new,
    );

/// 登录页状态控制器：负责表单状态与登录提交流程。
class LoginController extends AsyncNotifier<LoginPageState> {
  static const Duration _submitTimeout = Duration(seconds: 18);

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  LoginPageState build() {
    return LoginPageState.initial();
  }

  /// 避免在 AsyncLoading 等状态直接访问 value 导致空值分支不清晰。
  LoginPageState get _current =>
      state.asData?.value ?? LoginPageState.initial();

  void updateUsername(String value) {
    state = AsyncData(_current.copyWith(username: value, clearError: true));
  }

  void updatePassword(String value) {
    state = AsyncData(_current.copyWith(password: value, clearError: true));
  }

  Future<SessionInfo?> submit() async {
    if (_current.isSubmitting) {
      return null;
    }

    final username = _current.username.trim();
    final password = _current.password;

    if (username.isEmpty || password.isEmpty) {
      state = AsyncData(
        _current.copyWith(
          failure: const AuthLoginFailure(
            code: AuthLoginFailureCode.credentialsRequired,
          ),
        ),
      );
      return null;
    }

    state = AsyncData(_current.copyWith(isSubmitting: true, clearError: true));

    final result = await _repository
        .login(username: username, password: password)
        .timeout(
          _submitTimeout,
          onTimeout: () => const ApiFailure(
            ApiError(type: ApiErrorType.timeout, message: 'auth.login.timeout'),
          ),
        );

    return result.when(
      success: (session) {
        state = AsyncData(
          _current.copyWith(isSubmitting: false, clearError: true),
        );
        return session;
      },
      failure: (error) {
        state = AsyncData(
          _current.copyWith(
            isSubmitting: false,
            failure: AuthLoginFailure(
              code: error.type == ApiErrorType.timeout
                  ? AuthLoginFailureCode.timeout
                  : AuthLoginFailureCode.requestFailed,
              detail: error,
            ),
          ),
        );
        return null;
      },
    );
  }
}

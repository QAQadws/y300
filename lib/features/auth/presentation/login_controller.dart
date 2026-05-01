import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/auth/data/auth_repository.dart';
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
  LoginPageState get _current => state.asData?.value ?? LoginPageState.initial();

  void updateUsername(String value) {
    state = AsyncData(
      _current.copyWith(username: value, clearError: true, clearSuccess: true),
    );
  }

  void updatePassword(String value) {
    state = AsyncData(
      _current.copyWith(password: value, clearError: true, clearSuccess: true),
    );
  }

  Future<bool> submit() async {
    if (_current.isSubmitting) {
      return false;
    }

    final username = _current.username.trim();
    final password = _current.password;

    if (username.isEmpty || password.isEmpty) {
      state = AsyncData(
        _current.copyWith(
          errorMessage: '请输入用户名和密码',
          clearSuccess: true,
        ),
      );
      return false;
    }

    state = AsyncData(
      _current.copyWith(
        isSubmitting: true,
        clearError: true,
        clearSuccess: true,
      ),
    );

    final result = await _repository
        .login(username: username, password: password)
        .timeout(
          _submitTimeout,
          onTimeout: () => const ApiFailure(
            ApiError(
              type: ApiErrorType.timeout,
              message: '登录超时，请检查网络后重试',
            ),
          ),
        );

    return result.when(
      success: (session) {
        state = AsyncData(
          _current.copyWith(
            isSubmitting: false,
            successMessage:
                '欢迎回来，${session.username.isNotEmpty ? session.username : username}',
            clearError: true,
          ),
        );
        return true;
      },
      failure: (error) {
        state = AsyncData(
          _current.copyWith(
            isSubmitting: false,
            errorMessage: error.message,
            clearSuccess: true,
          ),
        );
        return false;
      },
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/auth/data/auth_repository.dart';
import 'package:y300/features/auth/presentation/login_state.dart';

final loginControllerProvider =
    AsyncNotifierProvider.autoDispose<LoginController, LoginPageState>(
      LoginController.new,
    );

/// 登录页状态控制器：负责表单状态与登录提交流程。
class LoginController extends AsyncNotifier<LoginPageState> {
  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  LoginPageState build() {
    return LoginPageState.initial();
  }

  LoginPageState get _current => state.value ?? LoginPageState.initial();

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

    final result = await _repository.login(username: username, password: password);

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

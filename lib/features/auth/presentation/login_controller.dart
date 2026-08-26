import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/auth/data/providers/auth_contract_providers.dart';
import 'package:y300/features/auth/presentation/login_state.dart';

final loginControllerProvider =
    AsyncNotifierProvider.autoDispose<LoginController, LoginPageState>(
      LoginController.new,
    );

/// 登录页状态控制器：负责表单状态与登录提交流程。
class LoginController extends AsyncNotifier<LoginPageState> {
  static const Duration _submitTimeout = Duration(seconds: 18);

  int _operationGeneration = 0;

  ForumPasswordLoginCommand get _command =>
      ref.read(forumPasswordLoginCommandProvider);

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

  Future<ForumSessionIdentity?> submit() async {
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

    final operation = ++_operationGeneration;
    final cancellation = ForumRequestCancellation();
    ref.onDispose(cancellation.cancel);
    final result = await _command
        .execute(
          ForumPasswordLoginRequest(
            username: username,
            password: password,
            cancellation: cancellation,
          ),
        )
        .timeout(
          _submitTimeout,
          onTimeout: () {
            cancellation.cancel();
            return const DataCommandOutcomeUnknown<ForumLoginReceipt>(
              DataCommandFailure(
                kind: DataCommandFailureKind.timeout,
                retryPolicy: DataCommandRetryPolicy.explicitOnly,
                code: 'auth_login_timeout',
                diagnosticMessage: 'auth_login_timeout',
              ),
            );
          },
        );

    if (!ref.mounted || operation != _operationGeneration) return null;
    return switch (result) {
      DataCommandApplied<ForumLoginReceipt>(:final receipt) => () {
        state = AsyncData(
          _current.copyWith(isSubmitting: false, clearError: true),
        );
        return receipt.session;
      }(),
      _ => () {
        final failure = result.failureOrNull;
        state = AsyncData(
          _current.copyWith(
            isSubmitting: false,
            failure: AuthLoginFailure(
              code: failure?.kind == DataCommandFailureKind.timeout
                  ? AuthLoginFailureCode.timeout
                  : AuthLoginFailureCode.requestFailed,
              detail: result is DataCommandRejected<ForumLoginReceipt>
                  ? result
                  : failure ?? result,
            ),
          ),
        );
        return null;
      }(),
    };
  }
}

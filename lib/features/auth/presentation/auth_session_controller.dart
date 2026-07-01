import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/auth/data/repositories/auth_repository.dart';

final authSessionControllerProvider =
    AsyncNotifierProvider.autoDispose<
      AuthSessionController,
      AuthSessionViewState
    >(AuthSessionController.new);

class AuthSessionViewState {
  const AuthSessionViewState({
    required this.isLoggedIn,
    required this.uid,
    required this.username,
    required this.isLoggingOut,
    this.errorMessage,
  });

  final bool isLoggedIn;
  final String uid;
  final String username;
  final bool isLoggingOut;
  final String? errorMessage;

  const AuthSessionViewState.signedOut()
    : isLoggedIn = false,
      uid = '',
      username = '',
      isLoggingOut = false,
      errorMessage = null;

  factory AuthSessionViewState.fromSession(SessionInfo session) {
    return AuthSessionViewState(
      isLoggedIn: session.isLoggedIn,
      uid: session.uid,
      username: session.username,
      isLoggingOut: false,
    );
  }

  AuthSessionViewState copyWith({
    bool? isLoggedIn,
    String? uid,
    String? username,
    bool? isLoggingOut,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthSessionViewState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      uid: uid ?? this.uid,
      username: username ?? this.username,
      isLoggingOut: isLoggingOut ?? this.isLoggingOut,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class AuthSessionController extends AsyncNotifier<AuthSessionViewState> {
  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  Future<AuthSessionViewState> build() {
    return _loadSession();
  }

  Future<void> refresh() async {
    state = const AsyncLoading<AuthSessionViewState>();
    state = await AsyncValue.guard(_loadSession);
  }

  void acceptSession(SessionInfo session) {
    state = AsyncData(AuthSessionViewState.fromSession(session));
  }

  Future<bool> logout() async {
    final current =
        state.asData?.value ?? const AuthSessionViewState.signedOut();
    if (current.isLoggingOut) {
      return false;
    }

    state = AsyncData(current.copyWith(isLoggingOut: true, clearError: true));
    try {
      await _repository.logout();
      // API 侧登出成功后，尽力清空 WebView 平台 cookie jar，避免残留的登录态
      // cookie 让下次 WebView 登录直接“自动登入”旧账号。这一步是加固而非成败
      // 关键——决定登录态的 dio 会话已在 repository.logout 里清除，因此即使平台
      // cookie 清理抛错（如平台通道不可用），也不应让整个登出失败。
      await _clearWebViewCookiesBestEffort();
      state = const AsyncData(AuthSessionViewState.signedOut());
      return true;
    } catch (error) {
      state = AsyncData(
        current.copyWith(
          isLoggingOut: false,
          errorMessage: _logoutErrorMessage(error),
        ),
      );
      return false;
    }
  }

  Future<void> _clearWebViewCookiesBestEffort() async {
    try {
      await ref.read(webViewCookieSyncServiceProvider).clearWebViewCookies();
    } catch (_) {
      // 忽略平台 cookie 清理异常，dio 会话已清除即视为登出成功。
    }
  }

  Future<AuthSessionViewState> _loadSession() async {
    final result = await _repository.refreshSession();
    return result.when(
      success: AuthSessionViewState.fromSession,
      failure: (_) => const AuthSessionViewState.signedOut(),
    );
  }

  String _logoutErrorMessage(Object error) {
    if (error is StateError) {
      return error.message;
    }
    return '退出登录失败：$error';
  }
}

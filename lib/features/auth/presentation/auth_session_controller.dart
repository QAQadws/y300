import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/auth/data/providers/auth_contract_providers.dart';

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
    this.logoutFailure,
  });

  final bool isLoggedIn;
  final String uid;
  final String username;
  final bool isLoggingOut;
  final Object? logoutFailure;

  const AuthSessionViewState.signedOut()
    : isLoggedIn = false,
      uid = '',
      username = '',
      isLoggingOut = false,
      logoutFailure = null;

  factory AuthSessionViewState.fromIdentity(ForumSessionIdentity session) {
    return AuthSessionViewState(
      isLoggedIn: true,
      uid: session.userId,
      username: session.username,
      isLoggingOut: false,
    );
  }

  AuthSessionViewState copyWith({
    bool? isLoggedIn,
    String? uid,
    String? username,
    bool? isLoggingOut,
    Object? logoutFailure,
    bool clearError = false,
  }) {
    return AuthSessionViewState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      uid: uid ?? this.uid,
      username: username ?? this.username,
      isLoggingOut: isLoggingOut ?? this.isLoggingOut,
      logoutFailure: clearError ? null : (logoutFailure ?? this.logoutFailure),
    );
  }
}

class AuthSessionController extends AsyncNotifier<AuthSessionViewState> {
  ForumSessionRepository get _sessionRepository =>
      ref.read(forumSessionRepositoryProvider);

  ForumLogoutCommand get _logoutCommand => ref.read(forumLogoutCommandProvider);

  @override
  Future<AuthSessionViewState> build() {
    return _loadSession();
  }

  Future<void> refresh() async {
    final previous = state.asData?.value;
    state = const AsyncLoading<AuthSessionViewState>();
    state = await AsyncValue.guard(() => _loadSession(previous));
  }

  void acceptSession(ForumSessionIdentity session) {
    state = AsyncData(AuthSessionViewState.fromIdentity(session));
  }

  Future<bool> logout() async {
    final current =
        state.asData?.value ?? const AuthSessionViewState.signedOut();
    if (current.isLoggingOut) {
      return false;
    }

    state = AsyncData(current.copyWith(isLoggingOut: true, clearError: true));
    final result = await _logoutCommand.execute();
    if (result case DataCommandApplied<ForumLogoutReceipt>()) {
      // API 侧登出成功后，尽力清空 WebView 平台 cookie jar，避免残留的登录态
      // cookie 让下次 WebView 登录直接“自动登入”旧账号。这一步是加固而非成败
      // 关键——决定登录态的 Cookie/session 已由 package command 清除，因此即使平台
      // cookie 清理抛错（如平台通道不可用），也不应让整个登出失败。
      await _clearWebViewCookiesBestEffort();
      state = const AsyncData(AuthSessionViewState.signedOut());
      return true;
    }
    state = AsyncData(
      current.copyWith(
        isLoggingOut: false,
        logoutFailure: result.failureOrNull ?? result,
      ),
    );
    return false;
  }

  Future<void> _clearWebViewCookiesBestEffort() async {
    try {
      await ref.read(webViewCookieSyncServiceProvider).clearWebViewCookies();
    } catch (_) {
      // 忽略平台 cookie 清理异常，dio 会话已清除即视为登出成功。
    }
  }

  Future<AuthSessionViewState> _loadSession([
    AuthSessionViewState? previous,
  ]) async {
    final result = await _sessionRepository.resolve();
    return switch (result) {
      ForumSessionAuthenticated(:final identity) =>
        AuthSessionViewState.fromIdentity(identity),
      ForumSessionAnonymous() => const AuthSessionViewState.signedOut(),
      ForumSessionInconclusive() when previous?.isLoggedIn == true => previous!,
      ForumSessionInconclusive() => const AuthSessionViewState.signedOut(),
    };
  }
}

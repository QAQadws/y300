import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/auth/data/auth_repository.dart';

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

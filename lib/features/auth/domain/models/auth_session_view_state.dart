import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

class AuthSessionViewState {
  const AuthSessionViewState({
    required this.isLoggedIn,
    required this.uid,
    required this.username,
    required this.isLoggingOut,
    this.logoutFailure,
    this.verificationInconclusive = false,
  });

  final bool isLoggedIn;
  final String uid;
  final String username;
  final bool isLoggingOut;
  final Object? logoutFailure;

  /// Display caches may survive an offline probe without granting login.
  final bool verificationInconclusive;

  const AuthSessionViewState.signedOut({this.verificationInconclusive = false})
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
      verificationInconclusive: verificationInconclusive,
    );
  }
}

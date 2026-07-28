enum AuthLoginFailureCode { credentialsRequired, timeout, requestFailed }

class AuthLoginFailure {
  const AuthLoginFailure({required this.code, this.detail});

  final AuthLoginFailureCode code;
  final Object? detail;
}

class LoginPageState {
  const LoginPageState({
    required this.username,
    required this.password,
    required this.isSubmitting,
    this.failure,
  });

  final String username;
  final String password;
  final bool isSubmitting;
  final AuthLoginFailure? failure;

  factory LoginPageState.initial() {
    return const LoginPageState(
      username: '',
      password: '',
      isSubmitting: false,
      failure: null,
    );
  }

  LoginPageState copyWith({
    String? username,
    String? password,
    bool? isSubmitting,
    AuthLoginFailure? failure,
    bool clearError = false,
  }) {
    return LoginPageState(
      username: username ?? this.username,
      password: password ?? this.password,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      failure: clearError ? null : (failure ?? this.failure),
    );
  }
}

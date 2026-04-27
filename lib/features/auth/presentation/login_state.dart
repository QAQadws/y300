class LoginPageState {
  const LoginPageState({
    required this.username,
    required this.password,
    required this.isSubmitting,
    this.errorMessage,
    this.successMessage,
  });

  final String username;
  final String password;
  final bool isSubmitting;
  final String? errorMessage;
  final String? successMessage;

  factory LoginPageState.initial() {
    return const LoginPageState(
      username: '',
      password: '',
      isSubmitting: false,
      errorMessage: null,
      successMessage: null,
    );
  }

  LoginPageState copyWith({
    String? username,
    String? password,
    bool? isSubmitting,
    String? errorMessage,
    String? successMessage,
    bool clearError = false,
    bool clearSuccess = false,
  }) {
    return LoginPageState(
      username: username ?? this.username,
      password: password ?? this.password,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearSuccess ? null : (successMessage ?? this.successMessage),
    );
  }
}

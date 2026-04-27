import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/auth/data/auth_repository.dart';
import 'package:y300/features/auth/presentation/login_page.dart';

void main() {
  group('LoginPage', () {
    testWidgets('shows success message after successful login', (tester) async {
      final repository = _FakeAuthRepository(
        shouldSucceed: true,
        username: 'tester',
      );

      await tester.pumpWidget(_buildTestApp(repository));

      await tester.enterText(find.byKey(const Key('login-username-field')), 'tester');
      await tester.enterText(find.byKey(const Key('login-password-field')), '123456');
      await tester.tap(find.byKey(const Key('login-submit-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login-success-text')), findsOneWidget);
      expect(find.textContaining('欢迎回来'), findsOneWidget);
    });

    testWidgets('shows error message after failed login', (tester) async {
      final repository = _FakeAuthRepository(
        shouldSucceed: false,
        username: 'tester',
      );

      await tester.pumpWidget(_buildTestApp(repository));

      await tester.enterText(find.byKey(const Key('login-username-field')), 'tester');
      await tester.enterText(find.byKey(const Key('login-password-field')), 'wrong');
      await tester.tap(find.byKey(const Key('login-submit-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login-error-text')), findsOneWidget);
      expect(find.text('账号或密码错误'), findsOneWidget);
    });
  });
}

Widget _buildTestApp(AuthRepository repository) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repository)],
    child: const MaterialApp(home: LoginPage()),
  );
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({required this.shouldSucceed, required this.username});

  final bool shouldSucceed;
  final String username;

  @override
  Future<ApiResult<SessionInfo>> login({
    required String username,
    required String password,
    String questionId = '0',
    String answer = '',
  }) async {
    if (shouldSucceed) {
      return ApiSuccess(
        SessionInfo(
          uid: '100',
          username: this.username,
          formhash: 'fh',
          isLoggedIn: true,
        ),
      );
    }

    return const ApiFailure(
      ApiError(type: ApiErrorType.business, message: '账号或密码错误'),
    );
  }

  @override
  Future<void> logout() async {}

  @override
  Future<ApiResult<SessionInfo>> refreshSession() async {
    return ApiSuccess(
      SessionInfo(
        uid: '100',
        username: username,
        formhash: 'fh',
        isLoggedIn: true,
      ),
    );
  }
}

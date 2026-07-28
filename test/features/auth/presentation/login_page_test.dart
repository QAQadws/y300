import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/auth/data/repositories/auth_repository.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/auth/presentation/login_page.dart';

void main() {
  group('LoginPage', () {
    testWidgets('pops page after successful login', (tester) async {
      final repository = _FakeAuthRepository(
        shouldSucceed: true,
        username: 'tester',
      );

      await tester.pumpWidget(_buildPushFlowTestApp(repository));

      await tester.tap(find.byKey(const Key('open-login-page-button')));
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('login-username-field')),
        'tester',
      );
      await tester.enterText(
        find.byKey(const Key('login-password-field')),
        '123456',
      );
      await tester.tap(find.byKey(const Key('login-submit-button')));
      await tester.pumpAndSettle();

      // 登录成功后应回退到上一页。
      expect(find.byType(LoginPage), findsNothing);
      expect(find.byKey(const Key('login-result-text')), findsOneWidget);
      expect(find.text('result=true'), findsOneWidget);
      expect(find.text('session=tester'), findsOneWidget);
      expect(repository.refreshSessionCallCount, 1);
    });

    testWidgets('shows error message after failed login', (tester) async {
      final repository = _FakeAuthRepository(
        shouldSucceed: false,
        username: 'tester',
      );

      await tester.pumpWidget(_buildTestApp(repository));

      await tester.enterText(
        find.byKey(const Key('login-username-field')),
        'tester',
      );
      await tester.enterText(
        find.byKey(const Key('login-password-field')),
        'wrong',
      );
      await tester.tap(find.byKey(const Key('login-submit-button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login-error-text')), findsOneWidget);
      expect(find.text('账号或密码错误'), findsOneWidget);
    });

    testWidgets('localizes Traditional Chinese chrome', (tester) async {
      final repository = _FakeAuthRepository(
        shouldSucceed: false,
        username: '原始用户名',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [authRepositoryProvider.overrideWithValue(repository)],
          child: const LocalizedTestApp(
            locale: Locale('zh', 'TW'),
            home: LoginPage(),
          ),
        ),
      );

      expect(find.text('登入'), findsWidgets);
      expect(find.text('使用者名稱'), findsOneWidget);
      expect(find.text('密碼'), findsOneWidget);
    });
  });
}

Widget _buildTestApp(AuthRepository repository) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repository)],
    child: const LocalizedTestApp(home: LoginPage()),
  );
}

Widget _buildPushFlowTestApp(AuthRepository repository) {
  return ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(repository)],
    child: const LocalizedTestApp(home: _LoginHostPage()),
  );
}

class _LoginHostPage extends StatefulWidget {
  const _LoginHostPage();

  @override
  State<_LoginHostPage> createState() => _LoginHostPageState();
}

class _LoginHostPageState extends State<_LoginHostPage> {
  bool? _result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              key: const Key('open-login-page-button'),
              onPressed: () async {
                final result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(builder: (_) => const LoginPage()),
                );
                setState(() {
                  _result = result;
                });
              },
              child: const Text('open login'),
            ),
            Text('result=$_result', key: const Key('login-result-text')),
            Consumer(
              builder: (context, ref, _) {
                final session = ref
                    .watch(authSessionControllerProvider)
                    .asData
                    ?.value;
                return Text(
                  'session=${session?.username ?? ''}',
                  key: const Key('login-session-text'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({required this.shouldSucceed, required this.username});

  final bool shouldSucceed;
  final String username;
  bool _isLoggedIn = false;
  int refreshSessionCallCount = 0;

  @override
  Future<ApiResult<SessionInfo>> login({
    required String username,
    required String password,
    String questionId = '0',
    String answer = '',
  }) async {
    if (shouldSucceed) {
      _isLoggedIn = true;
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
    refreshSessionCallCount += 1;
    return ApiSuccess(
      _isLoggedIn
          ? SessionInfo(
              uid: '100',
              username: username,
              formhash: 'fh',
              isLoggedIn: true,
            )
          : SessionInfo(
              uid: '0',
              username: '',
              formhash: '',
              isLoggedIn: false,
            ),
    );
  }

  @override
  Future<ApiResult<bool>> verifyAuthByForumIndex() async {
    return ApiSuccess(_isLoggedIn);
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/webview_cookie_sync_service.dart';
import 'package:y300/features/auth/data/repositories/auth_repository.dart';
import 'package:y300/features/auth/data/services/webview_login_progress.dart';
import 'package:y300/features/auth/data/services/webview_login_session_resolver.dart';

class _FakeWebViewCookieJar implements WebViewCookieJar {
  _FakeWebViewCookieJar(this.cookies);

  Map<String, String> cookies;

  @override
  Future<Map<String, String>> readCookies(Uri uri) async =>
      Map<String, String>.from(cookies);

  @override
  Future<void> clear() async => cookies = <String, String>{};
}

/// 只对 refreshSession 做桩，其它 AuthRepository 成员在本用例中不会被调用。
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._refreshResult);

  final ApiResult<SessionInfo> _refreshResult;
  int refreshCallCount = 0;

  @override
  Future<ApiResult<SessionInfo>> refreshSession() async {
    refreshCallCount += 1;
    return _refreshResult;
  }

  @override
  Future<ApiResult<bool>> verifyAuthByForumIndex() =>
      throw UnimplementedError();

  @override
  Future<ApiResult<SessionInfo>> login({
    required String username,
    required String password,
    String questionId = '0',
    String answer = '',
  }) => throw UnimplementedError();

  @override
  Future<void> logout() => throw UnimplementedError();
}

WebViewLoginSessionResolver _buildResolver({
  required Map<String, String> webViewCookies,
  required ApiResult<SessionInfo> refreshResult,
  required _FakeAuthRepository authRepository,
}) {
  final syncService = WebViewCookieSyncService(
    cookieJar: _FakeWebViewCookieJar(webViewCookies),
    cookieStore: CookieStore(),
  );
  return WebViewLoginSessionResolver(
    cookieSyncService: syncService,
    authRepository: authRepository,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('returns pending and skips API verification when no auth cookie', () async {
    final authRepository = _FakeAuthRepository(
      ApiSuccess<SessionInfo>(
        SessionInfo(uid: '1', username: 'u', formhash: 'h', isLoggedIn: true),
      ),
    );
    final resolver = _buildResolver(
      webViewCookies: const <String, String>{'acw_sc__v2': 'wafpass'},
      refreshResult: const ApiFailure<SessionInfo>(
        ApiError(type: ApiErrorType.unknown, message: 'unused'),
      ),
      authRepository: authRepository,
    );

    final progress = await resolver.evaluate();

    expect(progress, isA<WebViewLoginPending>());
    expect(authRepository.refreshCallCount, 0);
  });

  test('returns succeeded when auth cookie present and profile verifies', () async {
    final session = SessionInfo(
      uid: '42',
      username: 'reader',
      formhash: 'abcd',
      isLoggedIn: true,
    );
    final authRepository = _FakeAuthRepository(ApiSuccess<SessionInfo>(session));
    final resolver = _buildResolver(
      webViewCookies: const <String, String>{
        'acw_sc__v2': 'wafpass',
        'EeqY_2132_auth': 'token',
      },
      refreshResult: ApiSuccess<SessionInfo>(session),
      authRepository: authRepository,
    );

    final progress = await resolver.evaluate();

    expect(progress, isA<WebViewLoginSucceeded>());
    expect((progress as WebViewLoginSucceeded).session.username, 'reader');
    expect(authRepository.refreshCallCount, 1);
  });

  test('returns failed when auth cookie present but profile verification fails', () async {
    final authRepository = _FakeAuthRepository(
      const ApiFailure<SessionInfo>(
        ApiError(type: ApiErrorType.network, message: '网络异常'),
      ),
    );
    final resolver = _buildResolver(
      webViewCookies: const <String, String>{'EeqY_2132_auth': 'token'},
      refreshResult: const ApiFailure<SessionInfo>(
        ApiError(type: ApiErrorType.network, message: '网络异常'),
      ),
      authRepository: authRepository,
    );

    final progress = await resolver.evaluate();

    expect(progress, isA<WebViewLoginFailed>());
    expect((progress as WebViewLoginFailed).message, '网络异常');
  });
}

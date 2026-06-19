import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo/yamibo_session_extractor.dart';
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/features/auth/data/auth_formhash_provider.dart';
import 'package:y300/features/auth/data/auth_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthRepository mobile API flow', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test(
      'login loads formhash, posts mobile login, and verifies session',
      () async {
        final adapter = _DiscuzAuthTestAdapter(
          guestFormhash: 'fh_guest',
          loginSucceeds: true,
          forumIndexAuthAfterLogin: 'token123',
          profileUid: '123',
          profileUsername: 'tester',
        );
        final authRepository = _buildAuthRepository(adapter);

        final result = await authRepository.login(
          username: ' tester ',
          password: 'pass123',
        );

        expect(result.isSuccess, isTrue);
        final session = result.dataOrNull;
        expect(session, isNotNull);
        expect(session!.isLoggedIn, isTrue);
        expect(session.uid, '123');
        expect(session.username, 'tester');
        expect(adapter.lastLoginBody, contains('formhash=fh_guest'));
        expect(adapter.lastLoginBody, contains('loginsubmit=1'));
        expect(adapter.lastLoginBody, contains('username=tester'));
        expect(adapter.lastProfileCookieHeader, contains('auth=token123'));
        expect(adapter.forumIndexGetCount, 1);
        expect(adapter.profileGetCount, 1);
      },
    );

    test('login does not post password when formhash is empty', () async {
      final adapter = _DiscuzAuthTestAdapter(
        guestFormhash: '',
        loginSucceeds: true,
        forumIndexAuthAfterLogin: 'token123',
        profileUid: '123',
        profileUsername: 'tester',
      );
      final authRepository = _buildAuthRepository(adapter);

      final result = await authRepository.login(
        username: 'tester',
        password: 'pass123',
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.message, contains('formhash'));
      expect(adapter.loginPostCount, 0);
    });

    test('login returns business failure from mobile login API', () async {
      final adapter = _DiscuzAuthTestAdapter(
        guestFormhash: 'fh_guest',
        loginSucceeds: false,
        forumIndexAuthAfterLogin: null,
        profileUid: '0',
        profileUsername: '',
      );
      final authRepository = _buildAuthRepository(adapter);

      final result = await authRepository.login(
        username: 'tester',
        password: 'wrong-password',
      );

      expect(result.isFailure, isTrue);
      final error = result.errorOrNull;
      expect(error, isNotNull);
      expect(error!.type, ApiErrorType.business);
      expect(error.message, contains('密码错误'));
    });

    test(
      'mobile login success but profile is not logged in returns unauthorized',
      () async {
        final adapter = _DiscuzAuthTestAdapter(
          guestFormhash: 'fh_guest',
          loginSucceeds: true,
          forumIndexAuthAfterLogin: 'token123',
          profileUid: '0',
          profileUsername: 'tester',
        );
        final authRepository = _buildAuthRepository(adapter);

        final result = await authRepository.login(
          username: 'tester',
          password: 'pass123',
        );

        expect(result.isFailure, isTrue);
        final error = result.errorOrNull;
        expect(error, isNotNull);
        expect(error!.type, ApiErrorType.unauthorized);
        expect(error.message, contains('会话未生效'));
      },
    );

    test(
      'logout calls mobile API and clears persisted cookies after success',
      () async {
        final adapter = _DiscuzAuthTestAdapter(
          guestFormhash: 'fh_guest',
          loginSucceeds: true,
          forumIndexAuthAfterLogin: 'token123',
          profileUid: '123',
          profileUsername: 'tester',
          logoutSucceeds: true,
        );
        final authRepository = _buildAuthRepository(adapter);
        final cookieStore = CookieStore();

        await authRepository.login(username: 'tester', password: 'pass123');

        final beforeLogout = await cookieStore.readCookieHeader(
          Uri.parse('https://bbs.yamibo.com/api/mobile/index.php'),
        );
        expect(beforeLogout, contains('auth=token123'));

        await authRepository.logout();

        expect(adapter.logoutQuery?['action'], 'logout');
        expect(adapter.logoutQuery?['formhash'], 'fh_after_login');
        final afterLogout = await cookieStore.readCookieHeader(
          Uri.parse('https://bbs.yamibo.com/api/mobile/index.php'),
        );
        expect(afterLogout, isNull);
      },
    );

    test('logout clears shared session store after success', () async {
      final adapter = _DiscuzAuthTestAdapter(
        guestFormhash: 'fh_guest',
        loginSucceeds: true,
        forumIndexAuthAfterLogin: 'token123',
        profileUid: '123',
        profileUsername: 'tester',
        logoutSucceeds: true,
      );
      final sessionStore = YamiboSessionStore();
      sessionStore.saveExtracted(
        YamiboSessionSnapshot(
          isLoggedIn: true,
          uid: '123',
          username: 'tester',
          formhash: 'fh_after_login',
          updatedAt: DateTime.now(),
          source: 'api:profile',
        ),
      );
      final authRepository = _buildAuthRepository(
        adapter,
        sessionStore: sessionStore,
      );

      await authRepository.logout();

      expect(sessionStore.readCurrent(), isNull);
    });

    test('logout failure does not clear persisted cookies', () async {
      final adapter = _DiscuzAuthTestAdapter(
        guestFormhash: 'fh_guest',
        loginSucceeds: true,
        forumIndexAuthAfterLogin: 'token123',
        profileUid: '123',
        profileUsername: 'tester',
        logoutSucceeds: false,
      );
      final authRepository = _buildAuthRepository(adapter);
      final cookieStore = CookieStore();

      await authRepository.login(username: 'tester', password: 'pass123');

      await expectLater(authRepository.logout(), throwsA(isA<StateError>()));
      final afterLogout = await cookieStore.readCookieHeader(
        Uri.parse('https://bbs.yamibo.com/api/mobile/index.php'),
      );
      expect(afterLogout, contains('auth=token123'));
    });

    test(
      'formhash provider returns cached session formhash without API call',
      () async {
        final adapter = _DiscuzAuthTestAdapter(
          guestFormhash: 'fh_guest',
          loginSucceeds: true,
          forumIndexAuthAfterLogin: 'token123',
          profileUid: '123',
          profileUsername: 'tester',
        );
        final sessionStore = YamiboSessionStore();
        sessionStore.saveExtracted(
          YamiboSessionSnapshot(
            isLoggedIn: true,
            uid: '123',
            username: 'tester',
            formhash: 'fh_cached',
            updatedAt: DateTime.now(),
            source: 'html:forum.home.html',
          ),
        );
        final provider = ApiFormhashProvider(
          _buildApiClient(adapter, sessionStore: sessionStore),
          sessionStore: sessionStore,
        );

        final result = await provider.loadFormhash();

        expect(result.isSuccess, isTrue);
        expect(result.dataOrNull, 'fh_cached');
        expect(adapter.forumIndexGetCount, 0);
        expect(adapter.profileGetCount, 0);
      },
    );

    test(
      'formhash provider uses gateway-extracted formhash after API business failure',
      () async {
        final adapter = _DiscuzAuthTestAdapter(
          guestFormhash: 'fh_guest',
          loginSucceeds: true,
          forumIndexAuthAfterLogin: 'token123',
          profileUid: '123',
          profileUsername: 'tester',
          forumIndexFormhashMessageFails: true,
        );
        final sessionStore = YamiboSessionStore();
        final provider = ApiFormhashProvider(
          _buildApiClient(adapter, sessionStore: sessionStore),
          sessionStore: sessionStore,
        );

        final result = await provider.loadFormhash();

        expect(result.isSuccess, isTrue);
        expect(result.dataOrNull, 'fh_guest');
        expect(adapter.forumIndexGetCount, 1);
        expect(adapter.profileGetCount, 0);
      },
    );
  });
}

AuthRepository _buildAuthRepository(
  HttpClientAdapter adapter, {
  YamiboSessionStore? sessionStore,
}) {
  final apiClient = _buildApiClient(adapter, sessionStore: sessionStore);
  return ApiAuthRepository(
    apiClient,
    formhashProvider: ApiFormhashProvider(
      apiClient,
      sessionStore: sessionStore,
    ),
    sessionStore: sessionStore,
  );
}

ApiClient _buildApiClient(
  HttpClientAdapter adapter, {
  YamiboSessionStore? sessionStore,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://bbs.yamibo.com/api/mobile/index.php',
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
    ),
  )..httpClientAdapter = adapter;

  return ApiClient(
    cookieStore: CookieStore(),
    logger: Logger(level: Level.off),
    sessionStore: sessionStore,
    sessionExtractor: sessionStore == null
        ? null
        : const YamiboSessionExtractor(),
    dio: dio,
    enableLog: false,
  );
}

class _DiscuzAuthTestAdapter implements HttpClientAdapter {
  _DiscuzAuthTestAdapter({
    required this.guestFormhash,
    required this.loginSucceeds,
    required this.forumIndexAuthAfterLogin,
    required this.profileUid,
    required this.profileUsername,
    this.logoutSucceeds = true,
    this.forumIndexFormhashMessageFails = false,
  });

  final String guestFormhash;
  final bool loginSucceeds;
  final String? forumIndexAuthAfterLogin;
  final String profileUid;
  final String profileUsername;
  final bool logoutSucceeds;
  final bool forumIndexFormhashMessageFails;

  String lastLoginBody = '';
  String? lastProfileCookieHeader;
  Map<String, String>? logoutQuery;
  var loginPostCount = 0;
  var forumIndexGetCount = 0;
  var profileGetCount = 0;
  var _loggedIn = false;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final requestBody = await _readRequestBody(requestStream);
    final uri = options.uri;

    if (options.method == 'GET' &&
        uri.path.endsWith('/api/mobile/index.php') &&
        uri.queryParameters['module'] == 'forumindex') {
      forumIndexGetCount++;
      final auth = _loggedIn ? forumIndexAuthAfterLogin : null;
      return _jsonResponse(
        <String, dynamic>{
          'Version': '4',
          'Charset': 'utf-8',
          'Variables': <String, dynamic>{
            'auth': auth,
            'member_uid': auth == null ? '0' : '123',
            'formhash': _loggedIn ? 'fh_after_login' : guestFormhash,
          },
          if (forumIndexFormhashMessageFails && !_loggedIn)
            'Message': <String, dynamic>{
              'messageval': 'guest_prompt',
              'messagestr': '需要登录',
            },
        },
        headers: const <String, List<String>>{
          'set-cookie': <String>['guest=1; Path=/; HttpOnly'],
        },
      );
    }

    if (options.method == 'POST' &&
        uri.path.endsWith('/api/mobile/index.php') &&
        uri.queryParameters['module'] == 'login' &&
        uri.queryParameters['action'] == 'login') {
      loginPostCount++;
      lastLoginBody = requestBody;
      _loggedIn = loginSucceeds;
      return _jsonResponse(
        <String, dynamic>{
          'Version': '4',
          'Charset': 'utf-8',
          'Variables': <String, dynamic>{
            'auth': loginSucceeds ? 'token123' : null,
            'member_uid': loginSucceeds ? '123' : '0',
          },
          'Message': <String, dynamic>{
            'messageval': loginSucceeds ? 'login_succeed' : 'login_failed',
            'messagestr': loginSucceeds ? '登录成功' : '密码错误',
          },
        },
        headers: <String, List<String>>{
          if (loginSucceeds)
            'set-cookie': <String>['auth=token123; Path=/; HttpOnly'],
        },
      );
    }

    if (options.method == 'GET' &&
        uri.path.endsWith('/api/mobile/index.php') &&
        uri.queryParameters['module'] == 'profile') {
      profileGetCount++;
      lastProfileCookieHeader = options.headers['cookie']?.toString();
      return _jsonResponse(<String, dynamic>{
        'Version': '4',
        'Charset': 'utf-8',
        'Variables': <String, dynamic>{
          'member_uid': _loggedIn ? profileUid : '0',
          'member_username': _loggedIn ? profileUsername : '',
          'formhash': _loggedIn ? 'fh_after_login' : guestFormhash,
        },
      });
    }

    if (options.method == 'GET' &&
        uri.path.endsWith('/api/mobile/index.php') &&
        uri.queryParameters['module'] == 'login' &&
        (uri.queryParameters['action'] == 'logout' ||
            uri.queryParameters['mlogout'] == '1')) {
      logoutQuery = Map<String, String>.from(uri.queryParameters);
      if (logoutSucceeds) {
        _loggedIn = false;
      }
      return _jsonResponse(<String, dynamic>{
        'Version': '4',
        'Charset': 'utf-8',
        'Variables': <String, dynamic>{},
        'Message': <String, dynamic>{
          'messageval': logoutSucceeds ? 'logout_succeed' : 'logout_failed',
          'messagestr': logoutSucceeds ? '退出成功' : '退出失败',
        },
      });
    }

    return ResponseBody.fromString(
      'Not Found: ${options.method} ${options.uri} body=$requestBody',
      404,
      headers: <String, List<String>>{},
    );
  }

  ResponseBody _jsonResponse(
    Map<String, dynamic> body, {
    Map<String, List<String>> headers = const <String, List<String>>{},
  }) {
    return ResponseBody.fromString(jsonEncode(body), 200, headers: headers);
  }

  Future<String> _readRequestBody(Stream<Uint8List>? requestStream) async {
    if (requestStream == null) {
      return '';
    }

    final chunks = await requestStream.toList();
    final bytes = <int>[];
    for (final chunk in chunks) {
      bytes.addAll(chunk);
    }

    if (bytes.isEmpty) {
      return '';
    }

    return utf8.decode(bytes, allowMalformed: true);
  }
}

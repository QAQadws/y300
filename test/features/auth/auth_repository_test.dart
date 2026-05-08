import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/features/auth/data/auth_repository.dart';

void main() {
  group('AuthRepository web login flow', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('login success: should persist cookie and return logged-in session', () async {
      final adapter = _DiscuzTestAdapter(
        loginSucceeds: true,
        forumIndexAuth: 'token123',
        profileUid: '123',
        profileUsername: 'tester',
      );
      final authRepository = _buildAuthRepository(adapter);

      final result = await authRepository.login(
        username: 'tester',
        password: 'pass123',
      );

      expect(result.isSuccess, isTrue);
      final session = result.dataOrNull;
      expect(session, isNotNull);
      expect(session!.isLoggedIn, isTrue);
      expect(session.uid, '123');
      expect(session.username, 'tester');

      expect(adapter.lastProfileCookieHeader, contains('auth=token123'));
    });

    test('login failed on web form: should return business error', () async {
      final adapter = _DiscuzTestAdapter(
        loginSucceeds: false,
        forumIndexAuth: null,
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

    test('web login success but forumindex auth is null: should be unauthorized', () async {
      final adapter = _DiscuzTestAdapter(
        loginSucceeds: true,
        forumIndexAuth: null,
        profileUid: '123',
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
      expect(error.message, contains('forumindex.auth'));
    });

    test('logout should clear persisted cookies', () async {
      final adapter = _DiscuzTestAdapter(
        loginSucceeds: true,
        forumIndexAuth: 'token123',
        profileUid: '123',
        profileUsername: 'tester',
      );
      final authRepository = _buildAuthRepository(adapter);
      final apiClient = _buildApiClient(adapter);
      final cookieStore = CookieStore();

      await authRepository.login(username: 'tester', password: 'pass123');

      final beforeLogout = await cookieStore.readCookieHeader(
        Uri.parse('https://bbs.yamibo.com/api/mobile/index.php'),
      );
      expect(beforeLogout, contains('auth=token123'));

      await authRepository.logout();

      final afterLogout = await cookieStore.readCookieHeader(
        Uri.parse('https://bbs.yamibo.com/api/mobile/index.php'),
      );
      expect(afterLogout, isNull);

      expect(apiClient, isNotNull);
    });
  });
}

AuthRepository _buildAuthRepository(HttpClientAdapter adapter) {
  final apiClient = _buildApiClient(adapter);
  return ApiAuthRepository(apiClient);
}

ApiClient _buildApiClient(HttpClientAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://bbs.yamibo.com/api/mobile/index.php',
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
    ),
  );
  dio.httpClientAdapter = adapter;

  return ApiClient(
    cookieStore: CookieStore(),
    logger: Logger(level: Level.off),
    dio: dio,
    enableLog: false,
  );
}

class _DiscuzTestAdapter implements HttpClientAdapter {
  _DiscuzTestAdapter({
    required this.loginSucceeds,
    required this.forumIndexAuth,
    required this.profileUid,
    required this.profileUsername,
  });

  final bool loginSucceeds;
  final String? forumIndexAuth;
  final String profileUid;
  final String profileUsername;

  String? lastProfileCookieHeader;

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
        uri.path.endsWith('/member.php') &&
        uri.queryParameters['mod'] == 'logging' &&
        uri.queryParameters['action'] == 'login') {
      return ResponseBody.fromString(
        _loginPageHtml(),
        200,
        headers: <String, List<String>>{
          'set-cookie': <String>['prelogin=1; Path=/; HttpOnly'],
        },
      );
    }

    if (options.method == 'POST' &&
        uri.path.endsWith('/member.php') &&
        uri.queryParameters['mod'] == 'logging' &&
        uri.queryParameters['action'] == 'login' &&
        uri.queryParameters['loginsubmit'] == 'yes') {
      final body = loginSucceeds
          ? '<root><![CDATA[succeedhandle_login]]></root>'
          : '<root><![CDATA[密码错误]]></root>';

      return ResponseBody.fromString(
        body,
        200,
        headers: <String, List<String>>{
          if (loginSucceeds) 'set-cookie': <String>['auth=token123; Path=/; HttpOnly'],
        },
      );
    }

    if (options.method == 'GET' &&
        uri.path.endsWith('/api/mobile/index.php') &&
        uri.queryParameters['module'] == 'forumindex') {
      final forumIndexResponse = <String, dynamic>{
        'Version': '4',
        'Charset': 'utf-8',
        'Variables': <String, dynamic>{
          'auth': forumIndexAuth,
          'member_uid': forumIndexAuth == null ? '0' : '123',
        },
      };

      return ResponseBody.fromString(
        jsonEncode(forumIndexResponse),
        200,
        headers: <String, List<String>>{},
      );
    }

    if (options.method == 'GET' &&
        uri.path.endsWith('/api/mobile/index.php') &&
        uri.queryParameters['module'] == 'profile') {
      lastProfileCookieHeader = options.headers['cookie']?.toString();

      final profileResponse = <String, dynamic>{
        'Version': '4',
        'Charset': 'utf-8',
        'Variables': <String, dynamic>{
          'member_uid': profileUid,
          'member_username': profileUsername,
          'formhash': 'fh_after_login',
        },
      };

      return ResponseBody.fromString(
        jsonEncode(profileResponse),
        200,
        headers: <String, List<String>>{},
      );
    }

    return ResponseBody.fromString(
      'Not Found: ${options.method} ${options.uri} body=$requestBody',
      404,
      headers: <String, List<String>>{},
    );
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

  String _loginPageHtml() {
    return '''
<html>
  <body>
    <form action="member.php?mod=logging&action=login&loginsubmit=yes&loginhash=abc123&mobile=2" method="post">
      <input type="hidden" name="formhash" value="fh_login" />
    </form>
  </body>
</html>
''';
  }
}

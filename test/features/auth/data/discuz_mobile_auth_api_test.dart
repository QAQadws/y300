import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/features/auth/data/auth_remote_data_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DiscuzMobileAuthApi', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('posts mobile login form and treats success message as success', () async {
      final adapter = _AuthApiTestAdapter(
        responseJson: <String, dynamic>{
          'Version': '4',
          'Charset': 'UTF-8',
          'Variables': <String, dynamic>{
            'auth': 'token123',
            'member_uid': '123',
          },
          'Message': <String, dynamic>{
            'messageval': 'login_succeed',
            'messagestr': '登录成功',
          },
        },
      );
      final api = _buildApi(adapter);

      final result = await api.login(
        const LoginRequest(
          username: 'tester',
          password: 'pass123',
          formhash: 'fh_guest',
        ),
      );

      expect(result.isSuccess, isTrue);
      expect(adapter.lastUri?.queryParameters['module'], 'login');
      expect(adapter.lastUri?.queryParameters['version'], '4');
      expect(adapter.lastUri?.queryParameters['action'], 'login');
      expect(adapter.lastBody, contains('formhash=fh_guest'));
      expect(adapter.lastBody, contains('loginsubmit=1'));
      expect(adapter.lastBody, contains('username=tester'));
      expect(adapter.lastBody, contains('password=pass123'));
      expect(adapter.lastBody, contains('loginfield=auto'));
      expect(adapter.lastBody, contains('cookietime=1'));
    });

    test('returns business failure when login formhash is empty', () async {
      final adapter = _AuthApiTestAdapter(responseJson: <String, dynamic>{});
      final api = _buildApi(adapter);

      final result = await api.login(
        const LoginRequest(
          username: 'tester',
          password: 'pass123',
          formhash: ' ',
        ),
      );

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.type, ApiErrorType.business);
      expect(adapter.called, isFalse);
    });

    test('calls standard logout endpoint and parses Message success', () async {
      final adapter = _AuthApiTestAdapter(
        responseJson: <String, dynamic>{
          'Version': '4',
          'Charset': 'UTF-8',
          'Variables': <String, dynamic>{},
          'Message': <String, dynamic>{
            'messageval': 'logout_succeed',
            'messagestr': '退出成功',
          },
        },
      );
      final api = _buildApi(adapter);

      final result = await api.logout(formhash: 'fh_after_login');

      expect(result.isSuccess, isTrue);
      expect(adapter.lastUri?.queryParameters['module'], 'login');
      expect(adapter.lastUri?.queryParameters['action'], 'logout');
      expect(adapter.lastUri?.queryParameters['formhash'], 'fh_after_login');
    });

    test('returns business failure for failed logout message', () async {
      final adapter = _AuthApiTestAdapter(
        responseJson: <String, dynamic>{
          'Version': '4',
          'Charset': 'UTF-8',
          'Variables': <String, dynamic>{},
          'Message': <String, dynamic>{
            'messageval': 'logout_failed',
            'messagestr': '退出失败',
          },
        },
      );
      final api = _buildApi(adapter);

      final result = await api.logout(formhash: 'fh_after_login');

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.type, ApiErrorType.business);
      expect(result.errorOrNull?.message, '退出失败');
    });

    test('calls v4 mobile hash logout endpoint', () async {
      final adapter = _AuthApiTestAdapter(
        responseJson: <String, dynamic>{
          'Version': '4',
          'Charset': 'UTF-8',
          'Variables': <String, dynamic>{},
        },
      );
      final api = _buildApi(adapter);

      final result = await api.logout(
        formhash: 'fh_after_login',
        mode: LogoutMode.mobileHash,
      );

      expect(result.isSuccess, isTrue);
      expect(adapter.lastUri?.queryParameters['module'], 'login');
      expect(adapter.lastUri?.queryParameters['mlogout'], '1');
      expect(adapter.lastUri?.queryParameters['hash'], 'fh_after_login');
    });
  });
}

DiscuzMobileAuthApi _buildApi(_AuthApiTestAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://bbs.yamibo.com/api/mobile/index.php',
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
    ),
  )..httpClientAdapter = adapter;

  return DiscuzMobileAuthApi(
    ApiClient(
      cookieStore: CookieStore(),
      logger: Logger(level: Level.off),
      dio: dio,
      enableLog: false,
    ),
  );
}

class _AuthApiTestAdapter implements HttpClientAdapter {
  _AuthApiTestAdapter({required this.responseJson});

  final Map<String, dynamic> responseJson;
  bool called = false;
  Uri? lastUri;
  String lastBody = '';

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    called = true;
    lastUri = options.uri;
    final chunks = await requestStream?.toList() ?? const <Uint8List>[];
    lastBody = utf8.decode(
      chunks.expand((chunk) => chunk).toList(growable: false),
      allowMalformed: true,
    );

    return ResponseBody.fromString(
      jsonEncode(responseJson),
      200,
      headers: const <String, List<String>>{},
    );
  }
}

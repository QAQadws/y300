import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/cookie_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiClient.postDiscuzForm', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('posts form data with version and persists cookies', () async {
      final adapter = _PostFormTestAdapter();
      final client = _buildClient(adapter);

      final result = await client.postDiscuzForm(
        module: 'login',
        queryParameters: const <String, String>{'action': 'login'},
        data: const <String, String>{'formhash': 'abc', 'loginsubmit': '1'},
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.variables['formhash'], 'after');
      expect(adapter.lastUri?.queryParameters['module'], 'login');
      expect(adapter.lastUri?.queryParameters['version'], '4');
      expect(adapter.lastUri?.queryParameters['action'], 'login');
      expect(adapter.lastBody, contains('formhash=abc'));
      expect(adapter.lastBody, contains('loginsubmit=1'));
      expect(
        adapter.lastHeaders['content-type']?.toString(),
        contains('application/x-www-form-urlencoded'),
      );

      final cookie = await CookieStore().readCookieHeader(adapter.lastUri!);
      expect(cookie, contains('auth=token123'));
    });
  });
}

ApiClient _buildClient(HttpClientAdapter adapter) {
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
    dio: dio,
    enableLog: false,
  );
}

class _PostFormTestAdapter implements HttpClientAdapter {
  Uri? lastUri;
  String lastBody = '';
  Map<String, dynamic> lastHeaders = const <String, dynamic>{};

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastUri = options.uri;
    lastHeaders = options.headers;
    final chunks = await requestStream?.toList() ?? const <Uint8List>[];
    lastBody = utf8.decode(
      chunks.expand((chunk) => chunk).toList(growable: false),
      allowMalformed: true,
    );

    return ResponseBody.fromString(
      jsonEncode(<String, dynamic>{
        'Version': '4',
        'Charset': 'UTF-8',
        'Variables': <String, dynamic>{'formhash': 'after'},
      }),
      200,
      headers: const <String, List<String>>{
        'set-cookie': <String>['auth=token123; Path=/; HttpOnly'],
      },
    );
  }
}

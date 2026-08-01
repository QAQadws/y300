import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo/yamibo_api_client.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YamiboApiClient', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('getDiscuz injects default version', () async {
      final adapter = _ApiClientTestAdapter();
      final client = _buildClient(adapter);

      final result = await client.getDiscuz(module: 'forumindex');

      expect(result.isSuccess, isTrue);
      expect(adapter.lastResponseType, ResponseType.json);
      expect(adapter.lastUri?.queryParameters['module'], 'forumindex');
      expect(adapter.lastUri?.queryParameters['version'], '4');
    });

    test('getDiscuz keeps caller supplied version', () async {
      final adapter = _ApiClientTestAdapter();
      final client = _buildClient(adapter);

      final result = await client.getDiscuz(
        module: 'viewthread',
        queryParameters: const <String, dynamic>{'version': 1, 'tid': '123'},
      );

      expect(result.isSuccess, isTrue);
      expect(adapter.lastUri?.queryParameters['module'], 'viewthread');
      expect(adapter.lastUri?.queryParameters['version'], '1');
      expect(adapter.lastUri?.queryParameters['tid'], '123');
    });

    test('maps Message node to business error when requested', () async {
      final adapter = _ApiClientTestAdapter(
        responseBody: <String, dynamic>{
          'Version': '4',
          'Charset': 'utf-8',
          'Variables': <String, dynamic>{},
          'Message': <String, dynamic>{
            'messageval': 'bad',
            'messagestr': '业务失败',
          },
        },
      );
      final client = _buildClient(adapter);

      final result = await client.getDiscuz(module: 'profile');

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.type.name, 'business');
      expect(result.errorOrNull?.message, '业务失败');
    });

    test('getDiscuz parses BOM-prefixed JSON response', () async {
      final adapter = _ApiClientTestAdapter(
        responseText:
            '\uFEFF{"Version":"4","Charset":"utf-8","Variables":{"fid":"33"}}',
        contentType: 'text/plain',
      );
      final client = _buildClient(adapter);

      final result = await client.getDiscuz(
        module: 'forumdisplay',
        queryParameters: const <String, dynamic>{'fid': '33', 'page': 1},
      );

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.variables['fid'], '33');
    });

    test('getDiscuz reports clear parse error for HTML response', () async {
      final adapter = _ApiClientTestAdapter(
        responseText: '<!doctype html><html><body>login required</body></html>',
        contentType: 'text/html; charset=utf-8',
      );
      final client = _buildClient(adapter);

      final result = await client.getDiscuz(module: 'profile');

      expect(result.isFailure, isTrue);
      expect(result.errorOrNull?.type, ApiErrorType.parse);
      expect(result.errorOrNull?.message, contains('响应不是JSON文本'));
      expect(result.errorOrNull?.message, contains('<!doctype html>'));
    });

    test('postDiscuzForm sends urlencoded form body', () async {
      final adapter = _ApiClientTestAdapter();
      final client = _buildClient(adapter);

      final result = await client.postDiscuzForm(
        module: 'login',
        queryParameters: const <String, dynamic>{'action': 'login'},
        data: const <String, String>{'formhash': 'fh', 'loginsubmit': '1'},
      );

      expect(result.isSuccess, isTrue);
      expect(adapter.lastMethod, 'POST');
      expect(adapter.lastResponseType, ResponseType.json);
      expect(adapter.lastUri?.queryParameters['module'], 'login');
      expect(adapter.lastUri?.queryParameters['version'], '4');
      expect(adapter.lastUri?.queryParameters['action'], 'login');
      expect(adapter.lastBody, contains('formhash=fh'));
      expect(adapter.lastBody, contains('loginsubmit=1'));
      expect(
        adapter.lastHeaders['content-type']?.toString(),
        contains('application/x-www-form-urlencoded'),
      );
    });
  });
}

YamiboApiClient _buildClient(_ApiClientTestAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://bbs.yamibo.com/api/mobile/index.php',
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    ),
  )..httpClientAdapter = adapter;
  return YamiboApiClient(
    gateway: YamiboHttpGateway(
      cookieStore: CookieStore(),
      logger: Logger(level: Level.off),
      dio: dio,
      enableLog: false,
    ),
  );
}

class _ApiClientTestAdapter implements HttpClientAdapter {
  _ApiClientTestAdapter({
    Map<String, dynamic>? responseBody,
    String? responseText,
    this.contentType = 'application/json',
  }) : responseText =
           responseText ??
           jsonEncode(
             responseBody ??
                 <String, dynamic>{
                   'Version': '4',
                   'Charset': 'utf-8',
                   'Variables': <String, dynamic>{'formhash': 'fh_after'},
                 },
           );

  final String responseText;
  final String contentType;
  Uri? lastUri;
  String? lastMethod;
  String lastBody = '';
  ResponseType? lastResponseType;
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
    lastMethod = options.method;
    lastResponseType = options.responseType;
    lastHeaders = options.headers;
    final chunks = await requestStream?.toList() ?? const <Uint8List>[];
    lastBody = utf8.decode(
      chunks.expand((chunk) => chunk).toList(growable: false),
      allowMalformed: true,
    );
    return ResponseBody.fromString(
      responseText,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[contentType],
      },
    );
  }
}

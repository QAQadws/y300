import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo/yamibo_api_client.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/features/profile/data/my_message_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'YamiboMyMessageRepository loads notifications and private messages',
    () async {
      final adapter = _MyMessageApiTestAdapter();
      final repository = YamiboMyMessageRepository(
        apiClient: _buildClient(adapter),
      );

      final result = await repository.getMessageCenter();

      expect(result.isSuccess, isTrue);
      expect(adapter.modules, ['mynotelist', 'mypm']);
      expect(result.dataOrNull?.notifications.items, hasLength(7));
      expect(result.dataOrNull?.privateMessages.items, hasLength(1));
    },
  );
}

YamiboApiClient _buildClient(_MyMessageApiTestAdapter adapter) {
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

class _MyMessageApiTestAdapter implements HttpClientAdapter {
  final modules = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final module = options.uri.queryParameters['module'] ?? '';
    modules.add(module);
    final path = switch (module) {
      'mynotelist' => 'docs/html/我的资料/我的提醒.json',
      'mypm' => 'docs/html/我的资料/我的消息.json',
      _ => null,
    };
    final body = path == null
        ? jsonEncode(<String, dynamic>{
            'Version': '4',
            'Charset': 'utf-8',
            'Variables': <String, dynamic>{'list': <dynamic>[]},
          })
        : File(path).readAsStringSync();
    return ResponseBody.fromString(
      body,
      200,
      headers: const <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }
}

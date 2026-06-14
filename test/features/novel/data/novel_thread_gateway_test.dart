import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/features/novel/data/novel_thread_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiNovelThreadGateway', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('requests viewthread with version=1 and parses thread detail', () async {
      final adapter = _NovelThreadGatewayAdapter(
        responseJson: <String, dynamic>{
          'Version': '1',
          'Charset': 'UTF-8',
          'Variables': <String, dynamic>{
            'fid': '49',
            'ppp': '20',
            'thread': <String, dynamic>{
              'tid': '200',
              'fid': '49',
              'subject': '测试小说标题',
              'author': '楼主A',
              'replies': '2',
              'views': '10',
            },
            'postlist': <Map<String, dynamic>>[
              <String, dynamic>{
                'pid': '5001',
                'author': '楼主A',
                'authorid': '1',
                'message': '<p>第1章</p>',
                'number': '1',
                'first': '1',
                'dateline': '2026-05-03',
              },
            ],
          },
        },
      );
      final gateway = _buildGateway(adapter);

      final result = await gateway.getThreadDetail(tid: '200', page: 3);

      expect(adapter.lastUri?.queryParameters['module'], 'viewthread');
      expect(adapter.lastUri?.queryParameters['tid'], '200');
      expect(adapter.lastUri?.queryParameters['page'], '3');
      expect(adapter.lastUri?.queryParameters['version'], '1');
      expect(result.tid, '200');
      expect(result.currentPage, 3);
      expect(result.posts, hasLength(1));
      expect(result.posts.single.pid, '5001');
    });

    test('throws state error when api result is failure', () async {
      final adapter = _NovelThreadGatewayAdapter(
        responseJson: <String, dynamic>{
          'Version': '1',
          'Charset': 'UTF-8',
          'Variables': <String, dynamic>{},
          'Message': <String, dynamic>{
            'messageval': 'viewthread_forbidden',
            'messagestr': '读取失败',
          },
        },
      );
      final gateway = _buildGateway(adapter);

      expect(
        () => gateway.getThreadDetail(tid: '200', page: 1),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            '读取失败',
          ),
        ),
      );
    });
  });
}

ApiNovelThreadGateway _buildGateway(_NovelThreadGatewayAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://bbs.yamibo.com/api/mobile/index.php',
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 3),
    ),
  )..httpClientAdapter = adapter;

  return ApiNovelThreadGateway(
    ApiClient(
      cookieStore: CookieStore(),
      logger: Logger(level: Level.off),
      dio: dio,
      enableLog: false,
    ),
  );
}

class _NovelThreadGatewayAdapter implements HttpClientAdapter {
  _NovelThreadGatewayAdapter({required this.responseJson});

  final Map<String, dynamic> responseJson;
  Uri? lastUri;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastUri = options.uri;
    return ResponseBody.fromString(
      jsonEncode(responseJson),
      200,
      headers: const <String, List<String>>{},
    );
  }
}

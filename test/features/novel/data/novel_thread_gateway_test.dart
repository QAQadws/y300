import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/features/novel/data/services/novel_thread_gateway.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

import '../test_support/novel_phase0_api_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiNovelThreadGateway', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test(
      'requests viewthread with version=1 and parses thread detail',
      () async {
        final adapter = _NovelThreadGatewayAdapter(
          responseJson: <String, dynamic>{
            'Version': '1',
            'Charset': 'UTF-8',
            'Variables': <String, dynamic>{
              'fid': '49',
              'ppp': '200',
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

        final result = await gateway.loadAuthorPostsPage(
          tid: '200',
          authorId: '1',
          page: 3,
        );

        expect(adapter.lastUri?.queryParameters['module'], 'viewthread');
        expect(adapter.lastUri?.queryParameters['tid'], '200');
        expect(adapter.lastUri?.queryParameters['page'], '3');
        expect(adapter.lastUri?.queryParameters['version'], '1');
        expect(adapter.lastUri?.queryParameters['ppp'], '200');
        expect(adapter.lastUri?.queryParameters['authorid'], '1');
        expect(result.tid, '200');
        expect(result.currentPage, 3);
        expect(result.perPage, 200);
        expect(result.posts, hasLength(1));
        expect(result.posts.single.pid, '5001');
      },
    );

    test(
      'shared API client can express the target author-page query contract',
      () async {
        final fixture = await NovelPhase0ApiFixture.load(
          novelPhase0AuthorPageFixturePaths[1],
        );
        final adapter = _NovelThreadGatewayAdapter(responseJson: fixture.root);
        final client = _buildApiClient(adapter);

        final result = await client.getParsed<ThreadDetailData>(
          module: 'viewthread',
          queryParameters: <String, dynamic>{
            'tid': '521519',
            'page': 2,
            'version': 1,
            'ppp': 200,
            'authorid': '406769',
          },
          parser: (response) =>
              ThreadDetailData.fromVariables(response.variables, page: 2),
        );

        expect(result.isSuccess, isTrue);
        expect(adapter.lastUri?.queryParameters, <String, String>{
          'module': 'viewthread',
          'tid': '521519',
          'page': '2',
          'version': '1',
          'ppp': '200',
          'authorid': '406769',
        });
        expect(result.dataOrNull?.currentPage, 2);
        expect(result.dataOrNull?.perPage, 200);
        expect(
          result.dataOrNull?.posts.map((post) => post.authorId),
          everyElement('406769'),
        );
      },
    );

    test('production gateway sends the exact author-page contract', () async {
      final fixture = await NovelPhase0ApiFixture.load(
        novelPhase0AuthorPageFixturePaths[1],
      );
      final adapter = _NovelThreadGatewayAdapter(responseJson: fixture.root);
      final gateway = _buildGateway(adapter);

      final result = await gateway.loadAuthorPostsPage(
        tid: '521519',
        authorId: '406769',
        page: 2,
      );

      expect(adapter.lastUri?.queryParameters, <String, String>{
        'module': 'viewthread',
        'tid': '521519',
        'page': '2',
        'version': '1',
        'ppp': '200',
        'authorid': '406769',
      });
      expect(result.currentPage, 2);
      expect(result.posts.map((post) => post.authorId), everyElement('406769'));
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
        () => gateway.loadAuthorPostsPage(tid: '200', authorId: '1', page: 1),
        throwsA(
          isA<StateError>().having((error) => error.message, 'message', '读取失败'),
        ),
      );
    });
  });
}

ApiNovelThreadGateway _buildGateway(_NovelThreadGatewayAdapter adapter) {
  return ApiNovelThreadGateway(_buildApiClient(adapter));
}

ApiClient _buildApiClient(_NovelThreadGatewayAdapter adapter) {
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

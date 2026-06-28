import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo/yamibo_html_client.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/features/profile/data/models/profile_blog_models.dart';
import 'package:y300/features/profile/data/repositories/profile_blog_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('YamiboProfileBlogRepository requests blog list mobile HTML', () async {
    final adapter = _ProfileBlogHtmlTestAdapter(
      responsePath: 'docs/html/我的日志/随便看看-推荐阅读的日志.html',
    );
    final repository = _buildRepository(adapter);

    final result = await repository.getBlogList(
      view: ProfileBlogView.all,
      order: ProfileBlogOrder.hot,
      page: 2,
    );

    expect(result.isSuccess, isTrue);
    expect(result.dataOrNull?.activeOrder, ProfileBlogOrder.hot);
    final requested = adapter.requestedUris.single;
    expect(requested.path, '/home.php');
    expect(requested.queryParameters['mod'], 'space');
    expect(requested.queryParameters['do'], 'blog');
    expect(requested.queryParameters['view'], 'all');
    expect(requested.queryParameters['order'], 'hot');
    expect(requested.queryParameters['page'], '2');
    expect(requested.queryParameters['mobile'], '2');
  });

  test(
    'YamiboProfileBlogRepository omits order for latest public blogs',
    () async {
      final adapter = _ProfileBlogHtmlTestAdapter(
        responsePath: 'docs/html/我的日志/随便看看-最新发表的日志.html',
      );
      final repository = _buildRepository(adapter);

      final result = await repository.getBlogList(
        view: ProfileBlogView.all,
        order: ProfileBlogOrder.latest,
      );

      expect(result.isSuccess, isTrue);
      final requested = adapter.requestedUris.single;
      expect(requested.queryParameters['view'], 'all');
      expect(requested.queryParameters.containsKey('order'), isFalse);
      expect(requested.queryParameters['mobile'], '2');
    },
  );

  test('YamiboProfileBlogRepository requests blog detail mobile HTML', () async {
    final adapter = _ProfileBlogHtmlTestAdapter(
      responsePath: 'docs/html/我的日志/一个日志.html',
    );
    final repository = _buildRepository(adapter);

    final result = await repository.getBlogDetail(
      url:
          'https://bbs.yamibo.com/home.php?mod=space&uid=257582&do=blog&id=117548',
    );

    expect(result.isSuccess, isTrue);
    expect(result.dataOrNull?.title, '我们小区的公共交通极其不便利');
    final requested = adapter.requestedUris.single;
    expect(requested.path, '/home.php');
    expect(requested.queryParameters['mod'], 'space');
    expect(requested.queryParameters['uid'], '257582');
    expect(requested.queryParameters['do'], 'blog');
    expect(requested.queryParameters['id'], '117548');
    expect(requested.queryParameters['mobile'], '2');
  });
}

ProfileBlogRepository _buildRepository(_ProfileBlogHtmlTestAdapter adapter) {
  final gateway = YamiboHttpGateway(
    cookieStore: CookieStore(),
    logger: Logger(level: Level.off),
    dio: Dio(
      BaseOptions(
        baseUrl: 'https://bbs.yamibo.com',
        validateStatus: (status) =>
            status != null && status >= 200 && status < 400,
      ),
    )..httpClientAdapter = adapter,
    enableLog: false,
  );
  return YamiboProfileBlogRepository(
    htmlClient: YamiboHtmlClient(gateway: gateway),
  );
}

class _ProfileBlogHtmlTestAdapter implements HttpClientAdapter {
  _ProfileBlogHtmlTestAdapter({required this.responsePath});

  final String responsePath;
  final requestedUris = <Uri>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedUris.add(options.uri);
    return ResponseBody.fromString(
      File(responsePath).readAsStringSync(),
      200,
      headers: const <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/html; charset=utf-8'],
      },
    );
  }
}

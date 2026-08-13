import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/thread/data/repositories/thread_repository.dart';

/// 回归防护：收藏同步、漫画发现与漫画章节目录必须走 JSON
///（[ApiThreadRepository]），帖子阅读页才走 HTML-first
///（[ThreadDetailHtmlRepository]）。
///
/// 根因回顾：`5f886aac` 把共享的 [threadRepositoryProvider] 从 JSON 翻成移动端
/// HTML，移动端 HTML 没有 `typeid`，导致收藏入队策略与 tagName 反查全部失效。
/// 修复方式是新增 [threadJsonRepositoryProvider] 让同步/发现回到 JSON。
/// 本测试锁定这一分工，防止再次被 HTML 数据源顶替。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('threadJsonRepositoryProvider resolves to JSON ApiThreadRepository', () {
    final container = ProviderContainer(
      overrides: [
        // 用纯 Dart 构造的 ApiClient 覆盖，避免拉起 WAF / 平台通道；
        // 构造期不发起任何网络请求。
        apiClientProvider.overrideWithValue(
          ApiClient(cookieStore: CookieStore(), logger: Logger()),
        ),
      ],
    );
    addTearDown(container.dispose);

    final repository = container.read(threadJsonRepositoryProvider);

    expect(
      repository,
      isA<ApiThreadRepository>(),
      reason: '同步/发现必须走 JSON viewthread（带 typeid），不能退回 HTML。',
    );
  });

  test('comic episode source is pinned to JSON ApiThreadRepository', () {
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(cookieStore: CookieStore(), logger: Logger()),
        ),
      ],
    );
    addTearDown(container.dispose);

    final repository = container.read(comicEpisodeThreadRepositoryProvider);

    expect(
      repository,
      isA<ApiThreadRepository>(),
      reason: '漫画章节目录必须走 JSON viewthread，不能随阅读页切换到 HTML。',
    );
  });

  test('ApiThreadRepository requests viewthread v4 first page', () async {
    final adapter = _ApiThreadTestAdapter();
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://bbs.yamibo.com/api/mobile/index.php',
        validateStatus: (status) =>
            status != null && status >= 200 && status < 400,
      ),
    )..httpClientAdapter = adapter;
    final repository = ApiThreadRepository(
      ApiClient(
        cookieStore: CookieStore(),
        logger: Logger(level: Level.off),
        dio: dio,
        enableLog: false,
      ),
    );

    final result = await repository.getThreadDetail(tid: '573833', page: 1);

    expect(result.isSuccess, isTrue);
    expect(adapter.lastUri?.path, '/api/mobile/index.php');
    expect(adapter.lastUri?.queryParameters['module'], 'viewthread');
    expect(adapter.lastUri?.queryParameters['version'], '4');
    expect(adapter.lastUri?.queryParameters['tid'], '573833');
    expect(adapter.lastUri?.queryParameters['page'], '1');
  });
}

final class _ApiThreadTestAdapter implements HttpClientAdapter {
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
      jsonEncode(<String, dynamic>{
        'Version': '4',
        'Charset': 'utf-8',
        'Variables': <String, dynamic>{
          'fid': '30',
          'ppp': '20',
          'thread': <String, dynamic>{
            'tid': '573833',
            'fid': '30',
            'subject': 'API 帖子',
            'author': 'author',
            'replies': '0',
            'views': '1',
          },
          'postlist': <Map<String, dynamic>>[
            <String, dynamic>{
              'pid': '41584212',
              'author': 'author',
              'authorid': '1',
              'message': '',
              'number': '1',
              'first': '1',
              'dateline': '2026-08-13',
            },
          ],
        },
      }),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }
}

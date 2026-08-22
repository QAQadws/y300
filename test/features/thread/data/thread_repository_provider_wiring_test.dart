import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/api_client.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/data/repositories/discuz_api_comic_episode_catalog_repository.dart';
import 'package:y300/features/thread/data/repositories/thread_repository.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/repositories/thread_repository.dart';

import '../../../support/data_source_contracts/data_read_contract_scenarios.dart';
import '../../../support/data_source_contracts/thread_repository_contract_suite.dart';

/// 回归防护：收藏同步、漫画发现与漫画章节目录必须走 JSON
///（[ApiThreadRepository]），帖子阅读页才走 HTML-first
///（[ThreadDetailHtmlRepository]）。
///
/// 根因回顾：`5f886aac` 把共享的 [threadRepositoryProvider] 从 JSON 翻成移动端
/// HTML，移动端 HTML 没有 `typeid`，导致收藏入队策略与 tagName 反查全部失效。
/// 修复方式是新增 [threadJsonRepositoryProvider] 让同步/发现回到 JSON。
/// 本测试锁定这一分工，防止再次被 HTML 数据源顶替。
void main() {
  runThreadRepositoryContractSuite(
    () => ThreadRepositoryContractDriver(
      name: 'Discuz v4 API',
      createRepository: () =>
          _buildApiThreadRepository(_ApiThreadTestAdapter()),
      tid: '100',
    ),
  );

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

  test('comic catalog provider resolves to the v4 thread API adapter', () {
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(cookieStore: CookieStore(), logger: Logger()),
        ),
      ],
    );
    addTearDown(container.dispose);

    final repository = container.read(comicEpisodeCatalogRepositoryProvider);

    expect(repository, isA<DiscuzApiComicEpisodeCatalogRepository>());
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

    final result = await repository.getThreadDetail(tid: '100', page: 1);

    expect(result.isSuccess, isTrue);
    expectSuccessfulReadContract(
      result,
      hasKnownIdentity: (capabilities) =>
          capabilities.supports(ThreadDetailCapability.threadIdentity),
    );
    final success =
        result
            as DataReadSuccess<ThreadDetailData, ThreadDetailReadCapabilities>;
    expect(
      success.capabilities.supports(ThreadDetailCapability.ratingAction),
      isFalse,
    );
    expect(adapter.lastUri?.path, '/api/mobile/index.php');
    expect(adapter.lastUri?.queryParameters['module'], 'viewthread');
    expect(adapter.lastUri?.queryParameters['version'], '4');
    expect(adapter.lastUri?.queryParameters['tid'], '100');
    expect(adapter.lastUri?.queryParameters['page'], '1');
  });

  test('ApiThreadRepository rejects duplicate post identity', () async {
    final adapter = _ApiThreadTestAdapter(postIds: const <String>['1', '1']);
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

    final result = await repository.getThreadDetail(tid: '100');

    expectSourceNeutralFailure(result, kind: DataReadFailureKind.parse);
  });
}

ApiThreadRepository _buildApiThreadRepository(_ApiThreadTestAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://bbs.yamibo.com/api/mobile/index.php',
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    ),
  )..httpClientAdapter = adapter;
  return ApiThreadRepository(
    ApiClient(
      cookieStore: CookieStore(),
      logger: Logger(level: Level.off),
      dio: dio,
      enableLog: false,
    ),
  );
}

final class _ApiThreadTestAdapter implements HttpClientAdapter {
  _ApiThreadTestAdapter({this.postIds = const <String>['1001']});

  final List<String> postIds;
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
    final fixture =
        jsonDecode(
              await File(
                'test/fixtures/data_source_contracts/thread_detail_v4.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final variables = fixture['Variables'] as Map<String, dynamic>;
    variables['postlist'] = <Map<String, dynamic>>[
      for (var index = 0; index < postIds.length; index += 1)
        <String, dynamic>{
          'pid': postIds[index],
          'author': 'fixture-author',
          'authorid': '1',
          'message': '',
          'number': '${index + 1}',
          'first': index == 0 ? '1' : '0',
          'dateline': '2026-08-13',
        },
    ];
    return ResponseBody.fromString(
      jsonEncode(fixture),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }
}

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/yamibo/yamibo_http_gateway.dart';
import 'package:y300/features/auth/domain/services/formhash_provider.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/search/data/repositories/discuz_forum_search_repository.dart';
import 'package:y300/features/search/domain/models/forum_search_models.dart';
import 'package:y300/features/search/domain/repositories/forum_search_repository.dart';
import '../../../support/data_source_contracts/forum_search_repository_contract_suite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  runForumSearchRepositoryContractSuite(
    () => ForumSearchRepositoryContractDriver(
      name: 'Discuz mobile HTML',
      createRepository: () => _buildRepository(_SearchRepositoryAdapter()),
      query: const ForumSearchQuery(keyword: '漫画'),
    ),
  );

  test('invalid query fails before formhash or network access', () async {
    final adapter = _SearchRepositoryAdapter();
    final repository = _buildRepository(adapter);

    final result = await repository.load(const ForumSearchQuery(keyword: '  '));

    expect(result.failureOrNull?.kind, DataReadFailureKind.business);
    expect(adapter.requestCount, 0);
  });

  test('initial and next-page reads preserve identity and metadata', () async {
    final adapter = _SearchRepositoryAdapter(
      initialHtml: _pageHtml(tid: '100', nextPage: 2),
      nextPageHtml: _pageHtml(tid: '101'),
    );
    final repository = _buildRepository(adapter);
    const query = ForumSearchQuery(keyword: '漫画');

    final first = await repository.load(
      query,
      cachePolicy: CacheLoadPolicy.cacheFirst,
    );
    expect(
      first,
      isA<DataReadSuccess<ForumSearchData, ForumSearchReadCapabilities>>(),
    );
    final firstData = first.dataOrNull!;
    expect(firstData.topics.single.tid, '100');
    expect(firstData.pagination.nextPage?.page, 2);
    expect(first.failureOrNull, isNull);
    expect(
      (first as DataReadSuccess).metadata,
      const DataReadMetadata.network(),
    );
    expect(adapter.requestCount, 2);

    final next = await repository.loadNextPage(
      query,
      firstData.pagination.nextPage!,
      cachePolicy: CacheLoadPolicy.networkFirst,
    );
    expect(next.dataOrNull!.topics.single.tid, '101');
    expect(next.dataOrNull!.pagination.currentPage, 2);
    expect(adapter.requestCount, 3);
  });

  test(
    'current-forum search binds POST and redirect to the requested forum',
    () async {
      final adapter = _SearchRepositoryAdapter(
        postLocation:
            'search.php?mod=curforum&srhfid=42&searchid=778&searchsubmit=yes',
        initialHtml: _pageHtml(tid: '100', forumId: '42'),
      );
      final repository = _buildRepository(adapter);

      final result = await repository.load(
        const ForumSearchQuery(
          keyword: '漫画',
          scope: ForumSearchScope.currentForum,
          forumId: '42',
        ),
      );

      expect(result.failureOrNull, isNull);
      expect(result.dataOrNull!.topics.single.forumId, '42');
      expect(adapter.requestCount, 2);
      expect(adapter.requests.first.uri.queryParameters['mod'], 'curforum');
      expect(adapter.requests.first.uri.queryParameters['srhfid'], '42');
      expect(adapter.postBodies.single, containsPair('srhfid', '42'));
    },
  );

  test('redirect for another forum fails before the result GET', () async {
    final adapter = _SearchRepositoryAdapter(
      postLocation:
          'search.php?mod=curforum&srhfid=99&searchid=778&searchsubmit=yes',
    );
    final repository = _buildRepository(adapter);

    final result = await repository.load(
      const ForumSearchQuery(
        keyword: '漫画',
        scope: ForumSearchScope.currentForum,
        forumId: '42',
      ),
    );

    expect(result.failureOrNull?.kind, DataReadFailureKind.parse);
    expect(adapter.requestCount, 1);
  });

  test(
    'invalid redirect page or duplicate context fails before the result GET',
    () async {
      for (final location in <String>[
        'search.php?mod=forum&searchid=778&page=2',
        'search.php?mod=forum&searchid=778&searchid=779',
        'search.php?mod=forum&searchid=778&page=',
      ]) {
        final adapter = _SearchRepositoryAdapter(postLocation: location);
        final repository = _buildRepository(adapter);

        final result = await repository.load(
          const ForumSearchQuery(keyword: '漫画'),
        );

        expect(result.failureOrNull?.kind, DataReadFailureKind.parse);
        expect(adapter.requestCount, 1);
      }
    },
  );

  test(
    'continuation is opaque and cannot be reused for another query',
    () async {
      final adapter = _SearchRepositoryAdapter(
        initialHtml: _pageHtml(tid: '100', nextPage: 2),
      );
      final repository = _buildRepository(adapter);
      const query = ForumSearchQuery(keyword: '漫画');
      final first = await repository.load(query);
      final continuation = first.dataOrNull!.pagination.nextPage!;

      final result = await repository.loadNextPage(
        const ForumSearchQuery(keyword: '其他'),
        continuation,
      );

      expect(result.failureOrNull?.kind, DataReadFailureKind.business);
      expect(adapter.requestCount, 2);
    },
  );

  test('missing threadlist is a parse failure without leaking HTML', () async {
    final adapter = _SearchRepositoryAdapter(
      initialHtml: '<html>secret</html>',
    );
    final repository = _buildRepository(adapter);

    final result = await repository.load(const ForumSearchQuery(keyword: '漫画'));

    expect(result.failureOrNull?.kind, DataReadFailureKind.parse);
    expect(result.failureOrNull?.diagnosticMessage, isNot(contains('secret')));
  });
}

DiscuzForumSearchRepository _buildRepository(_SearchRepositoryAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      followRedirects: false,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    ),
  )..httpClientAdapter = adapter;
  return DiscuzForumSearchRepository(
    formhashProvider: _FakeFormhashProvider(),
    gateway: YamiboHttpGateway(
      cookieStore: CookieStore(),
      logger: Logger(level: Level.off),
      dio: dio,
      enableLog: false,
    ),
  );
}

String _pageHtml({required String tid, String forumId = '30', int? nextPage}) {
  return '''
<ul class="threadlist">
  <li class="list">
    <a href="forum.php?mod=viewthread&amp;tid=$tid&amp;mobile=2">
      <div class="threadlist_tit"><em>主题 $tid</em></div>
    </a>
    <div class="threadlist_foot">
      <a href="forum.php?mod=forumdisplay&amp;fid=$forumId&amp;mobile=2">漫画区</a>
    </div>
  </li>
</ul>
${nextPage == null ? '' : '<div class="pg"><a class="nxt" href="search.php?mod=forum&amp;searchid=777&amp;page=$nextPage&amp;mobile=2">下一页</a></div>'}
''';
}

class _FakeFormhashProvider implements FormhashProvider {
  @override
  Future<ApiResult<String>> loadFormhash({bool preferProfile = false}) async {
    expect(preferProfile, isTrue);
    return const ApiSuccess<String>('formhash');
  }
}

class _SearchRepositoryAdapter implements HttpClientAdapter {
  _SearchRepositoryAdapter({
    this.initialHtml,
    this.nextPageHtml,
    this.postLocation,
  });

  final String? initialHtml;
  final String? nextPageHtml;
  final String? postLocation;
  int requestCount = 0;
  final List<RequestOptions> requests = <RequestOptions>[];
  final List<Object?> postBodies = <Object?>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount += 1;
    requests.add(options);
    final uri = options.uri;
    if (options.method == 'POST') {
      postBodies.add(options.data);
      return ResponseBody.fromString(
        '',
        302,
        headers: <String, List<String>>{
          'location': <String>[
            postLocation ??
                'search.php?mod=forum&searchid=777&searchsubmit=yes',
          ],
        },
      );
    }
    if (uri.queryParameters['page'] == '2') {
      return ResponseBody.fromString(
        nextPageHtml ?? _pageHtml(tid: '101'),
        200,
      );
    }
    return ResponseBody.fromString(initialHtml ?? _pageHtml(tid: '100'), 200);
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/repositories/comic_catalog_directory_reader.dart';
import 'package:y300/features/comic/domain/services/comic_consecutive_op_post_parser.dart';
import 'package:y300/features/comic/domain/services/comic_episode_discovery_service.dart';
import 'package:y300/features/comic/domain/services/comic_post_parsing_engine.dart';
import 'package:y300/features/comic/domain/services/comic_recursive_thread_request_governor.dart';
import 'package:y300/features/comic/domain/services/comic_thread_discovery_cache.dart';
import 'package:y300/features/favorites/data/services/favorite_first_sync_request_governor.dart';

import '../../../../support/fixture_comic_thread_discovery_repository.dart';

void main() {
  group('ComicEpisodeDiscoveryService', () {
    test(
      'uses direct strategy when current post already has enough episodes',
      () async {
        final service = ComicEpisodeDiscoveryService(
          repository: _fakeThreadFetcher(
            detailsByTid: {
              '100': _thread(
                tid: '100',
                subject: '测试漫画 第10话',
                message: '''
<a href="thread-1001-1-1.html">01</a>
<a href="thread-1002-1-1.html">02</a>
<a href="thread-1003-1-1.html">03</a>
''',
              ),
              '1001': _thread(tid: '1001', subject: '测试漫画 第1话', message: ''),
              '1002': _thread(tid: '1002', subject: '测试漫画 第2话', message: ''),
              '1003': _thread(tid: '1003', subject: '测试漫画 第3话', message: ''),
            },
          ),
          opPostParser: ComicConsecutiveOpPostParser(
            engine: ComicPostParsingEngine(),
          ),
          catalogDirectoryReader: _FakeCatalogDirectoryReader(
            <String, String>{},
          ),
        );

        final result = await service.discoverFromTid('100');

        expect(result.strategy, EpisodeDiscoveryStrategy.direct);
        expect(result.episodeLinks.length, 3);
      },
    );

    test(
      'direct strategy does not request or filter candidate threads',
      () async {
        final requestedTids = <String>[];
        final service = ComicEpisodeDiscoveryService(
          repository: _discoveryRepository((tid) async {
            requestedTids.add(tid);
            if (tid != '2000') {
              return const ApiFailure<ThreadDetailData>(
                ApiError(type: ApiErrorType.network, message: 'unexpected'),
              );
            }
            return ApiSuccess<ThreadDetailData>(
              _thread(
                tid: '2000',
                subject: '测试漫画合集',
                message: '''
<a href="thread-2001-1-1.html">第1话</a>
<a href="thread-2002-1-1.html">第2话</a>
<a href="thread-2003-1-1.html">第3话</a>
''',
              ),
            );
          }),
          opPostParser: ComicConsecutiveOpPostParser(
            engine: ComicPostParsingEngine(),
          ),
          catalogDirectoryReader: _FakeCatalogDirectoryReader(
            <String, String>{},
          ),
        );

        final result = await service.discoverFromTid('2000');

        expect(result.strategy, EpisodeDiscoveryStrategy.direct);
        expect(result.episodeLinks.map((link) => link.url), <String>[
          'https://bbs.yamibo.com/thread-2001-1-1.html',
          'https://bbs.yamibo.com/thread-2002-1-1.html',
          'https://bbs.yamibo.com/thread-2003-1-1.html',
        ]);
        expect(requestedTids, <String>['2000']);
      },
    );

    test(
      'does not apply candidate eligibility rules to the root thread',
      () async {
        final service = ComicEpisodeDiscoveryService(
          repository: _fakeThreadFetcher(
            detailsByTid: <String, ThreadDetailData>{
              '2050': _thread(
                tid: '2050',
                subject: '历史索引来源',
                message: '''
<a href="thread-2051-1-1.html">第1话</a>
<a href="thread-2052-1-1.html">第2话</a>
<a href="thread-2053-1-1.html">第3话</a>
''',
                fid: '49',
                typeid: '293',
              ),
              for (final tid in <String>['2051', '2052', '2053'])
                tid: _thread(tid: tid, subject: '测试漫画', message: ''),
            },
          ),
          opPostParser: ComicConsecutiveOpPostParser(
            engine: ComicPostParsingEngine(),
          ),
          catalogDirectoryReader: _FakeCatalogDirectoryReader(
            <String, String>{},
          ),
        );

        final result = await service.discoverFromTid('2050');

        expect(result.strategy, EpisodeDiscoveryStrategy.direct);
        expect(result.episodeLinks, hasLength(3));
      },
    );

    test(
      'direct strategy keeps candidates without loading their details',
      () async {
        final requestedTids = <String>[];
        final details = <String, ThreadDetailData>{
          '2100': _thread(
            tid: '2100',
            subject: '测试漫画合集',
            message: '''
<a href="thread-2101-1-1.html">第1话</a>
<a href="thread-2102-1-1.html">第2话</a>
<a href="thread-2103-1-1.html">第3话</a>
''',
          ),
          '2101': _thread(tid: '2101', subject: '测试漫画 第1话', message: ''),
          '2103': _thread(tid: '2103', subject: '测试漫画 第3话', message: ''),
        };
        final service = ComicEpisodeDiscoveryService(
          repository: _discoveryRepository((tid) async {
            requestedTids.add(tid);
            final detail = details[tid];
            return detail == null
                ? const ApiFailure<ThreadDetailData>(
                    ApiError(type: ApiErrorType.network, message: 'offline'),
                  )
                : ApiSuccess<ThreadDetailData>(detail);
          }),
          opPostParser: ComicConsecutiveOpPostParser(
            engine: ComicPostParsingEngine(),
          ),
          catalogDirectoryReader: _FakeCatalogDirectoryReader(
            <String, String>{},
          ),
        );

        final result = await service.discoverFromTid('2100');

        expect(result.episodeLinks, hasLength(3));
        expect(requestedTids, <String>['2100']);
      },
    );

    test(
      'uses recursive strategy when root has only one previous link',
      () async {
        final requestedTids = <String>[];
        final recursiveGovernor = _RecordingRecursiveRequestGovernor();
        final details = <String, ThreadDetailData>{
          '300': _thread(
            tid: '300',
            subject: '测试漫画 第3话',
            message: '<a href="thread-299-1-1.html">上一话</a>',
          ),
          '299': _thread(
            tid: '299',
            subject: '测试漫画 第2话',
            message: '<a href="thread-298-1-1.html">上一话</a>',
          ),
          '298': _thread(
            tid: '298',
            subject: '测试漫画 第1话',
            message: '<a href="thread-297-1-1.html">上一话</a>',
          ),
          '297': _thread(tid: '297', subject: '测试漫画 序章', message: ''),
        };
        final service = ComicEpisodeDiscoveryService(
          repository: _discoveryRepository((tid) async {
            requestedTids.add(tid);
            final detail = details[tid];
            return detail == null
                ? const ApiFailure<ThreadDetailData>(
                    ApiError(type: ApiErrorType.business, message: 'not found'),
                  )
                : ApiSuccess<ThreadDetailData>(detail);
          }),
          opPostParser: ComicConsecutiveOpPostParser(
            engine: ComicPostParsingEngine(),
          ),
          catalogDirectoryReader: _FakeCatalogDirectoryReader(
            <String, String>{},
          ),
          recursiveRequestGovernor: recursiveGovernor,
        );

        final result = await service.discoverFromTid('300');

        expect(result.strategy, EpisodeDiscoveryStrategy.recursive);
        expect(result.episodeLinks.length, greaterThanOrEqualTo(3));
        expect(
          result.episodeLinks.any(
            (e) =>
                e.url.contains('tid=299') ||
                e.url.contains('thread-299-1-1.html'),
          ),
          isTrue,
        );
        expect(requestedTids.where((tid) => tid == '299'), hasLength(1));
        expect(recursiveGovernor.scheduledCount, requestedTids.length - 1);
      },
    );

    test(
      'recursive strategy does not traverse rejected announcement links',
      () async {
        final requestedTids = <String>[];
        final details = <String, ThreadDetailData>{
          '300': _thread(
            tid: '300',
            subject: '测试漫画 第10话',
            message: '''
<a href="thread-299-1-1.html">公告</a>
<a href="thread-298-1-1.html">上一话</a>
''',
          ),
          '299': _thread(
            tid: '299',
            subject: '漫画版公告',
            message: '<a href="thread-100-1-1.html">错误下一跳</a>',
            typeid: '65',
          ),
          '298': _thread(
            tid: '298',
            subject: '测试漫画 第9话',
            message: '<a href="thread-297-1-1.html">上一话</a>',
          ),
          '297': _thread(tid: '297', subject: '测试漫画 第8话', message: ''),
        };
        final service = ComicEpisodeDiscoveryService(
          repository: _discoveryRepository((tid) async {
            requestedTids.add(tid);
            final detail = details[tid];
            return detail == null
                ? const ApiFailure<ThreadDetailData>(
                    ApiError(type: ApiErrorType.business, message: 'not found'),
                  )
                : ApiSuccess<ThreadDetailData>(detail);
          }),
          opPostParser: ComicConsecutiveOpPostParser(
            engine: ComicPostParsingEngine(),
          ),
          catalogDirectoryReader: _FakeCatalogDirectoryReader(
            <String, String>{},
          ),
          recursiveRequestGovernor: _immediateRecursiveGovernor(),
          config: const EpisodeDiscoveryConfig(maxConsecutiveFailures: 1),
        );

        final result = await service.discoverFromTid('300');

        expect(result.strategy, EpisodeDiscoveryStrategy.recursive);
        expect(result.episodeLinks.map((link) => link.url), <String>[
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=298',
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=297',
        ]);
        expect(requestedTids, isNot(contains('100')));
        expect(requestedTids.where((tid) => tid == '298'), hasLength(1));
      },
    );

    test('recursive cache hits bypass the request governor', () async {
      final root = _thread(
        tid: '310',
        subject: '测试漫画 第3话',
        message: '<a href="thread-309-1-1.html">上一话</a>',
      );
      final cache = ComicThreadDiscoveryCache()
        ..store(
          _discoveryDocument(
            _thread(tid: '309', subject: '测试漫画 第2话', message: ''),
          ),
        );
      final recursiveGovernor = _RecordingRecursiveRequestGovernor();
      final service = ComicEpisodeDiscoveryService(
        repository: _discoveryRepository(
          (_) async => throw StateError('unexpected request'),
        ),
        opPostParser: ComicConsecutiveOpPostParser(
          engine: ComicPostParsingEngine(),
        ),
        catalogDirectoryReader: _FakeCatalogDirectoryReader(<String, String>{}),
        recursiveRequestGovernor: recursiveGovernor,
      );

      final result = await service.discoverFromTidWithPreference(
        tid: root.tid,
        preferCatalogFirst: false,
        preloadedRootDetail: _discoveryDocument(root),
        threadCache: cache,
      );

      expect(result.strategy, EpisodeDiscoveryStrategy.recursive);
      expect(result.episodeLinks, hasLength(1));
      expect(recursiveGovernor.scheduledCount, 0);
    });

    test('recursive requests retain the favorite sync governor', () async {
      final recursiveGovernor = _RecordingRecursiveRequestGovernor();
      final favoriteGovernor = _RecordingFavoriteRequestGovernor();
      final service = ComicEpisodeDiscoveryService(
        repository: _fakeThreadFetcher(
          detailsByTid: <String, ThreadDetailData>{
            '320': _thread(
              tid: '320',
              subject: '测试漫画 第3话',
              message: '<a href="thread-319-1-1.html">上一话</a>',
            ),
            '319': _thread(tid: '319', subject: '测试漫画 第2话', message: ''),
          },
        ),
        opPostParser: ComicConsecutiveOpPostParser(
          engine: ComicPostParsingEngine(),
        ),
        catalogDirectoryReader: _FakeCatalogDirectoryReader(<String, String>{}),
        recursiveRequestGovernor: recursiveGovernor,
      );

      final result = await service.discoverFromTidWithPreference(
        tid: '320',
        preferCatalogFirst: false,
        governor: favoriteGovernor,
      );

      expect(result.strategy, EpisodeDiscoveryStrategy.recursive);
      expect(recursiveGovernor.scheduledCount, 1);
      expect(favoriteGovernor.kinds, <FavoriteFirstSyncRequestKind>[
        FavoriteFirstSyncRequestKind.comicThreadDetail,
        FavoriteFirstSyncRequestKind.comicThreadDetail,
      ]);
    });

    test(
      'uses catalog strategy when direct and recursive are insufficient',
      () async {
        final service = ComicEpisodeDiscoveryService(
          repository: _fakeThreadFetcher(
            detailsByTid: {
              '500': _thread(
                tid: '500',
                subject: '测试漫画 第1话',
                message:
                    '<a href="https://bbs.yamibo.com/misc.php?mod=tag&id=21137">目录</a>',
              ),
            },
          ),
          opPostParser: ComicConsecutiveOpPostParser(
            engine: ComicPostParsingEngine(),
          ),
          catalogDirectoryReader: _FakeCatalogDirectoryReader({
            'https://bbs.yamibo.com/misc.php?mod=tag&id=21137&type=thread&page=1':
                '''
<html><body>
<table><tr><th><a href="thread-600-1-1.html">第1话</a></th></tr>
<tr><th><a href="thread-601-1-1.html">第2话</a></th></tr></table>
</body></html>
''',
          }),
        );

        final result = await service.discoverFromTid('500');

        expect(result.strategy, EpisodeDiscoveryStrategy.catalog);
        expect(result.episodeLinks.length, 2);
      },
    );

    test('uses catalog strategy for Yamibo elevator tag links', () async {
      final service = ComicEpisodeDiscoveryService(
        repository: _fakeThreadFetcher(
          detailsByTid: {
            '476059': _thread(
              tid: '476059',
              subject: '[百合會]はなにあらし(好事多磨)第6話',
              message:
                  '<a href="https://bbs.yamibo.com/misc.php?mod=tag&amp;amp;id=18235">電梯</a>',
            ),
          },
        ),
        opPostParser: ComicConsecutiveOpPostParser(
          engine: ComicPostParsingEngine(),
        ),
        catalogDirectoryReader: _FakeCatalogDirectoryReader({
          'https://bbs.yamibo.com/misc.php?mod=tag&id=18235&type=thread&page=1':
              '''
<html><body>
<table>
<tr><th><a href="thread-476059-1-1.html">[百合會]はなにあらし(好事多磨)第6話</a></th></tr>
<tr><th><a href="thread-503102-1-1.html">[百合會]はなにあらし(好事多磨)第82話下</a></th></tr>
</table>
</body></html>
''',
        }),
      );

      final result = await service.discoverFromTidWithPreference(
        tid: '476059',
        preferCatalogFirst: true,
      );

      expect(result.strategy, EpisodeDiscoveryStrategy.catalog);
      expect(result.episodeLinks.map((link) => link.url).toList(), <String>[
        'https://bbs.yamibo.com/thread-476059-1-1.html',
        'https://bbs.yamibo.com/thread-503102-1-1.html',
      ]);
    });

    test('catalog strategy follows type=thread pages until total pages', () async {
      final service = ComicEpisodeDiscoveryService(
        repository: _fakeThreadFetcher(
          detailsByTid: {
            '700': _thread(
              tid: '700',
              subject: '测试漫画 第10话',
              message:
                  '<a href="https://bbs.yamibo.com/misc.php?mod=tag&id=21661">目录</a>',
            ),
          },
        ),
        opPostParser: ComicConsecutiveOpPostParser(
          engine: ComicPostParsingEngine(),
        ),
        catalogDirectoryReader: _FakeCatalogDirectoryReader({
          'https://bbs.yamibo.com/misc.php?mod=tag&id=21661&type=thread&page=1':
              '''
<div class="pg"><strong>1</strong>
<label><span title="共 3 页"> / 3 页</span></label>
<a class="nxt" href="misc.php?mod=tag&id=21661&type=thread&page=2">下一页</a></div>
<table><tr><th><a href="thread-800-1-1.html">第1话</a></th></tr></table>
''',
          'https://bbs.yamibo.com/misc.php?mod=tag&id=21661&type=thread&page=2':
              '''
<div class="pg"><strong>2</strong>
<label><span title="共 3 页"> / 3 页</span></label>
<a class="nxt" href="misc.php?mod=tag&id=21661&type=thread&page=3">下一页</a></div>
<table><tr><th><a href="thread-801-1-1.html">第2话</a></th></tr></table>
''',
          'https://bbs.yamibo.com/misc.php?mod=tag&id=21661&type=thread&page=3':
              '''
<div class="pg"><strong>3</strong>
<label><span title="共 3 页"> / 3 页</span></label></div>
<table><tr><th><a href="thread-802-1-1.html">第3话</a></th></tr></table>
''',
        }),
      );

      final result = await service.discoverFromTid('700');
      expect(result.strategy, EpisodeDiscoveryStrategy.catalog);
      expect(result.episodeLinks.length, 3);
      expect(
        result.episodeLinks.any((e) => e.url.contains('thread-802-1-1.html')),
        isTrue,
      );
    });

    test(
      'recursive fallback ignores plain text thread urls outside anchors',
      () async {
        final service = ComicEpisodeDiscoveryService(
          repository: _fakeThreadFetcher(
            detailsByTid: {
              '900': _thread(
                tid: '900',
                subject: '测试漫画 第3话',
                message:
                    'plain text thread-899-1-1.html should stay plain text',
              ),
            },
          ),
          opPostParser: ComicConsecutiveOpPostParser(
            engine: ComicPostParsingEngine(),
          ),
          catalogDirectoryReader: _FakeCatalogDirectoryReader(
            <String, String>{},
          ),
        );

        final result = await service.discoverFromTid('900');

        expect(result.strategy, EpisodeDiscoveryStrategy.direct);
        expect(result.episodeLinks, isEmpty);
      },
    );

    test(
      'discoverFromCatalogUrl returns episode links from catalog page',
      () async {
        var threadFetchCount = 0;
        final service = ComicEpisodeDiscoveryService(
          repository: _discoveryRepository((tid) async {
            threadFetchCount++;
            return const ApiFailure<ThreadDetailData>(
              ApiError(type: ApiErrorType.business, message: 'unused'),
            );
          }),
          opPostParser: ComicConsecutiveOpPostParser(
            engine: ComicPostParsingEngine(),
          ),
          catalogDirectoryReader: _FakeCatalogDirectoryReader({
            'https://bbs.yamibo.com/misc.php?mod=tag&id=99999&type=thread&page=1':
                '''
<html><body>
<table>
<tr><th><a href="thread-1001-1-1.html">第1话</a></th></tr>
<tr><th><a href="thread-1002-1-1.html">第2话</a></th></tr>
<tr><th><a href="thread-1003-1-1.html">第3话</a></th></tr>
</table>
</body></html>
''',
          }),
        );

        final links = await service.discoverFromCatalogUrl(
          'https://bbs.yamibo.com/misc.php?mod=tag&id=99999',
        );

        expect(links, hasLength(3));
        expect(links[0].url, contains('thread-1001-1-1.html'));
        expect(links[1].url, contains('thread-1002-1-1.html'));
        expect(links[2].url, contains('thread-1003-1-1.html'));
        expect(threadFetchCount, 0);
      },
    );

    test(
      'discoverFromCatalogUrl returns empty when catalog has no episodes',
      () async {
        final service = ComicEpisodeDiscoveryService(
          repository: _fakeThreadFetcher(
            detailsByTid: <String, ThreadDetailData>{},
          ),
          opPostParser: ComicConsecutiveOpPostParser(
            engine: ComicPostParsingEngine(),
          ),
          catalogDirectoryReader: _FakeCatalogDirectoryReader(
            <String, String>{},
          ),
        );

        final links = await service.discoverFromCatalogUrl(
          'https://bbs.yamibo.com/misc.php?mod=tag&id=00000',
        );

        expect(links, isEmpty);
      },
    );

    test('rejects a persisted non-tag catalog url before fetching', () async {
      final fetcher = _FakeCatalogDirectoryReader(<String, String>{});
      final service = ComicEpisodeDiscoveryService(
        repository: _fakeThreadFetcher(
          detailsByTid: <String, ThreadDetailData>{},
        ),
        opPostParser: ComicConsecutiveOpPostParser(
          engine: ComicPostParsingEngine(),
        ),
        catalogDirectoryReader: fetcher,
      );

      final links = await service.discoverFromCatalogUrl(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=571564',
      );

      expect(links, isEmpty);
      expect(fetcher.requestedUrls, isEmpty);
    });
  });
}

ThreadDetailData _thread({
  required String tid,
  required String subject,
  required String message,
  String fid = '30',
  String typeid = '',
}) {
  return ThreadDetailData(
    tid: tid,
    fid: fid,
    typeid: typeid,
    subject: subject,
    author: 'op',
    replies: 0,
    views: 0,
    currentPage: 1,
    perPage: 20,
    posts: <ThreadPost>[
      ThreadPost(
        pid: '$tid-1',
        author: 'op',
        authorId: '100',
        message: message,
        number: 1,
        isFirst: true,
        dateline: '',
      ),
    ],
  );
}

ComicThreadDiscoveryRepository _fakeThreadFetcher({
  required Map<String, ThreadDetailData> detailsByTid,
}) {
  return _discoveryRepository((tid) async {
    final detail = detailsByTid[tid];
    if (detail == null) {
      return const ApiFailure<ThreadDetailData>(
        ApiError(type: ApiErrorType.business, message: 'not found'),
      );
    }
    return ApiSuccess<ThreadDetailData>(detail);
  });
}

ComicThreadDiscoveryRepository _discoveryRepository(
  Future<ApiResult<ThreadDetailData>> Function(String tid) loader,
) {
  return FixtureComicThreadDiscoveryRepository(
    threadRepository: _FixtureThreadRepository(loader),
  );
}

ComicThreadDiscoveryDocument _discoveryDocument(ThreadDetailData detail) {
  return const ComicThreadDiscoveryProjector().project(detail);
}

final class _FixtureThreadRepository implements ThreadRepository {
  const _FixtureThreadRepository(this._loader);

  final Future<ApiResult<ThreadDetailData>> Function(String tid) _loader;

  @override
  ThreadDetailSourceCapabilities get capabilities =>
      ThreadDetailSourceCapabilities.full;

  @override
  Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  getThreadDetail({
    required String tid,
    int page = 1,
    ThreadDetailQuery query = const ThreadDetailQuery(),
  }) async {
    final result = await _loader(tid);
    return switch (result) {
      ApiSuccess<ThreadDetailData>(:final data) => DataReadSuccess(
        data: data,
        capabilities: capabilities.toReadCapabilities(),
        metadata: const DataReadMetadata.network(),
      ),
      ApiFailure<ThreadDetailData>(:final error) => DataReadFailure(
        kind: DataReadFailureKind.business,
        code: error.code,
        statusCode: error.statusCode,
        diagnosticMessage: error.message,
      ),
    };
  }
}

class _FakeCatalogDirectoryReader implements ComicCatalogDirectoryReader {
  _FakeCatalogDirectoryReader(this.pages);

  final Map<String, String> pages;
  final List<String> requestedUrls = <String>[];

  @override
  Future<
    DataReadResult<ComicCatalogDirectory, ComicCatalogDirectoryCapabilities>
  >
  load(ComicCatalogDirectoryRequest request) async {
    final references = const ForumReferenceResolver(
      siteOrigin: 'https://bbs.yamibo.com',
    );
    final tagId = references.extractTagId(request.catalogUrl);
    if (tagId == null) {
      return const DataReadFailure(
        kind: DataReadFailureKind.parse,
        diagnosticMessage: 'invalid_catalog_reference',
      );
    }
    final links = <String, ComicEpisodeLink>{};
    var page = references.extractTagPage(request.catalogUrl);
    for (var count = 0; count < request.maxPages; count += 1) {
      final pageUrl = references.normalizeTagPageReference(
        request.catalogUrl,
        page: page,
      )!;
      requestedUrls.add(pageUrl);
      final html = pages[pageUrl];
      if (html == null || html.isEmpty) break;
      final document = html_parser.parseFragment(html);
      for (final anchor in document.querySelectorAll('a[href]')) {
        final href = anchor.attributes['href']?.trim() ?? '';
        final tid = references.extractTid(href, baseUrl: pageUrl);
        final title = anchor.text.trim();
        final normalizedUrl = references.normalizeHref(href, baseUrl: pageUrl);
        if (tid == null || title.isEmpty || normalizedUrl == null) continue;
        links.putIfAbsent(
          tid,
          () => ComicEpisodeLink(
            url: normalizedUrl,
            rawText: title,
            episodeTitle: title,
          ),
        );
      }
      if (document.querySelector('a.nxt') == null) {
        break;
      }
      page += 1;
    }
    return DataReadSuccess(
      data: ComicCatalogDirectory(links: links.values.toList()),
      capabilities: ComicCatalogDirectoryCapabilities(
        values: DataCapabilitySet.supported(
          ComicCatalogDirectoryCapability.values,
        ),
      ),
      metadata: const DataReadMetadata.network(),
    );
  }
}

ComicRecursiveThreadRequestGovernor _immediateRecursiveGovernor() {
  return DefaultComicRecursiveThreadRequestGovernor(cooldown: Duration.zero);
}

class _RecordingRecursiveRequestGovernor
    implements ComicRecursiveThreadRequestGovernor {
  int scheduledCount = 0;

  @override
  Future<T> schedule<T>(Future<T> Function() request) {
    scheduledCount++;
    return request();
  }
}

class _RecordingFavoriteRequestGovernor
    implements FavoriteFirstSyncRequestGovernor {
  final List<FavoriteFirstSyncRequestKind> kinds =
      <FavoriteFirstSyncRequestKind>[];

  @override
  Future<T> run<T>({
    required FavoriteFirstSyncRequestKind kind,
    required Future<T> Function() action,
  }) {
    kinds.add(kind);
    return action();
  }
}

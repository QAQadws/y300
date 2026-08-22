import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/comic/data/repositories/thread_repository_comic_thread_discovery_adapter.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/repositories/comic_thread_discovery_repository.dart';
import 'package:y300/features/comic/domain/services/comic_consecutive_op_post_parser.dart';
import 'package:y300/features/comic/domain/services/comic_incremental_episode_discovery.dart';
import 'package:y300/features/comic/domain/services/comic_post_parsing_engine.dart';
import 'package:y300/features/comic/domain/services/comic_recursive_thread_request_governor.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/repositories/thread_repository.dart';

void main() {
  group('ComicIncrementalEpisodeDiscovery', () {
    group('discoverDirectIncremental', () {
      test('returns only new tids without requesting their details', () async {
        final requestedTids = <String>[];
        final service = ComicIncrementalEpisodeDiscovery(
          repository: _discoveryRepository((tid) async {
            requestedTids.add(tid);
            return ApiSuccess<ThreadDetailData>(
              _thread(tid: tid, subject: '测试漫画', message: ''),
            );
          }),
          opPostParser: ComicConsecutiveOpPostParser(
            engine: ComicPostParsingEngine(),
          ),
        );

        final links = <ComicEpisodeLink>[
          const ComicEpisodeLink(
            url: 'https://bbs.yamibo.com/thread-101-1-1.html',
            rawText: '第1话',
          ),
          const ComicEpisodeLink(
            url: 'https://bbs.yamibo.com/thread-102-1-1.html',
            rawText: '第2话',
          ),
          const ComicEpisodeLink(
            url: 'https://bbs.yamibo.com/thread-103-1-1.html',
            rawText: '第3话',
          ),
          const ComicEpisodeLink(
            url: 'https://bbs.yamibo.com/thread-104-1-1.html',
            rawText: '第4话',
          ),
        ];

        final result = service.discoverDirectIncremental(
          currentLinks: links,
          knownTids: <String>{'101', '102'},
        );

        expect(result, hasLength(2));
        expect(result[0].url, contains('thread-103-1-1.html'));
        expect(result[1].url, contains('thread-104-1-1.html'));
        expect(requestedTids, isEmpty);
      });

      test('returns empty without requests when all links are known', () async {
        var fetchCallCount = 0;
        final service = ComicIncrementalEpisodeDiscovery(
          repository: _discoveryRepository((tid) async {
            fetchCallCount++;
            return const ApiFailure<ThreadDetailData>(
              ApiError(type: ApiErrorType.business, message: ''),
            );
          }),
          opPostParser: ComicConsecutiveOpPostParser(
            engine: ComicPostParsingEngine(),
          ),
        );

        final links = <ComicEpisodeLink>[
          const ComicEpisodeLink(
            url: 'https://bbs.yamibo.com/thread-101-1-1.html',
            rawText: '第1话',
          ),
          const ComicEpisodeLink(
            url: 'https://bbs.yamibo.com/thread-102-1-1.html',
            rawText: '第2话',
          ),
        ];

        final result = service.discoverDirectIncremental(
          currentLinks: links,
          knownTids: <String>{'101', '102'},
        );

        expect(result, isEmpty);
        expect(fetchCallCount, 0);
      });

      test('skips links with unextractable tid without crashing', () async {
        final service = ComicIncrementalEpisodeDiscovery(
          repository: _discoveryRepository(
            (tid) async => ApiSuccess<ThreadDetailData>(
              _thread(tid: tid, subject: '测试漫画', message: ''),
            ),
          ),
          opPostParser: ComicConsecutiveOpPostParser(
            engine: ComicPostParsingEngine(),
          ),
          recursiveRequestGovernor: _immediateRecursiveGovernor(),
        );

        final links = <ComicEpisodeLink>[
          const ComicEpisodeLink(
            url: 'https://example.com/not-a-thread-url',
            rawText: '无关链接',
          ),
          const ComicEpisodeLink(
            url: 'https://bbs.yamibo.com/thread-200-1-1.html',
            rawText: '第1话',
          ),
        ];

        final result = service.discoverDirectIncremental(
          currentLinks: links,
          knownTids: <String>{},
        );

        // 倒序：先处理 thread-200（新），再处理无关链接（跳过）
        expect(result, hasLength(1));
        expect(result[0].url, contains('thread-200-1-1.html'));
      });

      test('does not dynamically filter direct candidates', () async {
        final requestedTids = <String>[];
        final details = <String, ThreadDetailData>{
          '201': _thread(
            tid: '201',
            subject: '测试漫画 第1话',
            message: '',
            typeid: '398',
          ),
          '202': _thread(
            tid: '202',
            subject: '漫画版公告',
            message: '',
            typeid: '65',
          ),
          '203': _thread(
            tid: '203',
            subject: '小说帖子',
            message: '',
            fid: '49',
            typeid: '293',
          ),
        };
        final service = ComicIncrementalEpisodeDiscovery(
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
        );

        final result = service.discoverDirectIncremental(
          currentLinks: const <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-200-1-1.html', rawText: '已知'),
            ComicEpisodeLink(url: 'thread-201-1-1.html', rawText: '第1话'),
            ComicEpisodeLink(url: 'thread-202-1-1.html', rawText: '第2话'),
            ComicEpisodeLink(url: 'thread-203-1-1.html', rawText: '第3话'),
            ComicEpisodeLink(url: 'thread-204-1-1.html', rawText: '第4话'),
          ],
          knownTids: <String>{'200'},
        );

        expect(result.map((link) => link.url), <String>[
          'thread-201-1-1.html',
          'thread-202-1-1.html',
          'thread-203-1-1.html',
          'thread-204-1-1.html',
        ]);
        expect(requestedTids, isEmpty);
      });
    });

    group('discoverRecursiveIncremental', () {
      test('follows previous-episode links and stops at known tid', () async {
        final recursiveGovernor = _RecordingRecursiveRequestGovernor();
        final service = ComicIncrementalEpisodeDiscovery(
          repository: _fakeThreadFetcher(
            detailsByTid: <String, ThreadDetailData>{
              '500': _thread(
                tid: '500',
                subject: '测试漫画 第5话',
                message: '<a href="thread-499-1-1.html">上一话</a>',
              ),
              '499': _thread(
                tid: '499',
                subject: '测试漫画 第4话',
                message: '<a href="thread-498-1-1.html">上一话</a>',
              ),
              '498': _thread(
                tid: '498',
                subject: '测试漫画 第3话',
                message: '<a href="thread-497-1-1.html">上一话</a>',
              ),
            },
          ),
          opPostParser: ComicConsecutiveOpPostParser(
            engine: ComicPostParsingEngine(),
          ),
          recursiveRequestGovernor: recursiveGovernor,
        );

        final result = await service.discoverRecursiveIncremental(
          startTid: '500',
          knownTids: <String>{'498'},
        );

        expect(result, hasLength(2));
        expect(result[0].url, contains('tid=500'));
        expect(result[0].rawText, '测试漫画 第5话');
        expect(result[1].url, contains('tid=499'));
        expect(result[1].rawText, '测试漫画 第4话');
        expect(recursiveGovernor.scheduledCount, 2);
      });

      test('stops when maxRecursiveDepth is reached', () async {
        // 构造无限链：tid1 -> tid2 -> tid3 -> ...
        final details = <String, ThreadDetailData>{};
        for (var i = 1; i <= 20; i++) {
          final nextTid = '${i + 1}';
          details['$i'] = _thread(
            tid: '$i',
            subject: '第$i话',
            message: '<a href="thread-$nextTid-1-1.html">上一话</a>',
          );
        }

        final service = ComicIncrementalEpisodeDiscovery(
          repository: _fakeThreadFetcher(detailsByTid: details),
          opPostParser: ComicConsecutiveOpPostParser(
            engine: ComicPostParsingEngine(),
          ),
          recursiveRequestGovernor: _immediateRecursiveGovernor(),
          maxRecursiveDepth: 3,
        );

        final result = await service.discoverRecursiveIncremental(
          startTid: '1',
          knownTids: <String>{},
        );

        expect(result, hasLength(3));
      });

      test('stops immediately when fetch fails', () async {
        final service = ComicIncrementalEpisodeDiscovery(
          repository: _discoveryRepository(
            (tid) async => const ApiFailure<ThreadDetailData>(
              ApiError(type: ApiErrorType.network, message: 'connection error'),
            ),
          ),
          opPostParser: ComicConsecutiveOpPostParser(
            engine: ComicPostParsingEngine(),
          ),
          recursiveRequestGovernor: _immediateRecursiveGovernor(),
        );

        final result = await service.discoverRecursiveIncremental(
          startTid: '999',
          knownTids: <String>{},
        );

        expect(result, isEmpty);
      });

      test('does not add or follow an ineligible thread', () async {
        final requestedTids = <String>[];
        final service = ComicIncrementalEpisodeDiscovery(
          repository: _discoveryRepository((tid) async {
            requestedTids.add(tid);
            return ApiSuccess<ThreadDetailData>(
              _thread(
                tid: tid,
                subject: '漫画版公告',
                message: '<a href="thread-499-1-1.html">上一话</a>',
                typeid: '65',
              ),
            );
          }),
          opPostParser: ComicConsecutiveOpPostParser(
            engine: ComicPostParsingEngine(),
          ),
        );

        final result = await service.discoverRecursiveIncremental(
          startTid: '500',
          knownTids: <String>{},
        );

        expect(result, isEmpty);
        expect(requestedTids, <String>['500']);
      });
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
  return ThreadRepositoryComicThreadDiscoveryAdapter(
    threadRepository: _FixtureThreadRepository(loader),
  );
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

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_consecutive_op_post_parser.dart';
import 'package:y300/features/comic/domain/services/comic_episode_discovery_service.dart';
import 'package:y300/features/comic/domain/services/comic_incremental_episode_discovery.dart';
import 'package:y300/features/comic/domain/services/comic_post_parsing_engine.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

void main() {
  group('ComicIncrementalEpisodeDiscovery', () {
    group('discoverDirectIncremental', () {
      test('returns new tids not in knownTids without network calls', () {
        var fetchCallCount = 0;
        final service = ComicIncrementalEpisodeDiscovery(
          fetchThreadDetail: (tid) async {
            fetchCallCount++;
            return const ApiFailure<ThreadDetailData>(
              ApiError(type: ApiErrorType.business, message: 'should not be called'),
            );
          },
          opPostParser: ComicConsecutiveOpPostParser(engine: ComicPostParsingEngine()),
        );

        final links = <ComicEpisodeLink>[
          const ComicEpisodeLink(url: 'https://bbs.yamibo.com/thread-101-1-1.html', rawText: '第1话'),
          const ComicEpisodeLink(url: 'https://bbs.yamibo.com/thread-102-1-1.html', rawText: '第2话'),
          const ComicEpisodeLink(url: 'https://bbs.yamibo.com/thread-103-1-1.html', rawText: '第3话'),
          const ComicEpisodeLink(url: 'https://bbs.yamibo.com/thread-104-1-1.html', rawText: '第4话'),
        ];

        final result = service.discoverDirectIncremental(
          currentLinks: links,
          knownTids: <String>{'101', '102'},
        );

        expect(result, hasLength(2));
        expect(result[0].url, contains('thread-103-1-1.html'));
        expect(result[1].url, contains('thread-104-1-1.html'));
        expect(fetchCallCount, 0);
      });

      test('returns empty when all links are known', () {
        final service = ComicIncrementalEpisodeDiscovery(
          fetchThreadDetail: (tid) async =>
              const ApiFailure<ThreadDetailData>(ApiError(type: ApiErrorType.business, message: '')),
          opPostParser: ComicConsecutiveOpPostParser(engine: ComicPostParsingEngine()),
        );

        final links = <ComicEpisodeLink>[
          const ComicEpisodeLink(url: 'https://bbs.yamibo.com/thread-101-1-1.html', rawText: '第1话'),
          const ComicEpisodeLink(url: 'https://bbs.yamibo.com/thread-102-1-1.html', rawText: '第2话'),
        ];

        final result = service.discoverDirectIncremental(
          currentLinks: links,
          knownTids: <String>{'101', '102'},
        );

        expect(result, isEmpty);
      });

      test('skips links with unextractable tid without crashing', () {
        final service = ComicIncrementalEpisodeDiscovery(
          fetchThreadDetail: (tid) async =>
              const ApiFailure<ThreadDetailData>(ApiError(type: ApiErrorType.business, message: '')),
          opPostParser: ComicConsecutiveOpPostParser(engine: ComicPostParsingEngine()),
        );

        final links = <ComicEpisodeLink>[
          const ComicEpisodeLink(url: 'https://example.com/not-a-thread-url', rawText: '无关链接'),
          const ComicEpisodeLink(url: 'https://bbs.yamibo.com/thread-200-1-1.html', rawText: '第1话'),
        ];

        final result = service.discoverDirectIncremental(
          currentLinks: links,
          knownTids: <String>{},
        );

        // 倒序：先处理 thread-200（新），再处理无关链接（跳过）
        expect(result, hasLength(1));
        expect(result[0].url, contains('thread-200-1-1.html'));
      });
    });

    group('discoverRecursiveIncremental', () {
      test('follows previous-episode links and stops at known tid', () async {
        final service = ComicIncrementalEpisodeDiscovery(
          fetchThreadDetail: _fakeThreadFetcher(
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
          opPostParser: ComicConsecutiveOpPostParser(engine: ComicPostParsingEngine()),
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
          fetchThreadDetail: _fakeThreadFetcher(detailsByTid: details),
          opPostParser: ComicConsecutiveOpPostParser(engine: ComicPostParsingEngine()),
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
          fetchThreadDetail: (tid) async => const ApiFailure<ThreadDetailData>(
            ApiError(type: ApiErrorType.network, message: 'connection error'),
          ),
          opPostParser: ComicConsecutiveOpPostParser(engine: ComicPostParsingEngine()),
        );

        final result = await service.discoverRecursiveIncremental(
          startTid: '999',
          knownTids: <String>{},
        );

        expect(result, isEmpty);
      });
    });
  });
}

ThreadDetailData _thread({
  required String tid,
  required String subject,
  required String message,
}) {
  return ThreadDetailData(
    tid: tid,
    fid: '30',
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

ThreadDetailFetcher _fakeThreadFetcher({
  required Map<String, ThreadDetailData> detailsByTid,
}) {
  return (tid) async {
    final detail = detailsByTid[tid];
    if (detail == null) {
      return const ApiFailure<ThreadDetailData>(
        ApiError(type: ApiErrorType.business, message: 'not found'),
      );
    }
    return ApiSuccess<ThreadDetailData>(detail);
  };
}

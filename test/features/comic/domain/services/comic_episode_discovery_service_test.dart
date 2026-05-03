import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/comic/domain/services/comic_consecutive_op_post_parser.dart';
import 'package:y300/features/comic/domain/services/comic_episode_discovery_service.dart';
import 'package:y300/features/comic/domain/services/comic_post_parsing_engine.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

void main() {
  group('ComicEpisodeDiscoveryService', () {
    test('uses direct strategy when current post already has enough episodes', () async {
      final service = ComicEpisodeDiscoveryService(
        fetchThreadDetail: _fakeThreadFetcher(
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
          },
        ),
        opPostParser: ComicConsecutiveOpPostParser(engine: ComicPostParsingEngine()),
        catalogHtmlFetcher: _FakeCatalogHtmlFetcher(<String, String>{}),
      );

      final result = await service.discoverFromTid('100');

      expect(result.strategy, EpisodeDiscoveryStrategy.direct);
      expect(result.episodeLinks.length, 3);
    });

    test('uses recursive strategy when root has only one previous link', () async {
      final service = ComicEpisodeDiscoveryService(
        fetchThreadDetail: _fakeThreadFetcher(
          detailsByTid: {
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
          },
        ),
        opPostParser: ComicConsecutiveOpPostParser(engine: ComicPostParsingEngine()),
        catalogHtmlFetcher: _FakeCatalogHtmlFetcher(<String, String>{}),
      );

      final result = await service.discoverFromTid('300');

      expect(result.strategy, EpisodeDiscoveryStrategy.recursive);
      expect(result.episodeLinks.length, greaterThanOrEqualTo(3));
      expect(result.episodeLinks.any((e) => e.url.contains('tid=299') || e.url.contains('thread-299-1-1.html')), isTrue);
    });

    test('uses catalog strategy when direct and recursive are insufficient', () async {
      final service = ComicEpisodeDiscoveryService(
        fetchThreadDetail: _fakeThreadFetcher(
          detailsByTid: {
            '500': _thread(
              tid: '500',
              subject: '测试漫画 第1话',
              message: '<a href="https://bbs.yamibo.com/misc.php?mod=tag&id=21137">目录</a>',
            ),
          },
        ),
        opPostParser: ComicConsecutiveOpPostParser(engine: ComicPostParsingEngine()),
        catalogHtmlFetcher: _FakeCatalogHtmlFetcher({
          'https://bbs.yamibo.com/misc.php?mod=tag&id=21137': '''
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

Future<ApiResult<ThreadDetailData>> Function(String tid) _fakeThreadFetcher({
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

class _FakeCatalogHtmlFetcher implements CatalogHtmlFetcher {
  _FakeCatalogHtmlFetcher(this.pages);

  final Map<String, String> pages;

  @override
  Future<String?> fetchHtml(String url) async {
    return pages[url];
  }
}

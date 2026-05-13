import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_consecutive_op_post_parser.dart';
import 'package:y300/features/comic/domain/services/comic_episode_discovery_service.dart';
import 'package:y300/features/comic/domain/services/comic_post_parsing_engine.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/search/data/discuz_search_service.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';

void main() {
  group('NetworkComicEpisodeRefreshService', () {
    test('uses search fallback top-k when discovery returns empty', () async {
      final discovery = _FakeDiscoveryService(
        byTid: <String, List<ComicEpisodeLink>>{
          '100': const <ComicEpisodeLink>[],
          '301': const <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-9001-1-1.html', rawText: '第1话'),
          ],
          '302': const <ComicEpisodeLink>[],
          '303': const <ComicEpisodeLink>[],
        },
      );
      final searchService = _FakeDiscuzSearchService(
        response: DiscuzSearchResponse(
          items: const <DiscuzSearchResultItem>[
            DiscuzSearchResultItem(
              tid: '301',
              title: '百合情结 第14话',
              url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=301',
              fid: '30',
            ),
            DiscuzSearchResultItem(
              tid: '302',
              title: '百合情结 特典',
              url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=302',
              fid: '30',
            ),
            DiscuzSearchResultItem(
              tid: '303',
              title: '百合情结 番外',
              url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=303',
              fid: '30',
            ),
          ],
          rateLimited: false,
        ),
      );
      final service = NetworkComicEpisodeRefreshService(
        discoveryService: discovery,
        searchService: searchService,
        subjectParser: const RuleBasedComicSubjectParser(),
        threadSeedFetcher: (tid) async {
          return ThreadSeed(
            subject: const <String, String>{
              '100': '【提黄灯喵汉化组】百合情结 第14话',
            }[tid]!,
          );
        },
      );

      final links = await service.fetchEpisodeLinksFromTid('100');

      expect(links, isNotEmpty);
      expect(links.first.url, contains('9001'));
      expect(searchService.calledKeywords, contains('百合情结'));
      expect(discovery.requestedTids, containsAll(<String>['301']));
    });

    test('returns empty when search is rate limited', () async {
      final discovery = _FakeDiscoveryService(byTid: <String, List<ComicEpisodeLink>>{
        '100': const <ComicEpisodeLink>[],
      });
      final searchService = _FakeDiscuzSearchService(
        response: const DiscuzSearchResponse(
          items: <DiscuzSearchResultItem>[],
          rateLimited: true,
          retryAfter: Duration(seconds: 6),
        ),
      );
      final service = NetworkComicEpisodeRefreshService(
        discoveryService: discovery,
        searchService: searchService,
        subjectParser: const RuleBasedComicSubjectParser(),
        threadSeedFetcher: (tid) async {
          return ThreadSeed(
            subject: const <String, String>{
              '100': '【提黄灯喵汉化组】百合情结 第14话',
            }[tid]!,
          );
        },
      );

      final links = await service.fetchEpisodeLinksFromTid('100');

      expect(links, isEmpty);
    });

    test('searches once and merges when current tid only has older direct links', () async {
      final discovery = _FakeDiscoveryService(
        byTid: <String, List<ComicEpisodeLink>>{
          '100': const <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-90-1-1.html', rawText: '上一话'),
          ],
          '301': const <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-90-1-1.html', rawText: '第13话'),
            ComicEpisodeLink(url: 'thread-100-1-1.html', rawText: '第14话'),
            ComicEpisodeLink(url: 'thread-110-1-1.html', rawText: '第15话'),
          ],
        },
      );
      final searchService = _FakeDiscuzSearchService(
        response: DiscuzSearchResponse(
          items: const <DiscuzSearchResultItem>[
            DiscuzSearchResultItem(
              tid: '301',
              title: '百合情结 第15话',
              url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=301',
              fid: '30',
            ),
          ],
          rateLimited: false,
        ),
      );
      final service = NetworkComicEpisodeRefreshService(
        discoveryService: discovery,
        searchService: searchService,
        subjectParser: const RuleBasedComicSubjectParser(),
        threadSeedFetcher: (tid) async {
          return ThreadSeed(
            subject: const <String, String>{
              '100': '【提黄灯喵汉化组】百合情结 第14话',
            }[tid]!,
          );
        },
      );

      final links = await service.fetchEpisodeLinksFromTid('100');

      expect(searchService.calledKeywords, contains('百合情结'));
      expect(discovery.requestedTids, containsAll(<String>['100', '301']));
      expect(links.map((link) => link.url), <String>[
        'thread-90-1-1.html',
        'thread-100-1-1.html',
        'thread-110-1-1.html',
      ]);
      expect(links.first.rawText, '第13话');
    });

    test('search fallback skips current tid and keeps scanning candidates', () async {
      final discovery = _FakeDiscoveryService(
        byTid: <String, List<ComicEpisodeLink>>{
          '100': const <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-90-1-1.html', rawText: '上一话'),
          ],
          '301': const <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-90-1-1.html', rawText: '第13话'),
            ComicEpisodeLink(url: 'thread-110-1-1.html', rawText: '第15话'),
          ],
        },
      );
      final searchService = _FakeDiscuzSearchService(
        response: DiscuzSearchResponse(
          items: const <DiscuzSearchResultItem>[
            DiscuzSearchResultItem(
              tid: '100',
              title: '百合情结 第14话',
              url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100',
              fid: '30',
            ),
            DiscuzSearchResultItem(
              tid: '301',
              title: '百合情结 第15话',
              url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=301',
              fid: '30',
            ),
          ],
          rateLimited: false,
        ),
      );
      final service = NetworkComicEpisodeRefreshService(
        discoveryService: discovery,
        searchService: searchService,
        subjectParser: const RuleBasedComicSubjectParser(),
        threadSeedFetcher: (tid) async {
          return ThreadSeed(
            subject: const <String, String>{
              '100': '【提黄灯喵汉化组】百合情结 第14话',
            }[tid]!,
          );
        },
      );

      final links = await service.fetchEpisodeLinksFromTid('100');

      expect(discovery.requestedTids, <String>['100', '301']);
      expect(links.map((link) => link.rawText), <String>['第13话', '第15话']);
    });

    test('uses custom search title before custom and source titles', () async {
      final discovery = _FakeDiscoveryService(
        byTid: <String, List<ComicEpisodeLink>>{
          '100': const <ComicEpisodeLink>[],
          '301': const <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-301-1-1.html', rawText: '第1话'),
          ],
        },
      );
      final searchService = _FakeDiscuzSearchService(
        response: DiscuzSearchResponse(
          items: const <DiscuzSearchResultItem>[
            DiscuzSearchResultItem(
              tid: '301',
              title: '真正标题 第1话',
              url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=301',
              fid: '30',
            ),
          ],
          rateLimited: false,
        ),
      );
      final service = NetworkComicEpisodeRefreshService(
        discoveryService: discovery,
        searchService: searchService,
        subjectParser: const RuleBasedComicSubjectParser(),
        threadSeedFetcher: (tid) async {
          return const ThreadSeed(subject: '【错误组】错误标题 第1话');
        },
      );

      final links = await service.fetchEpisodeLinks(
        const ComicEpisodeRefreshRequest(
          comicId: 'comic:100',
          sourceTid: '100',
          displayTitle: '展示标题',
          sourceTitle: '来源标题',
          customTitle: '自定义标题',
          customSearchTitle: '真正标题',
        ),
      );

      expect(links, isNotEmpty);
      expect(searchService.calledKeywords, <String>['真正标题']);
      expect(discovery.requestedTids, <String>['100', '301']);
    });

    test('falls back from empty custom search title to custom title', () async {
      final discovery = _FakeDiscoveryService(
        byTid: <String, List<ComicEpisodeLink>>{
          '100': const <ComicEpisodeLink>[],
        },
      );
      final searchService = _FakeDiscuzSearchService(
        response: const DiscuzSearchResponse(
          items: <DiscuzSearchResultItem>[],
          rateLimited: false,
        ),
      );
      final service = NetworkComicEpisodeRefreshService(
        discoveryService: discovery,
        searchService: searchService,
        subjectParser: const RuleBasedComicSubjectParser(),
        threadSeedFetcher: (tid) async {
          return const ThreadSeed(subject: '来源标题 第1话');
        },
      );

      await service.fetchEpisodeLinks(
        const ComicEpisodeRefreshRequest(
          sourceTid: '100',
          customSearchTitle: '   ',
          customTitle: '自定义标题',
          displayTitle: '展示标题',
          sourceTitle: '来源标题',
        ),
      );

      expect(searchService.calledKeywords, <String>['自定义标题']);
    });
  });
}

class _FakeDiscoveryService extends ComicEpisodeDiscoveryService {
  _FakeDiscoveryService({
    required this.byTid,
  }) : super(
         fetchThreadDetail: (_) async => const ApiFailure<ThreadDetailData>(
           ApiError(type: ApiErrorType.business, message: 'unused'),
         ),
         opPostParser: ComicConsecutiveOpPostParser(
           engine: ComicPostParsingEngine(),
         ),
         catalogHtmlFetcher: _NoopCatalogHtmlFetcher(),
       );

  final Map<String, List<ComicEpisodeLink>> byTid;
  final List<String> requestedTids = <String>[];

  @override
  Future<EpisodeDiscoveryResult> discoverFromTid(String tid) async {
    requestedTids.add(tid);
    return EpisodeDiscoveryResult(
      strategy: EpisodeDiscoveryStrategy.direct,
      episodeLinks: byTid[tid] ?? const <ComicEpisodeLink>[],
    );
  }

  @override
  Future<EpisodeDiscoveryResult> discoverFromTidWithPreference({
    required String tid,
    required bool preferCatalogFirst,
  }) async {
    requestedTids.add(tid);
    return EpisodeDiscoveryResult(
      strategy: EpisodeDiscoveryStrategy.direct,
      episodeLinks: byTid[tid] ?? const <ComicEpisodeLink>[],
    );
  }
}

class _NoopCatalogHtmlFetcher implements CatalogHtmlFetcher {
  @override
  Future<String?> fetchHtml(String url) async {
    return null;
  }
}

class _FakeDiscuzSearchService implements ForumSearchService {
  _FakeDiscuzSearchService({
    required DiscuzSearchResponse response,
  }) : _response = response;

  final DiscuzSearchResponse _response;
  final List<String> calledKeywords = <String>[];

  @override
  Future<DiscuzSearchResponse> searchForum({
    required String keyword,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
    bool enforceRateLimit = true,
  }) async {
    calledKeywords.add(keyword);
    return _response;
  }

  @override
  Future<DiscuzSearchResponse> fetchNextPage({
    required String nextPageUrl,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
  }) async {
    return const DiscuzSearchResponse(
      items: <DiscuzSearchResultItem>[],
      rateLimited: false,
    );
  }
}

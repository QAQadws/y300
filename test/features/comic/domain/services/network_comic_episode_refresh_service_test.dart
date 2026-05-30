import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_consecutive_op_post_parser.dart';
import 'package:y300/features/comic/domain/services/comic_episode_discovery_service.dart';
import 'package:y300/features/comic/domain/services/comic_post_parsing_engine.dart';
import 'package:y300/features/comic/domain/services/comic_reader_feature_flags.dart';
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

    test('uses matched search results when candidate discovery finds no links', () async {
      final discovery = _FakeDiscoveryService(
        byTid: <String, List<ComicEpisodeLink>>{
          '476059': const <ComicEpisodeLink>[],
          '503102': const <ComicEpisodeLink>[],
          '502780': const <ComicEpisodeLink>[],
          '502128': const <ComicEpisodeLink>[],
        },
      );
      final searchService = _FakeDiscuzSearchService(
        response: DiscuzSearchResponse(
          items: const <DiscuzSearchResultItem>[
            DiscuzSearchResultItem(
              tid: '503102',
              title: '[百合會][サンデーうぇぶり][古鉢るか]はなにあらし(好事多磨)第82話下',
              url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=503102',
              fid: '30',
            ),
            DiscuzSearchResultItem(
              tid: '502780',
              title: '[百合會][サンデーうぇぶり][古鉢るか]はなにあらし(好事多磨)第82話上',
              url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=502780',
              fid: '30',
            ),
            DiscuzSearchResultItem(
              tid: '502128',
              title: '[百合會][サンデーうぇぶり][古鉢るか]はなにあらし(好事多磨)第81話',
              url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=502128',
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
          return const ThreadSeed(
            subject: '[百合會][サンデーうぇぶり][古鉢るか]はなにあらし(好事多磨)第6話',
          );
        },
      );

      final links = await service.fetchEpisodeLinks(
        const ComicEpisodeRefreshRequest(
          comicId: 'yamibo:476059',
          sourceTid: '476059',
          customTitle: '好事多磨',
        ),
      );

      expect(discovery.requestedTids, <String>['476059', '503102', '502780', '502128']);
      expect(links.map((link) => link.url).toList(), <String>[
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=502128',
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=502780',
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=503102',
      ]);
      expect(links.map((link) => link.episodeTitle).toList(), <String>[
        '第81話',
        '第82話上',
        '第82話下',
      ]);
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

    test('does not merge low-score search candidates', () async {
      final discovery = _FakeDiscoveryService(
        byTid: <String, List<ComicEpisodeLink>>{
          '100': const <ComicEpisodeLink>[],
          '401': const <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-401-1-1.html', rawText: '低分误匹配'),
          ],
        },
      );
      final searchService = _FakeDiscuzSearchService(
        response: const DiscuzSearchResponse(
          items: <DiscuzSearchResultItem>[
            DiscuzSearchResultItem(
              tid: '401',
              title: '完全不同的作品 第1话',
              url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=401',
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
          return const ThreadSeed(subject: '百合情结 第4话');
        },
      );

      final links = await service.fetchEpisodeLinksFromTid('100');

      expect(links, isEmpty);
      expect(discovery.requestedTids, <String>['100']);
    });

    test('multi-keyword flag retries source title after custom keyword has no hits', () async {
      final discovery = _FakeDiscoveryService(
        byTid: <String, List<ComicEpisodeLink>>{
          '100': const <ComicEpisodeLink>[],
          '501': const <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-501-1-1.html', rawText: '第1话'),
          ],
        },
      );
      final searchService = _SequencedDiscuzSearchService(
        responses: <DiscuzSearchResponse>[
          const DiscuzSearchResponse(
            items: <DiscuzSearchResultItem>[],
            rateLimited: false,
          ),
          const DiscuzSearchResponse(
            items: <DiscuzSearchResultItem>[
              DiscuzSearchResultItem(
                tid: '501',
                title: '来源标题 第1话',
                url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=501',
                fid: '30',
              ),
            ],
            rateLimited: false,
          ),
        ],
      );
      final service = NetworkComicEpisodeRefreshService(
        discoveryService: discovery,
        searchService: searchService,
        subjectParser: const RuleBasedComicSubjectParser(),
        featureFlags: ComicReaderFeatureFlags.defaults.copyWith(
          readerRefreshMultiKeywordEnabled: true,
        ),
        threadSeedFetcher: (tid) async {
          return const ThreadSeed(subject: '来源标题 第1话');
        },
      );

      final links = await service.fetchEpisodeLinks(
        const ComicEpisodeRefreshRequest(
          sourceTid: '100',
          customSearchTitle: '错误关键词',
          sourceTitle: '来源标题',
        ),
      );

      expect(searchService.calledKeywords, <String>['错误关键词', '来源标题']);
      expect(links.map((link) => link.url), <String>['thread-501-1-1.html']);
    });

    test('single keyword mode does not retry lower priority title', () async {
      final discovery = _FakeDiscoveryService(
        byTid: <String, List<ComicEpisodeLink>>{
          '100': const <ComicEpisodeLink>[],
          '501': const <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-501-1-1.html', rawText: '第1话'),
          ],
        },
      );
      final searchService = _SequencedDiscuzSearchService(
        responses: <DiscuzSearchResponse>[
          const DiscuzSearchResponse(
            items: <DiscuzSearchResultItem>[],
            rateLimited: false,
          ),
          const DiscuzSearchResponse(
            items: <DiscuzSearchResultItem>[
              DiscuzSearchResultItem(
                tid: '501',
                title: '来源标题 第1话',
                url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=501',
                fid: '30',
              ),
            ],
            rateLimited: false,
          ),
        ],
      );
      final service = NetworkComicEpisodeRefreshService(
        discoveryService: discovery,
        searchService: searchService,
        subjectParser: const RuleBasedComicSubjectParser(),
        threadSeedFetcher: (tid) async {
          return const ThreadSeed(subject: '来源标题 第1话');
        },
      );

      final links = await service.fetchEpisodeLinks(
        const ComicEpisodeRefreshRequest(
          sourceTid: '100',
          customSearchTitle: '错误关键词',
          sourceTitle: '来源标题',
        ),
      );

      expect(searchService.calledKeywords, <String>['错误关键词']);
      expect(links, isEmpty);
      expect(discovery.requestedTids, <String>['100']);
    });

    test('search candidate links exclude current tid when discovery is empty', () async {
      final discovery = _FakeDiscoveryService(
        byTid: <String, List<ComicEpisodeLink>>{
          '100': const <ComicEpisodeLink>[],
          '601': const <ComicEpisodeLink>[],
        },
      );
      final searchService = _FakeDiscuzSearchService(
        response: const DiscuzSearchResponse(
          items: <DiscuzSearchResultItem>[
            DiscuzSearchResultItem(
              tid: '100',
              title: '测试漫画 第1话',
              url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100',
              fid: '30',
            ),
            DiscuzSearchResultItem(
              tid: '601',
              title: '测试漫画 第2话',
              url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=601',
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
          return const ThreadSeed(subject: '测试漫画 第1话');
        },
      );

      final links = await service.fetchEpisodeLinksFromTid('100');

      expect(
        links.map((link) => link.url).toList(),
        <String>['https://bbs.yamibo.com/forum.php?mod=viewthread&tid=601'],
      );
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

    test('normalizes display title before using it as search keyword', () async {
      final discovery = _FakeDiscoveryService(
        byTid: <String, List<ComicEpisodeLink>>{
          '100': const <ComicEpisodeLink>[],
          '301': const <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-301-1-1.html', rawText: 'EP 03'),
          ],
        },
      );
      final searchService = _FakeDiscuzSearchService(
        response: const DiscuzSearchResponse(
          items: <DiscuzSearchResultItem>[
            DiscuzSearchResultItem(
              tid: '301',
              title: '[Scan] Parsed Display Comic EP 03',
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
        threadSeedFetcher: (_) async {
          return const ThreadSeed(subject: '[Scan] Current Thread EP 01');
        },
      );

      final links = await service.fetchEpisodeLinks(
        const ComicEpisodeRefreshRequest(
          sourceTid: '100',
          displayTitle: '[Favorite] Parsed Display Comic EP 02',
        ),
      );

      expect(links, isNotEmpty);
      expect(searchService.calledKeywords, <String>['Parsed Display Comic']);
      expect(discovery.requestedTids, <String>['100', '301']);
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

    test('catalog-only returns catalog outcome without searching', () async {
      final discovery = _FakeDiscoveryService(
        byTid: <String, List<ComicEpisodeLink>>{
          '100': const <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '第1话'),
          ],
        },
        strategyByTid: const <String, EpisodeDiscoveryStrategy>{
          '100': EpisodeDiscoveryStrategy.catalog,
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
      );

      final outcome = await service.fetchCatalogOnly(
        const ComicEpisodeRefreshRequest(sourceTid: '100'),
      );

      expect(outcome.source, ComicEpisodeRefreshSource.catalog);
      expect(outcome.catalogMatched, isTrue);
      expect(outcome.links, hasLength(1));
      expect(searchService.calledKeywords, isEmpty);
    });

    test('catalog-only miss does not trigger search fallback', () async {
      final discovery = _FakeDiscoveryService(
        byTid: <String, List<ComicEpisodeLink>>{
          '100': const <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-90-1-1.html', rawText: '上一话'),
          ],
        },
      );
      final searchService = _FakeDiscuzSearchService(
        response: const DiscuzSearchResponse(
          items: <DiscuzSearchResultItem>[
            DiscuzSearchResultItem(
              tid: '301',
              title: '测试漫画 第2话',
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
      );

      final outcome = await service.fetchCatalogOnly(
        const ComicEpisodeRefreshRequest(sourceTid: '100'),
      );

      expect(outcome.source, ComicEpisodeRefreshSource.empty);
      expect(outcome.links, isEmpty);
      expect(outcome.catalogMatched, isFalse);
      expect(searchService.calledKeywords, isEmpty);
    });

    test('search-and-current-only returns search outcome and skips current catalog fallback', () async {
      final discovery = _FakeDiscoveryService(
        byTid: <String, List<ComicEpisodeLink>>{
          '100': const <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-90-1-1.html', rawText: '上一话'),
          ],
          '301': const <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '第1话'),
          ],
        },
      );
      final searchService = _FakeDiscuzSearchService(
        response: const DiscuzSearchResponse(
          items: <DiscuzSearchResultItem>[
            DiscuzSearchResultItem(
              tid: '301',
              title: '测试漫画 第1话',
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
        threadSeedFetcher: (_) async {
          return const ThreadSeed(subject: '测试漫画 第2话');
        },
      );

      final outcome = await service.fetchSearchAndCurrentOnly(
        const ComicEpisodeRefreshRequest(sourceTid: '100'),
      );

      expect(outcome.source, ComicEpisodeRefreshSource.search);
      expect(outcome.usedSearch, isTrue);
      expect(outcome.links.map((link) => link.url), contains('thread-101-1-1.html'));
      expect(discovery.catalogFallbackAllowedByTid['100'], isFalse);
    });

    test('catalog-then-fallback returns catalog outcome when catalog matches', () async {
      final discovery = _FakeDiscoveryService(
        byTid: <String, List<ComicEpisodeLink>>{
          '100': const <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: 'EP 01'),
          ],
        },
        strategyByTid: const <String, EpisodeDiscoveryStrategy>{
          '100': EpisodeDiscoveryStrategy.catalog,
        },
      );
      final service = NetworkComicEpisodeRefreshService(
        discoveryService: discovery,
        searchService: _FakeDiscuzSearchService(
          response: const DiscuzSearchResponse(
            items: <DiscuzSearchResultItem>[],
            rateLimited: false,
          ),
        ),
        subjectParser: const RuleBasedComicSubjectParser(),
      );

      final outcome = await service.fetchCatalogThenFallback(
        const ComicEpisodeRefreshRequest(sourceTid: '100'),
      );

      expect(outcome.source, ComicEpisodeRefreshSource.catalog);
      expect(outcome.catalogMatched, isTrue);
      expect(outcome.links, hasLength(1));
    });

    test('catalog-then-fallback returns search outcome when catalog misses', () async {
      final discovery = _FakeDiscoveryService(
        byTid: <String, List<ComicEpisodeLink>>{
          '100': const <ComicEpisodeLink>[],
          '301': const <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-301-1-1.html', rawText: 'EP 03'),
          ],
        },
      );
      final searchService = _FakeDiscuzSearchService(
        response: const DiscuzSearchResponse(
          items: <DiscuzSearchResultItem>[
            DiscuzSearchResultItem(
              tid: '301',
              title: '[Scan] Parsed Display Comic EP 03',
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
        threadSeedFetcher: (_) async {
          return const ThreadSeed(subject: '[Scan] Current Thread EP 01');
        },
      );

      final outcome = await service.fetchCatalogThenFallback(
        const ComicEpisodeRefreshRequest(
          sourceTid: '100',
          displayTitle: '[Favorite] Parsed Display Comic EP 02',
        ),
      );

      expect(outcome.source, ComicEpisodeRefreshSource.search);
      expect(outcome.usedSearch, isTrue);
      expect(outcome.links, isNotEmpty);
      expect(searchService.calledKeywords, <String>['Parsed Display Comic']);
    });

    test('catalog-then-fallback returns current-only outcome when search misses', () async {
      final discovery = _FakeDiscoveryService(
        byTid: <String, List<ComicEpisodeLink>>{
          '100': const <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-100-1-1.html', rawText: 'EP 01'),
          ],
        },
      );
      final service = NetworkComicEpisodeRefreshService(
        discoveryService: discovery,
        searchService: _FakeDiscuzSearchService(
          response: const DiscuzSearchResponse(
            items: <DiscuzSearchResultItem>[],
            rateLimited: false,
          ),
        ),
        subjectParser: const RuleBasedComicSubjectParser(),
        threadSeedFetcher: (_) async {
          return const ThreadSeed(subject: 'Current Comic EP 01');
        },
      );

      final outcome = await service.fetchCatalogThenFallback(
        const ComicEpisodeRefreshRequest(
          sourceTid: '100',
          displayTitle: 'Current Comic EP 01',
        ),
      );

      expect(outcome.source, ComicEpisodeRefreshSource.currentOnly);
      expect(outcome.usedSearch, isTrue);
      expect(outcome.links, hasLength(1));
    });

    test('catalog-then-fallback returns empty outcome when nothing is found', () async {
      final discovery = _FakeDiscoveryService(
        byTid: <String, List<ComicEpisodeLink>>{
          '100': const <ComicEpisodeLink>[],
        },
      );
      final service = NetworkComicEpisodeRefreshService(
        discoveryService: discovery,
        searchService: _FakeDiscuzSearchService(
          response: const DiscuzSearchResponse(
            items: <DiscuzSearchResultItem>[],
            rateLimited: false,
          ),
        ),
        subjectParser: const RuleBasedComicSubjectParser(),
        threadSeedFetcher: (_) async {
          return const ThreadSeed(subject: 'Current Comic EP 01');
        },
      );

      final outcome = await service.fetchCatalogThenFallback(
        const ComicEpisodeRefreshRequest(
          sourceTid: '100',
          displayTitle: 'Current Comic EP 01',
        ),
      );

      expect(outcome.source, ComicEpisodeRefreshSource.empty);
      expect(outcome.links, isEmpty);
    });
  });
}

class _FakeDiscoveryService extends ComicEpisodeDiscoveryService {
  _FakeDiscoveryService({
    required this.byTid,
    this.strategyByTid = const <String, EpisodeDiscoveryStrategy>{},
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
  final Map<String, EpisodeDiscoveryStrategy> strategyByTid;
  final List<String> requestedTids = <String>[];
  final Map<String, bool> catalogFallbackAllowedByTid = <String, bool>{};

  @override
  Future<EpisodeDiscoveryResult> discoverFromTid(String tid) async {
    requestedTids.add(tid);
    return EpisodeDiscoveryResult(
      strategy: strategyByTid[tid] ?? EpisodeDiscoveryStrategy.direct,
      episodeLinks: byTid[tid] ?? const <ComicEpisodeLink>[],
    );
  }

  @override
  Future<EpisodeDiscoveryResult> discoverFromTidWithPreference({
    required String tid,
    required bool preferCatalogFirst,
    bool allowCatalogFallback = true,
  }) async {
    requestedTids.add(tid);
    catalogFallbackAllowedByTid[tid] = allowCatalogFallback;
    return EpisodeDiscoveryResult(
      strategy: strategyByTid[tid] ?? EpisodeDiscoveryStrategy.direct,
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

class _SequencedDiscuzSearchService implements ForumSearchService {
  _SequencedDiscuzSearchService({
    required List<DiscuzSearchResponse> responses,
  }) : _responses = responses;

  final List<DiscuzSearchResponse> _responses;
  final List<String> calledKeywords = <String>[];
  int _index = 0;

  @override
  Future<DiscuzSearchResponse> searchForum({
    required String keyword,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
    bool enforceRateLimit = true,
  }) async {
    calledKeywords.add(keyword);
    final response = _responses[_index.clamp(0, _responses.length - 1).toInt()];
    _index++;
    return response;
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

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_consecutive_op_post_parser.dart';
import 'package:y300/features/comic/domain/services/comic_episode_discovery_service.dart';
import 'package:y300/features/comic/domain/services/comic_episode_link_merger.dart';
import 'package:y300/features/comic/domain/services/comic_post_parsing_engine.dart';
import 'package:y300/features/comic/domain/services/comic_reader_feature_flags.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_keyword_resolver.dart';
import 'package:y300/features/comic/domain/services/comic_search_candidate_ranker.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';
import 'package:y300/features/comic/domain/services/comic_thread_detail_cache.dart';
import 'package:y300/features/favorites/data/services/favorite_first_sync_request_governor.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/search/data/services/discuz_search_service.dart';
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
      final service = _buildService(
        discoveryService: discovery,
        searchService: searchService,
        subjectParser: const RuleBasedComicSubjectParser(),
        threadSeedFetcher: (tid) async {
          return ThreadSeed(
            subject: const <String, String>{'100': '【提黄灯喵汉化组】百合情结 第14话'}[tid]!,
          );
        },
      );

      final links = await service.fetchEpisodeLinksFromTid('100');

      expect(links, isNotEmpty);
      expect(links.first.url, contains('9001'));
      expect(searchService.calledKeywords, contains('百合情结'));
      expect(discovery.requestedTids, containsAll(<String>['301']));
    });

    test(
      'uses matched search results when candidate discovery finds no links',
      () async {
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
                url:
                    'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=503102',
                fid: '30',
              ),
              DiscuzSearchResultItem(
                tid: '502780',
                title: '[百合會][サンデーうぇぶり][古鉢るか]はなにあらし(好事多磨)第82話上',
                url:
                    'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=502780',
                fid: '30',
              ),
              DiscuzSearchResultItem(
                tid: '502128',
                title: '[百合會][サンデーうぇぶり][古鉢るか]はなにあらし(好事多磨)第81話',
                url:
                    'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=502128',
                fid: '30',
              ),
            ],
            rateLimited: false,
          ),
        );
        final service = _buildService(
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

        expect(discovery.requestedTids, <String>[
          '476059',
          '503102',
          '502780',
          '502128',
        ]);
        expect(links.map((link) => link.url).toList(), <String>[
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=502128',
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=502780',
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=503102',
        ]);
        expect(links.map((link) => link.episodeTitle).toList(), <String>[
          '第81话',
          '第82话上',
          '第82话下',
        ]);
      },
    );

    test('returns empty when search is rate limited', () async {
      final discovery = _FakeDiscoveryService(
        byTid: <String, List<ComicEpisodeLink>>{
          '100': const <ComicEpisodeLink>[],
        },
      );
      final searchService = _FakeDiscuzSearchService(
        response: const DiscuzSearchResponse(
          items: <DiscuzSearchResultItem>[],
          rateLimited: true,
          retryAfter: Duration(seconds: 6),
        ),
      );
      final service = _buildService(
        discoveryService: discovery,
        searchService: searchService,
        subjectParser: const RuleBasedComicSubjectParser(),
        threadSeedFetcher: (tid) async {
          return ThreadSeed(
            subject: const <String, String>{'100': '【提黄灯喵汉化组】百合情结 第14话'}[tid]!,
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
      final service = _buildService(
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

    test(
      'multi-keyword flag retries source title after custom keyword has no hits',
      () async {
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
                  url:
                      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=501',
                  fid: '30',
                ),
              ],
              rateLimited: false,
            ),
          ],
        );
        final service = _buildService(
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
        expect(links.map((link) => link.url), <String>[
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=501',
        ]);
      },
    );

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
      final service = _buildService(
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

    test('search candidate links keep an episode-like current tid', () async {
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
      final service = _buildService(
        discoveryService: discovery,
        searchService: searchService,
        subjectParser: const RuleBasedComicSubjectParser(),
        threadSeedFetcher: (tid) async {
          return const ThreadSeed(subject: '测试漫画 第1话');
        },
      );

      final links = await service.fetchEpisodeLinksFromTid('100');

      expect(links.map((link) => link.url).toList(), <String>[
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100',
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=601',
      ]);
    });

    test(
      'keeps the real latest episode when the favorited source is latest',
      () async {
        final discovery = _FakeDiscoveryService(
          byTid: <String, List<ComicEpisodeLink>>{
            '571256': const <ComicEpisodeLink>[
              ComicEpisodeLink(url: 'thread-568759-1-1.html', rawText: '第1话'),
              ComicEpisodeLink(url: 'thread-570088-1-1.html', rawText: '第2话'),
            ],
            '570088': const <ComicEpisodeLink>[
              ComicEpisodeLink(url: 'thread-568759-1-1.html', rawText: '第1话'),
            ],
            '568759': const <ComicEpisodeLink>[],
          },
        );
        final searchService = _FakeDiscuzSearchService(
          response: const DiscuzSearchResponse(
            items: <DiscuzSearchResultItem>[
              DiscuzSearchResultItem(
                tid: '571256',
                title: '[汉化工房九九组][相崎うたう]可爱会毁灭一切 03话',
                url: 'https://bbs.yamibo.com/thread-571256-1-1.html',
                fid: '30',
              ),
              DiscuzSearchResultItem(
                tid: '570088',
                title: '[汉化工房九九组][相崎うたう]可爱会毁灭一切 02话',
                url: 'https://bbs.yamibo.com/thread-570088-1-1.html',
                fid: '30',
              ),
              DiscuzSearchResultItem(
                tid: '568759',
                title: '[汉化工房九九组][相崎うたう]可爱会毁灭一切 01话',
                url: 'https://bbs.yamibo.com/thread-568759-1-1.html',
                fid: '30',
              ),
            ],
            rateLimited: false,
          ),
        );
        final service = _buildService(
          discoveryService: discovery,
          searchService: searchService,
          subjectParser: const RuleBasedComicSubjectParser(),
          threadSeedFetcher: (_) async {
            return const ThreadSeed(subject: '[汉化工房九九组][相崎うたう]可爱会毁灭一切 03话');
          },
        );

        final links = await service.fetchEpisodeLinksFromTid('571256');

        expect(links.map((link) => link.episodeTitle).toList(), <String>[
          '第1话',
          '第2话',
          '第3话',
        ]);
        expect(discovery.requestedTids, <String>['571256', '570088', '568759']);
      },
    );

    test(
      'keeps the latest episode when the favorited source is older',
      () async {
        final discovery = _FakeDiscoveryService(
          byTid: <String, List<ComicEpisodeLink>>{
            '568759': const <ComicEpisodeLink>[],
            '571256': const <ComicEpisodeLink>[
              ComicEpisodeLink(url: 'thread-568759-1-1.html', rawText: '01话'),
              ComicEpisodeLink(url: 'thread-570088-1-1.html', rawText: '02话'),
            ],
            '570088': const <ComicEpisodeLink>[
              ComicEpisodeLink(url: 'thread-568759-1-1.html', rawText: '01话'),
            ],
          },
        );
        final searchService = _FakeDiscuzSearchService(
          response: const DiscuzSearchResponse(
            items: <DiscuzSearchResultItem>[
              DiscuzSearchResultItem(
                tid: '571256',
                title: '可爱会毁灭一切 03话',
                url: 'https://bbs.yamibo.com/thread-571256-1-1.html',
                fid: '30',
              ),
              DiscuzSearchResultItem(
                tid: '570088',
                title: '可爱会毁灭一切 02话',
                url: 'https://bbs.yamibo.com/thread-570088-1-1.html',
                fid: '30',
              ),
              DiscuzSearchResultItem(
                tid: '568759',
                title: '可爱会毁灭一切 01话',
                url: 'https://bbs.yamibo.com/thread-568759-1-1.html',
                fid: '30',
              ),
            ],
            rateLimited: false,
          ),
        );
        final service = _buildService(
          discoveryService: discovery,
          searchService: searchService,
          subjectParser: const RuleBasedComicSubjectParser(),
          threadSeedFetcher: (_) async {
            return const ThreadSeed(subject: '可爱会毁灭一切 01话');
          },
        );

        final links = await service.fetchEpisodeLinksFromTid('568759');

        expect(links.map((link) => link.episodeTitle).toList(), <String>[
          '第1话',
          '第2话',
          '第3话',
        ]);
        expect(discovery.requestedTids, <String>['568759', '571256', '570088']);
      },
    );

    test(
      'merges unique search episodes even when discovery returns more links',
      () async {
        final discovery = _FakeDiscoveryService(
          byTid: <String, List<ComicEpisodeLink>>{
            '900': const <ComicEpisodeLink>[],
            '304': const <ComicEpisodeLink>[
              ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '第1话'),
              ComicEpisodeLink(url: 'thread-102-1-1.html', rawText: '第2话'),
              ComicEpisodeLink(url: 'thread-103-1-1.html', rawText: '第3话'),
            ],
            '305': const <ComicEpisodeLink>[],
          },
        );
        final searchService = _FakeDiscuzSearchService(
          response: const DiscuzSearchResponse(
            items: <DiscuzSearchResultItem>[
              DiscuzSearchResultItem(
                tid: '304',
                title: '测试漫画 第4话',
                url: 'https://bbs.yamibo.com/thread-304-1-1.html',
                fid: '30',
              ),
              DiscuzSearchResultItem(
                tid: '305',
                title: '测试漫画 第5话',
                url: 'https://bbs.yamibo.com/thread-305-1-1.html',
                fid: '30',
              ),
            ],
            rateLimited: false,
          ),
        );
        final service = _buildService(
          discoveryService: discovery,
          searchService: searchService,
          subjectParser: const RuleBasedComicSubjectParser(),
          threadSeedFetcher: (_) async {
            return const ThreadSeed(subject: '测试漫画 第3话');
          },
        );

        final links = await service.fetchEpisodeLinksFromTid('900');

        expect(
          links.map((link) => link.episodeTitle ?? link.rawText).toList(),
          <String>['第1话', '第2话', '第3话', '第4话', '第5话'],
        );
      },
    );

    test(
      'searches once and merges when current tid only has older direct links',
      () async {
        final discovery = _FakeDiscoveryService(
          byTid: <String, List<ComicEpisodeLink>>{
            '100': const <ComicEpisodeLink>[
              ComicEpisodeLink(url: 'thread-90-1-1.html', rawText: '上一话'),
            ],
            '301': const <ComicEpisodeLink>[
              ComicEpisodeLink(url: 'thread-90-1-1.html', rawText: '第13话'),
              ComicEpisodeLink(url: 'thread-100-1-1.html', rawText: '第14话'),
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
        final service = _buildService(
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
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=301',
        ]);
        expect(links.first.rawText, '第13话');
      },
    );

    test('search keyword uses clean book name from the new parser', () async {
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
      final service = _buildService(
        discoveryService: discovery,
        searchService: searchService,
        subjectParser: const RuleBasedComicSubjectParser(),
        threadSeedFetcher: (_) async {
          return const ThreadSeed(subject: '[汉化组]漫画标题 Vol.2');
        },
      );

      await service.fetchEpisodeLinksFromTid('100');

      expect(searchService.calledKeywords, <String>['漫画标题']);
    });

    test(
      'search fallback avoids rediscovering current tid but keeps it as an episode',
      () async {
        final discovery = _FakeDiscoveryService(
          byTid: <String, List<ComicEpisodeLink>>{
            '100': const <ComicEpisodeLink>[
              ComicEpisodeLink(url: 'thread-90-1-1.html', rawText: '上一话'),
            ],
            '301': const <ComicEpisodeLink>[
              ComicEpisodeLink(url: 'thread-90-1-1.html', rawText: '第13话'),
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
        final service = _buildService(
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
        expect(links.map((link) => link.episodeTitle ?? link.rawText), <String>[
          '第13话',
          '第14话',
          '第15话',
        ]);
      },
    );

    test(
      'normalizes display title before using it as search keyword',
      () async {
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
        final service = _buildService(
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
      },
    );

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
      final service = _buildService(
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
      final service = _buildService(
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
      final service = _buildService(
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
      final service = _buildService(
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

    test(
      'search-and-current-only returns search outcome and skips current catalog fallback',
      () async {
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
        final service = _buildService(
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
        expect(
          outcome.links.map((link) => link.url),
          contains('thread-101-1-1.html'),
        );
        expect(discovery.catalogFallbackAllowedByTid['100'], isFalse);
      },
    );

    test(
      'catalog-only reuses preloaded root detail without root discovery request',
      () async {
        final discovery = _FakeDiscoveryService(
          byTid: <String, List<ComicEpisodeLink>>{
            '301': const <ComicEpisodeLink>[
              ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '第1话'),
            ],
          },
          directLinksByTid: <String, List<ComicEpisodeLink>>{
            '100': const <ComicEpisodeLink>[
              ComicEpisodeLink(url: 'thread-301-1-1.html', rawText: '上一话'),
            ],
          },
          strategyByTid: const <String, EpisodeDiscoveryStrategy>{
            '100': EpisodeDiscoveryStrategy.direct,
          },
        );
        final service = _buildService(
          discoveryService: discovery,
          searchService: _FakeDiscuzSearchService(
            response: const DiscuzSearchResponse(
              items: <DiscuzSearchResultItem>[],
              rateLimited: false,
            ),
          ),
        );

        final outcome = await service.fetchCatalogOnly(
          const ComicEpisodeRefreshRequest(sourceTid: '100'),
          preloadedRootDetail: _threadDetail(
            tid: '100',
            subject: '测试漫画 第1话',
            message:
                '<a href="https://bbs.yamibo.com/forum.php?mod=viewthread&tid=301">上一话</a>',
          ),
        );

        expect(outcome.source, ComicEpisodeRefreshSource.empty);
        expect(discovery.requestedTids, isEmpty);
        expect(discovery.preloadedTids, <String>['100']);
      },
    );

    test(
      'search-and-current-only reuses preloaded root detail and skips threadSeedFetcher',
      () async {
        final discovery = _FakeDiscoveryService(
          byTid: <String, List<ComicEpisodeLink>>{
            '301': const <ComicEpisodeLink>[
              ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '第1话'),
            ],
          },
          directLinksByTid: <String, List<ComicEpisodeLink>>{
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
                title: '测试漫画 第1话',
                url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=301',
                fid: '30',
              ),
            ],
            rateLimited: false,
          ),
        );
        var threadSeedFetchCount = 0;
        final service = _buildService(
          discoveryService: discovery,
          searchService: searchService,
          subjectParser: const RuleBasedComicSubjectParser(),
          threadSeedFetcher: (_) async {
            threadSeedFetchCount++;
            return const ThreadSeed(subject: '不会被使用');
          },
        );

        final outcome = await service.fetchSearchAndCurrentOnly(
          const ComicEpisodeRefreshRequest(sourceTid: '100'),
          preloadedRootDetail: _threadDetail(
            tid: '100',
            subject: '测试漫画 第2话',
            message:
                '<a href="https://bbs.yamibo.com/forum.php?mod=viewthread&tid=301">上一话</a>',
          ),
        );

        expect(outcome.source, ComicEpisodeRefreshSource.search);
        expect(outcome.links, isNotEmpty);
        expect(threadSeedFetchCount, 0);
        expect(searchService.calledKeywords, <String>['测试漫画']);
        expect(discovery.requestedTids, <String>['301']);
        expect(discovery.preloadedTids, <String>['100']);
      },
    );

    test(
      'catalog-then-fallback returns catalog outcome when catalog matches',
      () async {
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
        final service = _buildService(
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
      },
    );

    test(
      'catalog-then-fallback returns search outcome when catalog misses',
      () async {
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
        final service = _buildService(
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
      },
    );

    test(
      'catalog-then-fallback returns current-only outcome when search misses',
      () async {
        final discovery = _FakeDiscoveryService(
          byTid: <String, List<ComicEpisodeLink>>{
            '100': const <ComicEpisodeLink>[
              ComicEpisodeLink(url: 'thread-100-1-1.html', rawText: 'EP 01'),
            ],
          },
        );
        final service = _buildService(
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
      },
    );

    test(
      'catalog-then-fallback returns empty outcome when nothing is found',
      () async {
        final discovery = _FakeDiscoveryService(
          byTid: <String, List<ComicEpisodeLink>>{
            '100': const <ComicEpisodeLink>[],
          },
        );
        final service = _buildService(
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
      },
    );

    test('catalog hit does not consult extracted search strategies', () async {
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
      final keywordResolver = _RecordingKeywordResolver();
      final candidateRanker = _RecordingCandidateRanker();
      final linkMerger = _RecordingEpisodeLinkMerger();
      final service = _buildService(
        discoveryService: discovery,
        searchService: _FakeDiscuzSearchService(
          response: const DiscuzSearchResponse(
            items: <DiscuzSearchResultItem>[],
            rateLimited: false,
          ),
        ),
        keywordResolver: keywordResolver,
        candidateRanker: candidateRanker,
        episodeLinkMerger: linkMerger,
      );

      final outcome = await service.fetchCatalogThenFallback(
        const ComicEpisodeRefreshRequest(sourceTid: '100'),
      );

      expect(outcome.source, ComicEpisodeRefreshSource.catalog);
      expect(keywordResolver.callCount, 0);
      expect(candidateRanker.callCount, 0);
      expect(linkMerger.mergeCallCount, 0);
      expect(linkMerger.fromSearchCandidatesCallCount, 0);
      expect(linkMerger.sortCallCount, 0);
    });

    test(
      'catalog miss delegates fallback to resolver ranker and merger',
      () async {
        const searchItem = DiscuzSearchResultItem(
          tid: '301',
          title: '测试漫画 第2话',
          url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=301',
          fid: '30',
        );
        final discovery = _FakeDiscoveryService(
          byTid: <String, List<ComicEpisodeLink>>{
            '100': const <ComicEpisodeLink>[
              ComicEpisodeLink(url: 'thread-100-1-1.html', rawText: '第1话'),
            ],
            '301': const <ComicEpisodeLink>[
              ComicEpisodeLink(url: 'thread-301-1-1.html', rawText: '第2话'),
            ],
          },
        );
        final keywordResolver = _RecordingKeywordResolver(
          keywords: const <ComicRefreshKeyword>[
            ComicRefreshKeyword(
              source: ComicRefreshKeywordSource.customTitle,
              value: '测试漫画',
            ),
          ],
        );
        final candidateRanker = _RecordingCandidateRanker(
          candidates: const <ComicSearchCandidate>[
            ComicSearchCandidate(item: searchItem, score: 1, searchIndex: 0),
          ],
        );
        final linkMerger = _RecordingEpisodeLinkMerger();
        final searchService = _FakeDiscuzSearchService(
          response: const DiscuzSearchResponse(
            items: <DiscuzSearchResultItem>[searchItem],
            rateLimited: false,
          ),
        );
        final service = _buildService(
          discoveryService: discovery,
          searchService: searchService,
          keywordResolver: keywordResolver,
          candidateRanker: candidateRanker,
          episodeLinkMerger: linkMerger,
          threadSeedFetcher: (_) async {
            return const ThreadSeed(subject: '测试漫画 第1话');
          },
        );

        final outcome = await service.fetchCatalogThenFallback(
          const ComicEpisodeRefreshRequest(
            sourceTid: '100',
            customTitle: '测试漫画',
          ),
        );

        expect(outcome.source, ComicEpisodeRefreshSource.search);
        expect(searchService.calledKeywords, <String>['测试漫画']);
        expect(keywordResolver.callCount, 1);
        expect(keywordResolver.lastRequest?.sourceTid, '100');
        expect(keywordResolver.lastSubject, '测试漫画 第1话');
        expect(candidateRanker.callCount, 1);
        expect(candidateRanker.lastThreadSubject, '测试漫画 第1话');
        expect(candidateRanker.lastKeyword?.value, '测试漫画');
        expect(
          candidateRanker.lastItems.map((item) => item.tid).toList(),
          <String>['301'],
        );
        expect(linkMerger.fromSearchCandidatesCallCount, 1);
        expect(linkMerger.sortCallCount, 1);
        expect(linkMerger.mergeCallCount, greaterThanOrEqualTo(2));
      },
    );

    test(
      'catalog miss preserves catalogUrl discovered from search candidate',
      () async {
        const candidateCatalogUrl =
            'https://bbs.yamibo.com/misc.php?mod=tag&id=18235';
        const searchItem = DiscuzSearchResultItem(
          tid: '301',
          title: '测试漫画 第2话',
          url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=301',
          fid: '30',
        );
        final discovery = _FakeDiscoveryService(
          byTid: <String, List<ComicEpisodeLink>>{
            '100': const <ComicEpisodeLink>[],
            '301': const <ComicEpisodeLink>[
              ComicEpisodeLink(url: 'thread-301-1-1.html', rawText: '第1话'),
              ComicEpisodeLink(url: 'thread-302-1-1.html', rawText: '第2话'),
            ],
          },
          catalogUrlByTid: const <String, String>{'301': candidateCatalogUrl},
        );
        final searchService = _FakeDiscuzSearchService(
          response: const DiscuzSearchResponse(
            items: <DiscuzSearchResultItem>[searchItem],
            rateLimited: false,
          ),
        );
        final service = _buildService(
          discoveryService: discovery,
          searchService: searchService,
          threadSeedFetcher: (_) async {
            return const ThreadSeed(subject: '测试漫画 第1话');
          },
        );

        final outcome = await service.fetchSearchAndCurrentOnly(
          const ComicEpisodeRefreshRequest(
            sourceTid: '100',
            customTitle: '测试漫画',
          ),
        );

        expect(outcome.source, ComicEpisodeRefreshSource.search);
        expect(outcome.catalogUrl, candidateCatalogUrl);
      },
    );

    test(
      'fetchCatalogDirect returns catalog outcome when links found',
      () async {
        final discovery = _FakeDiscoveryService(
          byTid: <String, List<ComicEpisodeLink>>{},
          byCatalogUrl: <String, List<ComicEpisodeLink>>{
            'https://bbs.yamibo.com/misc.php?mod=tag&id=123':
                const <ComicEpisodeLink>[
                  ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '第1话'),
                  ComicEpisodeLink(url: 'thread-102-1-1.html', rawText: '第2话'),
                ],
          },
        );
        final service = _buildService(
          discoveryService: discovery,
          searchService: _FakeDiscuzSearchService(
            response: const DiscuzSearchResponse(
              items: <DiscuzSearchResultItem>[],
              rateLimited: false,
            ),
          ),
        );

        final outcome = await service.fetchCatalogDirect(
          'https://bbs.yamibo.com/misc.php?mod=tag&id=123',
        );

        expect(outcome.catalogMatched, isTrue);
        expect(outcome.hasLinks, isTrue);
        expect(outcome.source, ComicEpisodeRefreshSource.catalog);
        expect(outcome.links, hasLength(2));
        expect(
          outcome.catalogUrl,
          'https://bbs.yamibo.com/misc.php?mod=tag&id=123',
        );
        expect(
          discovery.requestedCatalogUrls,
          contains('https://bbs.yamibo.com/misc.php?mod=tag&id=123'),
        );
      },
    );

    test(
      'fetchCatalogDirect returns empty when catalog has no links',
      () async {
        final discovery = _FakeDiscoveryService(
          byTid: <String, List<ComicEpisodeLink>>{},
          byCatalogUrl: <String, List<ComicEpisodeLink>>{},
        );
        final service = _buildService(
          discoveryService: discovery,
          searchService: _FakeDiscuzSearchService(
            response: const DiscuzSearchResponse(
              items: <DiscuzSearchResultItem>[],
              rateLimited: false,
            ),
          ),
        );

        final outcome = await service.fetchCatalogDirect(
          'https://bbs.yamibo.com/misc.php?mod=tag&id=999',
        );

        expect(outcome.catalogMatched, isFalse);
        expect(outcome.hasLinks, isFalse);
        expect(outcome.source, ComicEpisodeRefreshSource.empty);
        expect(
          outcome.catalogUrl,
          'https://bbs.yamibo.com/misc.php?mod=tag&id=999',
        );
      },
    );
  });
}

NetworkComicEpisodeRefreshService _buildService({
  required ComicEpisodeDiscoveryService discoveryService,
  required ForumSearchService searchService,
  ComicSubjectParser subjectParser = const RuleBasedComicSubjectParser(),
  ComicReaderFeatureFlags featureFlags = ComicReaderFeatureFlags.defaults,
  ThreadSeedFetcher? threadSeedFetcher,
  ComicRefreshKeywordResolver? keywordResolver,
  ComicSearchCandidateRanker? candidateRanker,
  ComicEpisodeLinkMerger? episodeLinkMerger,
}) {
  final resolvedSubjectParser = subjectParser;
  return NetworkComicEpisodeRefreshService(
    discoveryService: discoveryService,
    searchService: searchService,
    keywordResolver:
        keywordResolver ??
        DefaultComicRefreshKeywordResolver(
          subjectParser: resolvedSubjectParser,
          featureFlags: featureFlags,
        ),
    candidateRanker:
        candidateRanker ?? const DefaultComicSearchCandidateRanker(),
    episodeLinkMerger:
        episodeLinkMerger ??
        DefaultComicEpisodeLinkMerger(subjectParser: resolvedSubjectParser),
    threadSeedFetcher: threadSeedFetcher,
  );
}

class _FakeDiscoveryService extends ComicEpisodeDiscoveryService {
  _FakeDiscoveryService({
    required this.byTid,
    this.strategyByTid = const <String, EpisodeDiscoveryStrategy>{},
    this.catalogUrlByTid = const <String, String>{},
    this.byCatalogUrl = const <String, List<ComicEpisodeLink>>{},
    this.directLinksByTid = const <String, List<ComicEpisodeLink>>{},
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
  final Map<String, String> catalogUrlByTid;
  final Map<String, List<ComicEpisodeLink>> byCatalogUrl;
  final Map<String, List<ComicEpisodeLink>> directLinksByTid;
  final List<String> requestedTids = <String>[];
  final List<String> requestedCatalogUrls = <String>[];
  final List<String> preloadedTids = <String>[];
  final Map<String, bool> catalogFallbackAllowedByTid = <String, bool>{};

  @override
  Future<EpisodeDiscoveryResult> discoverFromTid(String tid) async {
    requestedTids.add(tid);
    return EpisodeDiscoveryResult(
      strategy: strategyByTid[tid] ?? EpisodeDiscoveryStrategy.direct,
      episodeLinks: byTid[tid] ?? const <ComicEpisodeLink>[],
      catalogUrl: catalogUrlByTid[tid],
    );
  }

  @override
  Future<EpisodeDiscoveryResult> discoverFromTidWithPreference({
    required String tid,
    required bool preferCatalogFirst,
    bool allowCatalogFallback = true,
    FavoriteFirstSyncRequestGovernor? governor,
    ThreadDetailData? preloadedRootDetail,
    ComicThreadDetailCache? threadCache,
  }) async {
    if (preloadedRootDetail != null && preloadedRootDetail.tid == tid) {
      preloadedTids.add(tid);
    } else {
      requestedTids.add(tid);
    }
    catalogFallbackAllowedByTid[tid] = allowCatalogFallback;
    return EpisodeDiscoveryResult(
      strategy: strategyByTid[tid] ?? EpisodeDiscoveryStrategy.direct,
      episodeLinks:
          preloadedRootDetail != null && preloadedRootDetail.tid == tid
          ? directLinksByTid[tid] ?? const <ComicEpisodeLink>[]
          : byTid[tid] ?? const <ComicEpisodeLink>[],
      catalogUrl: catalogUrlByTid[tid],
    );
  }

  @override
  Future<List<ComicEpisodeLink>> discoverFromCatalogUrl(
    String catalogUrl, {
    FavoriteFirstSyncRequestGovernor? governor,
  }) async {
    requestedCatalogUrls.add(catalogUrl);
    return byCatalogUrl[catalogUrl] ?? const <ComicEpisodeLink>[];
  }
}

class _NoopCatalogHtmlFetcher implements CatalogHtmlFetcher {
  @override
  Future<String?> fetchHtml(String url) async {
    return null;
  }
}

class _FakeDiscuzSearchService implements ForumSearchService {
  _FakeDiscuzSearchService({required DiscuzSearchResponse response})
    : _response = response;

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

ThreadDetailData _threadDetail({
  required String tid,
  required String subject,
  required String message,
}) {
  return ThreadDetailData(
    tid: tid,
    fid: '30',
    typeid: '398',
    subject: subject,
    author: 'Author',
    replies: 0,
    views: 1,
    currentPage: 1,
    perPage: 20,
    posts: <ThreadPost>[
      ThreadPost(
        pid: 'p1',
        author: 'Author',
        authorId: '1',
        message: message,
        number: 1,
        isFirst: true,
        dateline: '2026-01-01',
      ),
    ],
  );
}

class _SequencedDiscuzSearchService implements ForumSearchService {
  _SequencedDiscuzSearchService({required List<DiscuzSearchResponse> responses})
    : _responses = responses;

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

class _RecordingKeywordResolver implements ComicRefreshKeywordResolver {
  _RecordingKeywordResolver({
    List<ComicRefreshKeyword> keywords = const <ComicRefreshKeyword>[],
  }) : _keywords = keywords;

  final List<ComicRefreshKeyword> _keywords;
  int callCount = 0;
  ComicEpisodeRefreshRequest? lastRequest;
  String? lastSubject;

  @override
  List<ComicRefreshKeyword> resolve(
    ComicEpisodeRefreshRequest request,
    String subject,
  ) {
    callCount++;
    lastRequest = request;
    lastSubject = subject;
    return _keywords;
  }
}

class _RecordingCandidateRanker implements ComicSearchCandidateRanker {
  _RecordingCandidateRanker({this.candidates = const <ComicSearchCandidate>[]});

  final List<ComicSearchCandidate> candidates;

  @override
  int get discoveryTopK => 3;

  int callCount = 0;
  String? lastThreadSubject;
  ComicRefreshKeyword? lastKeyword;
  List<DiscuzSearchResultItem> lastItems = const <DiscuzSearchResultItem>[];

  @override
  List<ComicSearchCandidate> rank({
    required String threadSubject,
    required ComicRefreshKeyword keyword,
    required List<DiscuzSearchResultItem> items,
  }) {
    callCount++;
    lastThreadSubject = threadSubject;
    lastKeyword = keyword;
    lastItems = items;
    return candidates;
  }
}

class _RecordingEpisodeLinkMerger implements ComicEpisodeLinkMerger {
  _RecordingEpisodeLinkMerger()
    : _delegate = DefaultComicEpisodeLinkMerger(
        subjectParser: const RuleBasedComicSubjectParser(),
      );

  final DefaultComicEpisodeLinkMerger _delegate;
  int mergeCallCount = 0;
  int sortCallCount = 0;
  int fromSearchCandidatesCallCount = 0;

  @override
  List<ComicEpisodeLink> fromSearchCandidates(
    List<ComicSearchCandidate> candidates,
  ) {
    fromSearchCandidatesCallCount++;
    return _delegate.fromSearchCandidates(candidates);
  }

  @override
  List<ComicEpisodeLink> merge(
    List<ComicEpisodeLink> primary,
    List<ComicEpisodeLink> supplement, {
    bool preferSupplement = false,
  }) {
    mergeCallCount++;
    return _delegate.merge(
      primary,
      supplement,
      preferSupplement: preferSupplement,
    );
  }

  @override
  List<ComicEpisodeLink> sort(List<ComicEpisodeLink> links) {
    sortCallCount++;
    return _delegate.sort(links);
  }
}

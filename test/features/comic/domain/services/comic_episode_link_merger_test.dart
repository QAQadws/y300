import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_episode_link_merger.dart';
import 'package:y300/features/comic/domain/services/comic_search_candidate_ranker.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';

void main() {
  group('DefaultComicEpisodeLinkMerger', () {
    final merger = DefaultComicEpisodeLinkMerger(
      subjectParser: const RuleBasedComicSubjectParser(),
    );

    test('deduplicates by tid identity across query and thread urls', () {
      final merged = merger.merge(
        const <ComicEpisodeLink>[
          ComicEpisodeLink(
            url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100',
            rawText: '旧标题',
          ),
        ],
        const <ComicEpisodeLink>[
          ComicEpisodeLink(url: 'thread-100-1-1.html', rawText: '新标题'),
          ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '第2话'),
        ],
      );

      expect(merged, hasLength(2));
      expect(merged.first.rawText, '旧标题');
      expect(merged.last.url, 'thread-101-1-1.html');
    });

    test('preferSupplement replaces existing duplicate entry', () {
      final merged = merger.merge(
        const <ComicEpisodeLink>[
          ComicEpisodeLink(
            url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100',
            rawText: '旧标题',
          ),
        ],
        const <ComicEpisodeLink>[
          ComicEpisodeLink(url: 'thread-100-1-1.html', rawText: '补全标题'),
        ],
        preferSupplement: true,
      );

      expect(merged, hasLength(1));
      expect(merged.single.rawText, '补全标题');
    });

    test('fromSearchCandidates keeps every explicit episode candidate', () {
      final links = merger.fromSearchCandidates(const <ComicSearchCandidate>[
        ComicSearchCandidate(
          item: DiscuzSearchResultItem(
            tid: '100',
            title: '测试漫画 第80话',
            url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100',
            fid: '30',
          ),
          score: 1,
          searchIndex: 0,
        ),
        ComicSearchCandidate(
          item: DiscuzSearchResultItem(
            tid: '502780',
            title: '[百合會]测试漫画第82话上',
            url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=502780',
            fid: '30',
          ),
          score: 0.9,
          searchIndex: 1,
        ),
        ComicSearchCandidate(
          item: DiscuzSearchResultItem(
            tid: '503102',
            title: '[百合會]测试漫画第82话下',
            url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=503102',
            fid: '30',
          ),
          score: 0.9,
          searchIndex: 2,
        ),
        ComicSearchCandidate(
          item: DiscuzSearchResultItem(
            tid: '502128',
            title: '[百合會]测试漫画第81话',
            url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=502128',
            fid: '30',
          ),
          score: 0.9,
          searchIndex: 3,
        ),
      ]);

      expect(links.map((link) => link.url).toList(), <String>[
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100',
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=502128',
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=502780',
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=503102',
      ]);
      expect(links.map((link) => link.episodeTitle).toList(), <String>[
        '第80话',
        '第81话',
        '第82话上',
        '第82话下',
      ]);
    });

    test('fromSearchCandidates rejects non-episode work entries', () {
      final links = merger.fromSearchCandidates(const <ComicSearchCandidate>[
        ComicSearchCandidate(
          item: DiscuzSearchResultItem(
            tid: '100',
            title: '测试漫画 目录合集',
            url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100',
            fid: '30',
          ),
          score: 1,
          searchIndex: 0,
        ),
        ComicSearchCandidate(
          item: DiscuzSearchResultItem(
            tid: '101',
            title: '测试漫画 第1话',
            url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=101',
            fid: '30',
          ),
          score: 1,
          searchIndex: 1,
        ),
      ]);

      expect(links, hasLength(1));
      expect(links.single.url, contains('tid=101'));
      expect(links.single.episodeTitle, '第1话');
    });

    test('sort keeps numbered chapters before extras', () {
      final sorted = merger.sort(const <ComicEpisodeLink>[
        ComicEpisodeLink(url: 'thread-4-1-1.html', rawText: '番外'),
        ComicEpisodeLink(url: 'thread-3-1-1.html', rawText: '第2话下'),
        ComicEpisodeLink(url: 'thread-1-1-1.html', rawText: '第1话'),
        ComicEpisodeLink(url: 'thread-2-1-1.html', rawText: '第2话上'),
      ]);

      expect(sorted.map((link) => link.rawText).toList(), <String>[
        '第1话',
        '第2话上',
        '第2话下',
        '番外',
      ]);
    });
  });
}

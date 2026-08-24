import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_keyword_resolver.dart';
import 'package:y300/features/comic/domain/services/comic_search_candidate_ranker.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

void main() {
  group('DefaultComicSearchCandidateRanker', () {
    test('filters out candidates below adaptive threshold', () {
      const ranker = DefaultComicSearchCandidateRanker();

      final candidates = ranker.rank(
        threadSubject: 'abc 第1话',
        keyword: const ComicRefreshKeyword(
          source: ComicRefreshKeywordSource.customTitle,
          value: 'abc',
        ),
        items: const <ForumSearchTopicSummary>[
          ForumSearchTopicSummary(tid: '301', title: 'abc 第2话'),
          ForumSearchTopicSummary(tid: '302', title: 'abd 第2话'),
        ],
      );

      expect(candidates, hasLength(1));
      expect(candidates.single.tid, '301');
    });

    test('keeps score desc then search index asc ordering', () {
      const ranker = DefaultComicSearchCandidateRanker();

      final candidates = ranker.rank(
        threadSubject: 'abc 第1话',
        keyword: const ComicRefreshKeyword(
          source: ComicRefreshKeywordSource.customTitle,
          value: 'abc',
        ),
        items: const <ForumSearchTopicSummary>[
          ForumSearchTopicSummary(tid: '401', title: 'abc 特典'),
          ForumSearchTopicSummary(tid: '402', title: 'abc 第2话'),
          ForumSearchTopicSummary(tid: '403', title: 'ab 第2话'),
        ],
      );

      expect(candidates.map((candidate) => candidate.tid).toList(), <String>[
        '401',
        '402',
      ]);
      expect(candidates.first.searchIndex, 0);
      expect(candidates.last.searchIndex, 1);
    });

    test('uses 0.50 floor when current subject score is zero', () {
      const ranker = DefaultComicSearchCandidateRanker();

      final candidates = ranker.rank(
        threadSubject: 'zzz',
        keyword: const ComicRefreshKeyword(
          source: ComicRefreshKeywordSource.customTitle,
          value: 'abc',
        ),
        items: const <ForumSearchTopicSummary>[
          ForumSearchTopicSummary(tid: '501', title: 'abd'),
          ForumSearchTopicSummary(tid: '502', title: 'qqq'),
        ],
      );

      expect(candidates.map((candidate) => candidate.tid), <String>['501']);
    });

    test('exposes discoveryTopK as 3 by default', () {
      const ranker = DefaultComicSearchCandidateRanker();

      expect(ranker.discoveryTopK, 3);
    });
  });
}

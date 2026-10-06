import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_search_candidate_ranker.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

void main() {
  group('DefaultComicSearchCandidateRanker', () {
    test('keeps all server matches without filtering titles', () {
      const ranker = DefaultComicSearchCandidateRanker();

      final candidates = ranker.rank(
        items: const <ForumSearchTopicSummary>[
          ForumSearchTopicSummary(tid: '301', title: 'abc 第2话'),
          ForumSearchTopicSummary(tid: '302', title: '完全不同的标题 第1话'),
        ],
      );

      expect(candidates.map((candidate) => candidate.tid), ['302', '301']);
      expect(candidates.first.title, '完全不同的标题 第1话');
    });

    test('orders the whole page by numeric tid descending', () {
      const ranker = DefaultComicSearchCandidateRanker();

      final candidates = ranker.rank(
        items: const <ForumSearchTopicSummary>[
          ForumSearchTopicSummary(tid: '9', title: '测试漫画 第1话'),
          ForumSearchTopicSummary(tid: '700', title: '测试漫画 第3话'),
          ForumSearchTopicSummary(tid: '80', title: '测试漫画 第2话'),
          ForumSearchTopicSummary(tid: '6000', title: '测试漫画 第4话'),
        ],
      );

      expect(candidates.map((candidate) => candidate.tid).toList(), <String>[
        '6000',
        '700',
        '80',
        '9',
      ]);
      expect(candidates.map((candidate) => candidate.searchIndex), [
        3,
        1,
        2,
        0,
      ]);
    });

    test('normalizes tids and preserves search order for equal tids', () {
      const ranker = DefaultComicSearchCandidateRanker();

      final candidates = ranker.rank(
        items: const <ForumSearchTopicSummary>[
          ForumSearchTopicSummary(tid: ' 401 ', title: '测试漫画 第1话'),
          ForumSearchTopicSummary(tid: '401', title: '测试漫画 第一话'),
        ],
      );

      expect(candidates.map((candidate) => candidate.tid), ['401', '401']);
      expect(candidates.map((candidate) => candidate.searchIndex), [0, 1]);
    });

    test('exposes discoveryTopK as 3 by default', () {
      const ranker = DefaultComicSearchCandidateRanker();

      expect(ranker.discoveryTopK, 3);
    });
  });
}

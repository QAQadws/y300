import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_keyword_resolver.dart';
import 'package:y300/features/comic/domain/services/comic_search_candidate_ranker.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';

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
        items: const <DiscuzSearchResultItem>[
          DiscuzSearchResultItem(
            tid: '301',
            title: 'abc 第2话',
            url: 'https://example.com/301',
            fid: '30',
          ),
          DiscuzSearchResultItem(
            tid: '302',
            title: 'abd 第2话',
            url: 'https://example.com/302',
            fid: '30',
          ),
        ],
      );

      expect(candidates, hasLength(1));
      expect(candidates.single.item.tid, '301');
    });

    test('keeps score desc then search index asc ordering', () {
      const ranker = DefaultComicSearchCandidateRanker();

      final candidates = ranker.rank(
        threadSubject: 'abc 第1话',
        keyword: const ComicRefreshKeyword(
          source: ComicRefreshKeywordSource.customTitle,
          value: 'abc',
        ),
        items: const <DiscuzSearchResultItem>[
          DiscuzSearchResultItem(
            tid: '401',
            title: 'abc 特典',
            url: 'https://example.com/401',
            fid: '30',
          ),
          DiscuzSearchResultItem(
            tid: '402',
            title: 'abc 第2话',
            url: 'https://example.com/402',
            fid: '30',
          ),
          DiscuzSearchResultItem(
            tid: '403',
            title: 'ab 第2话',
            url: 'https://example.com/403',
            fid: '30',
          ),
        ],
      );

      expect(
        candidates.map((candidate) => candidate.item.tid).toList(),
        <String>['401', '402'],
      );
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
        items: const <DiscuzSearchResultItem>[
          DiscuzSearchResultItem(
            tid: '501',
            title: 'abd',
            url: 'https://example.com/501',
            fid: '30',
          ),
          DiscuzSearchResultItem(
            tid: '502',
            title: 'qqq',
            url: 'https://example.com/502',
            fid: '30',
          ),
        ],
      );

      expect(
        candidates.map((candidate) => candidate.item.tid).toList(),
        <String>['501'],
      );
    });

    test('exposes discoveryTopK as 3 by default', () {
      const ranker = DefaultComicSearchCandidateRanker();

      expect(ranker.discoveryTopK, 3);
    });
  });
}

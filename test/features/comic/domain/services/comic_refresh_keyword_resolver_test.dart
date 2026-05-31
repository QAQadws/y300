import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_episode_refresh_service.dart';
import 'package:y300/features/comic/domain/services/comic_reader_feature_flags.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_keyword_resolver.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';

void main() {
  group('DefaultComicRefreshKeywordResolver current baseline', () {
    test('uses custom search title before lower priority fields', () {
      final resolver = DefaultComicRefreshKeywordResolver(
        subjectParser: const RuleBasedComicSubjectParser(),
      );

      final keywords = resolver.resolve(
        const ComicEpisodeRefreshRequest(
          sourceTid: '100',
          customSearchTitle: 'Actual Search Title',
          customTitle: 'Custom Title',
          displayTitle: '[Favorite] Display Title EP 02',
          sourceTitle: '[Scan] Source Title EP 01',
        ),
        '[Thread] Current Title EP 03',
      );

      expect(keywords, hasLength(1));
      expect(keywords.single.value, 'Actual Search Title');
      expect(
        keywords.single.source,
        ComicRefreshKeywordSource.customSearchTitle,
      );
    });

    test('single keyword mode stops after first non-empty choice', () {
      final resolver = DefaultComicRefreshKeywordResolver(
        subjectParser: const RuleBasedComicSubjectParser(),
      );

      final keywords = resolver.resolve(
        const ComicEpisodeRefreshRequest(
          sourceTid: '100',
          customSearchTitle: '   ',
          customTitle: 'Custom Title',
          sourceTitle: 'Source Title',
        ),
        'Current Title',
      );

      expect(
        keywords.map((keyword) => keyword.value).toList(),
        <String>['Custom Title'],
      );
      expect(
        keywords.single.source,
        ComicRefreshKeywordSource.customTitle,
      );
    });

    test('multi-keyword mode keeps priority order and removes duplicates', () {
      final resolver = DefaultComicRefreshKeywordResolver(
        subjectParser: const RuleBasedComicSubjectParser(),
        featureFlags: ComicReaderFeatureFlags.defaults.copyWith(
          readerRefreshMultiKeywordEnabled: true,
        ),
      );

      final keywords = resolver.resolve(
        const ComicEpisodeRefreshRequest(
          sourceTid: '100',
          customSearchTitle: 'Primary Keyword',
          customTitle: 'Primary Keyword',
          displayTitle: '[Favorite] Display Title EP 02',
          sourceTitle: '[Scan] Display Title EP 01',
        ),
        '[Thread] Current Title EP 03',
      );

      expect(
        keywords.map((keyword) => keyword.value).toList(),
        <String>['Primary Keyword', 'Display Title', 'Current Title'],
      );
      expect(
        keywords.map((keyword) => keyword.source).toList(),
        <ComicRefreshKeywordSource>[
          ComicRefreshKeywordSource.customSearchTitle,
          ComicRefreshKeywordSource.displayTitle,
          ComicRefreshKeywordSource.subjectNormalized,
        ],
      );
    });

    test('falls back to raw title when parser only returns the trimmed input', () {
      final resolver = DefaultComicRefreshKeywordResolver(
        subjectParser: const RuleBasedComicSubjectParser(),
        featureFlags: ComicReaderFeatureFlags.defaults.copyWith(
          readerRefreshMultiKeywordEnabled: true,
        ),
      );

      final keywords = resolver.resolve(
        const ComicEpisodeRefreshRequest(
          sourceTid: '100',
          displayTitle: 'Original Title',
        ),
        'Another Raw Title',
      );

      expect(
        keywords.map((keyword) => keyword.value).toList(),
        <String>['Original Title', 'Another Raw Title'],
      );
    });

    test('keeps current parser noise when only light cleaning applies', () {
      final resolver = DefaultComicRefreshKeywordResolver(
        subjectParser: const RuleBasedComicSubjectParser(),
      );

      final keywords = resolver.resolve(
        const ComicEpisodeRefreshRequest(
          sourceTid: '100',
          displayTitle: '[Scan] Noisy Title Vol.2',
        ),
        'Unused Subject',
      );

      expect(keywords, hasLength(1));
      expect(
        keywords.single.value,
        'Noisy Title Vol.2',
      );
      expect(
        keywords.single.source,
        ComicRefreshKeywordSource.displayTitle,
      );
    });
  });
}

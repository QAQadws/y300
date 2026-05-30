import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_episode_refresh_service.dart';
import 'package:y300/features/comic/domain/services/comic_reader_feature_flags.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_keyword_resolver.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';

void main() {
  group('DefaultComicRefreshKeywordResolver', () {
    test('uses custom search title before lower priority fields', () {
      final resolver = DefaultComicRefreshKeywordResolver(
        subjectParser: const RuleBasedComicSubjectParser(),
      );

      final keywords = resolver.resolve(
        const ComicEpisodeRefreshRequest(
          sourceTid: '100',
          customSearchTitle: '真正标题',
          customTitle: '自定义标题',
          displayTitle: '[Favorite] 展示标题 EP 02',
          sourceTitle: '[Scan] 来源标题 EP 01',
        ),
        '[Thread] 当前标题 EP 03',
      );

      expect(keywords, hasLength(1));
      expect(keywords.single.value, '真正标题');
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
          customTitle: '自定义标题',
          sourceTitle: '来源标题',
        ),
        '当前标题',
      );

      expect(
        keywords.map((keyword) => keyword.value).toList(),
        <String>['自定义标题'],
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
          customSearchTitle: '主关键字',
          customTitle: '主关键字',
          displayTitle: '[Favorite] 展示标题 EP 02',
          sourceTitle: '[Scan] 展示标题 EP 01',
        ),
        '[Thread] 当前标题 EP 03',
      );

      expect(
        keywords.map((keyword) => keyword.value).toList(),
        <String>['主关键字', '展示标题', '当前标题'],
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

    test('falls back to raw title when parser cannot normalize it', () {
      final resolver = DefaultComicRefreshKeywordResolver(
        subjectParser: const RuleBasedComicSubjectParser(),
        featureFlags: ComicReaderFeatureFlags.defaults.copyWith(
          readerRefreshMultiKeywordEnabled: true,
        ),
      );

      final keywords = resolver.resolve(
        const ComicEpisodeRefreshRequest(
          sourceTid: '100',
          displayTitle: '原样标题',
        ),
        '另一个原样标题',
      );

      expect(
        keywords.map((keyword) => keyword.value).toList(),
        <String>['原样标题', '另一个原样标题'],
      );
    });
  });
}

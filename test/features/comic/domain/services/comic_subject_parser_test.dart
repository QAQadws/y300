import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';

import 'comic_title_parser_cases.dart';

void main() {
  const parser = RuleBasedComicSubjectParser();

  group('RuleBasedComicSubjectParser compatibility mapping', () {
    for (final testCase in currentComicSubjectParserCases) {
      test(testCase.id, () {
        final result = parser.parse(testCase.rawTitle);

        expect(result.normalizedTitle, testCase.expectedNormalizedTitle);
        expect(result.episodeLabel, testCase.expectedEpisodeLabel);
        expect(result.translationGroup, testCase.expectedTranslationGroup);
        expect(result.inferredAuthor, testCase.expectedAuthor);
      });
    }

    test('documents stage 1 title analyzer rule samples', () {
      expect(stageOneComicTitleRuleSummaryCases, isNotEmpty);
      expect(
        stageOneComicTitleRuleSummaryCases.map((sample) => sample.id),
        containsAll(<String>[
          'strip_volume_marker',
          'search_keyword_is_clean_book_name',
          'extract_special_episode_number',
        ]),
      );
    });
  });
}

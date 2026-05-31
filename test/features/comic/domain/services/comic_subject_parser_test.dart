import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';

import 'comic_title_parser_cases.dart';

void main() {
  const parser = RuleBasedComicSubjectParser();

  group('RuleBasedComicSubjectParser current baseline', () {
    for (final testCase in currentComicSubjectParserCases) {
      test(testCase.id, () {
        final result = parser.parse(testCase.rawTitle);

        expect(result.normalizedTitle, testCase.expectedNormalizedTitle);
        expect(result.episodeLabel, testCase.expectedEpisodeLabel);
        expect(result.translationGroup, testCase.expectedTranslationGroup);
        expect(result.inferredAuthor, testCase.expectedAuthor);
      });
    }

    test('documents stage 1 title cleaning rule samples', () {
      expect(stageOneComicTitleRuleSummaryCases, isNotEmpty);
      expect(
        stageOneComicTitleRuleSummaryCases.map((sample) => sample.id),
        containsAll(<String>[
          'strip_volume_marker',
          'build_author_search_keyword',
        ]),
      );
    });
  });
}

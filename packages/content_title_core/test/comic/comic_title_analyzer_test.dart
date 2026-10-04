import 'package:content_title_core/content_title_core.dart';
import 'package:test/test.dart';

import '../fixtures/comic_title_fixtures.dart';

void main() {
  const analyzer = PetitComicTitleAnalyzer();

  group('PetitComicTitleAnalyzer', () {
    for (final testCase in stageOneComicTitleAnalyzerCases) {
      test(testCase.id, () {
        final result = analyzer.analyze(testCase.rawTitle);

        expect(result.rawTitle, testCase.expectedRawTitle);
        expect(result.cleanBookName, testCase.expectedCleanBookName);
        expect(result.searchKeyword, testCase.expectedSearchKeyword);
        expect(result.authorPrefix, testCase.expectedAuthorPrefix);
        expect(result.episodeLabel, testCase.expectedEpisodeLabel);
        expect(result.chapterNumber, testCase.expectedChapterNumber);
        expect(
          result.possibleChapterNumbers,
          testCase.expectedPossibleChapterNumbers,
        );
      });
    }

    test('extractTidFromUrl supports query and thread urls', () {
      expect(
        analyzer.extractTidFromUrl(
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=12345',
        ),
        '12345',
      );
      expect(analyzer.extractTidFromUrl('thread-54321-1-1.html'), '54321');
    });
  });
}

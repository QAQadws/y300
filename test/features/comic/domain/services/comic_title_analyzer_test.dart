import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/title/comic_title_analyzer.dart';

import 'comic_title_parser_cases.dart';

void main() {
  const analyzer = PetitComicTitleAnalyzer();

  group('PetitComicTitleAnalyzer', () {
    for (final testCase in stageOneComicTitleAnalyzerCases) {
      test(testCase.id, () {
        final result = analyzer.analyze(testCase.rawTitle);

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

    test('search keyword is clipped to 18 runes', () {
      final result = analyzer.analyze('这是一个非常非常非常非常非常长的漫画标题第1话');

      expect(result.cleanBookName, '这是一个非常非常非常非常非常长的漫画标题');
      expect(result.searchKeyword.runes.length, 18);
      expect(result.searchKeyword, '这是一个非常非常非常非常非常长的漫画');
    });

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

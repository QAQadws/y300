import 'package:content_title_core/content_title_core.dart';

void main() {
  const analyzer = PetitComicTitleAnalyzer();
  final result = analyzer.analyze('[Scan] Comic Title Vol.2');
  print(result.cleanBookName);
  print(result.episodeLabel);
  print(result.possibleChapterNumbers);

  const sanitizer = DefaultNovelTitleSanitizer();
  print(sanitizer.sanitize('[Author] Novel Title Vol.2'));

  const chapterPolicy = FirstMeaningfulSentenceNovelChapterTitlePolicy();
  print(
    chapterPolicy.buildTitle(
      normalizedPlainText: 'ACT13.5 First sentence. Second sentence.',
      orderIndex: 0,
      pid: 'example',
    ),
  );
}

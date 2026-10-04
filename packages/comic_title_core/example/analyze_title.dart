import 'package:comic_title_core/comic_title_core.dart';

void main() {
  const analyzer = PetitComicTitleAnalyzer();
  final result = analyzer.analyze('[Scan] Comic Title Vol.2');
  print(result.cleanBookName);
  print(result.episodeLabel);
  print(result.possibleChapterNumbers);
}

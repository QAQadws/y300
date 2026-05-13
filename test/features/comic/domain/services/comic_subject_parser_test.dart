import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';

void main() {
  const parser = RuleBasedComicSubjectParser();

  test('extracts translation group, normalized title and episode label', () {
    const subject = '【提灯喵汉化组】[紬めめ]若小雏尚在人世 5';
    final result = parser.parse(subject);

    expect(result.translationGroup, '提灯喵汉化组');
    expect(result.normalizedTitle, '若小雏尚在人世');
    expect(result.episodeLabel, '5');
    expect(result.inferredAuthor, '紬めめ');
  });

  test('keeps plain title when no bracket metadata exists', () {
    const subject = '邻座的大姐头';
    final result = parser.parse(subject);

    expect(result.translationGroup, isNull);
    expect(result.normalizedTitle, '邻座的大姐头');
    expect(result.episodeLabel, isNull);
  });

  test('keeps split episode suffix in episode label', () {
    const subject = '[百合會]はなにあらし(好事多磨)第82話下';
    final result = parser.parse(subject);

    expect(result.normalizedTitle, 'はなにあらし(好事多磨)');
    expect(result.episodeLabel, '第82話下');
  });

  test('keeps paired title brackets while trimming trailing separators', () {
    const subject = '[百合會]作品名(副标题)_ 第3話';
    final result = parser.parse(subject);

    expect(result.normalizedTitle, '作品名(副标题)');
    expect(result.episodeLabel, '第3話');
  });
}

import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_title_policy.dart';

import '../../test_support/novel_title_fixtures.dart';

void main() {
  const policy = FirstMeaningfulSentenceNovelChapterTitlePolicy();

  test('uses the first meaningful Chinese or English sentence', () {
    expect(_title(policy, '简介\n这是第一句。后面不进入标题。'), '这是第一句。');
    expect(
      _title(policy, 'The first sentence. The second sentence.'),
      'The first sentence.',
    );
    expect(_title(policy, '第一句……第二句'), '第一句……');
  });

  test('uses a newline as a sentence boundary', () {
    expect(_title(policy, '没有句号的第一行\n第二行'), '没有句号的第一行');
  });

  for (final fixture in novelChapterTitleFixtures) {
    test('preserves chapter heading punctuation: ${fixture.id}', () {
      expect(
        _title(policy, fixture.normalizedCandidate),
        fixture.expectedTitle,
      );
    });
  }

  test('ignores standalone and inline Discuz edit notices', () {
    expect(_title(policy, '本帖最后由 咕哒子鸭 于 2025-5-4 19:36 编辑\n正文第一句。'), '正文第一句。');
    expect(_title(policy, '本帖最后由 咕哒子鸭 于2025-5-419:36编辑正文第一句。后句。'), '正文第一句。');
  });

  test('falls back to a stable ordinal title for empty metadata text', () {
    expect(
      policy.buildTitle(
        normalizedPlainText: '简介\n目录',
        orderIndex: 4,
        pid: '5001',
      ),
      '第 5 章',
    );
  });

  test('truncates by grapheme cluster without splitting emoji', () {
    final source = '${List<String>.filled(35, '字').join()}👨‍👩‍👧‍👦结尾';
    final title = _title(policy, source);

    expect(title.characters.length, 36);
    expect(title, endsWith('…'));
    expect(title, isNot(contains('�')));
  });
}

String _title(NovelChapterTitlePolicy policy, String source) {
  return policy.buildTitle(
    normalizedPlainText: source,
    orderIndex: 0,
    pid: '5001',
  );
}

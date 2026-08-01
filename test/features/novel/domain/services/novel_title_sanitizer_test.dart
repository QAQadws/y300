import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/services/novel_title_sanitizer.dart';

import '../../test_support/novel_title_fixtures.dart';

void main() {
  const sanitizer = DefaultNovelTitleSanitizer();

  group('DefaultNovelTitleSanitizer fixtures', () {
    for (final fixture in novelTitleFixtures) {
      test('${fixture.id} → ${fixture.note ?? "expected output"}', () {
        expect(
          sanitizer.sanitize(fixture.raw),
          fixture.expectedSanitized,
          reason: '样例 ${fixture.id} 期望被清洗为预设值',
        );
      });
    }
  });

  group('DefaultNovelTitleSanitizer edges', () {
    test('空字符串原样返回', () {
      expect(sanitizer.sanitize(''), '');
    });

    test('仅空白返回空', () {
      expect(sanitizer.sanitize('   \t  '), '');
    });

    test('已清洗的标题不再变化', () {
      const clean = '一周一次买下同班同学的那些事';
      expect(sanitizer.sanitize(clean), clean);
    });

    test('&amp; 实体解码为 &', () {
      expect(sanitizer.sanitize('Foo &amp; Bar'), 'Foo & Bar');
    });

    test('解码后剥前导括号', () {
      expect(sanitizer.sanitize('[A&amp;B]Title'), 'Title');
    });

    test('只剥前导，正文中的方括号保留', () {
      expect(sanitizer.sanitize('[漢化]内文 [注释] 结尾'), '内文 [注释] 结尾');
    });

    test('混搭中文和英文括号都被剥', () {
      expect(sanitizer.sanitize('【组】[人]Title'), 'Title');
    });

    test('遇到第一个非括号 token 立即停止剥离', () {
      expect(sanitizer.sanitize('[A]Body[B]'), 'Body[B]');
    });

    test('括号未闭合时不会越界吞内容', () {
      // 不匹配 leading 模式 —— 整段保持原样（去首尾空白）。
      expect(sanitizer.sanitize('[未闭合标题正文'), '[未闭合标题正文');
    });
  });
}

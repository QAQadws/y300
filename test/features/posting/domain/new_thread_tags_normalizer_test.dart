import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/posting/domain/services/new_thread_tags_normalizer.dart';

void main() {
  group('NewThreadTagsNormalizer', () {
    const normalizer = NewThreadTagsNormalizer(maxTagLength: 5, maxTagsCount: 3);

    test('trims whitespace and drops empties', () {
      expect(
        normalizer.normalize(['  百合 ', '', '  ', '动画']),
        ['百合', '动画'],
      );
    });

    test('preserves first occurrence and dedupes', () {
      expect(
        normalizer.normalize(['百合', '百合', '动画']),
        ['百合', '动画'],
      );
    });

    test('drops tags longer than maxTagLength entirely', () {
      // 没有"截断成头 N 个字符"——这是设计选择，避免悄悄改写用户输入。
      expect(
        normalizer.normalize(['百合', '太长太长了不行']),
        ['百合'],
      );
    });

    test('caps total count at maxTagsCount', () {
      expect(
        normalizer.normalize(['a', 'b', 'c', 'd']),
        ['a', 'b', 'c'],
      );
    });

    test('empty input yields empty list', () {
      expect(normalizer.normalize(<String>[]), isEmpty);
    });
  });
}

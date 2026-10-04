import 'package:content_title_core/content_title_core.dart';
import 'package:test/test.dart';

import '../fixtures/novel_title_fixtures.dart';

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
    for (final fixture in novelTitleEdgeFixtures) {
      test(fixture.note ?? fixture.id, () {
        expect(sanitizer.sanitize(fixture.raw), fixture.expectedSanitized);
      });
    }
  });
}

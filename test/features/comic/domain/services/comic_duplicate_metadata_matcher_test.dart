import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_duplicate_metadata_matcher.dart';

import 'comic_title_parser_cases.dart';

void main() {
  const matcher = ComicDuplicateMetadataMatcher();

  group('ComicDuplicateMetadataMatcher', () {
    for (final testCase in comicDuplicateMetadataCases) {
      test(testCase.id, () {
        final left = matcher.keyFor(
          title: testCase.left.title,
          author: testCase.left.author,
        );
        final right = matcher.keyFor(
          title: testCase.right.title,
          author: testCase.right.author,
        );

        expect(left != null && left == right, testCase.matches);
      });
    }

    test('null titles cannot generate matching evidence', () {
      expect(
        matcher.keyFor(title: null, author: comicDuplicateMetadataBase.author),
        isNull,
      );
    });
  });
}

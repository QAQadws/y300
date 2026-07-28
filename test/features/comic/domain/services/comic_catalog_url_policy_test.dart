import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_catalog_url_policy.dart';

void main() {
  group('ComicCatalogUrlPolicy', () {
    const policy = ComicCatalogUrlPolicy();

    test('normalizes a Yamibo tag catalog override', () {
      expect(
        policy.normalizeOverride('misc.php?mod=tag&id=20686'),
        'https://bbs.yamibo.com/misc.php?mod=tag&id=20686&type=thread&page=1',
      );
    });

    test('rejects a Yamibo thread url as a catalog override', () {
      expect(
        () => policy.normalizeOverride(
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=571564',
        ),
        throwsA(
          isA<ComicCatalogUrlInputException>().having(
            (error) => error.code,
            'code',
            ComicCatalogUrlInputErrorCode.notTagCatalog,
          ),
        ),
      );
    });

    test('rejects a tag url without an id', () {
      expect(
        () =>
            policy.normalizeOverride('https://bbs.yamibo.com/misc.php?mod=tag'),
        throwsA(
          isA<ComicCatalogUrlInputException>().having(
            (error) => error.code,
            'code',
            ComicCatalogUrlInputErrorCode.notTagCatalog,
          ),
        ),
      );
    });
  });
}

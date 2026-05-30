import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_catalog_miss_policy.dart';

void main() {
  group('DefaultComicCatalogMissPolicy', () {
    const policy = DefaultComicCatalogMissPolicy();

    test('allows long-running tag', () {
      expect(
        policy.shouldQueueSearchOnCatalogMiss(sourceTagName: '長篇連載'),
        isTrue,
      );
    });

    test('rejects non long-running tag', () {
      expect(
        policy.shouldQueueSearchOnCatalogMiss(sourceTagName: '韩国漫画'),
        isFalse,
      );
    });

    test('forceSearchOnCatalogMiss bypasses tag gate', () {
      expect(
        policy.shouldQueueSearchOnCatalogMiss(
          sourceTagName: '韩国漫画',
          forceSearchOnCatalogMiss: true,
        ),
        isTrue,
      );
    });

    test('treats null empty and trimmed input consistently', () {
      expect(
        policy.shouldQueueSearchOnCatalogMiss(sourceTagName: null),
        isFalse,
      );
      expect(
        policy.shouldQueueSearchOnCatalogMiss(sourceTagName: '   '),
        isFalse,
      );
      expect(
        policy.shouldQueueSearchOnCatalogMiss(sourceTagName: ' 長篇連載 '),
        isTrue,
      );
    });
  });
}

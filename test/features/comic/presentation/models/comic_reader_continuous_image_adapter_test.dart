import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/presentation/controllers/comic_reader_controller.dart';
import 'package:y300/features/comic/presentation/models/comic_reader_continuous_image_adapter.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';

void main() {
  group('ComicReaderContinuousImageAdapter', () {
    const adapter = ComicReaderContinuousImageAdapter();

    test('maps reader images to stable continuous image items', () {
      final items = adapter.mapImages(
        episodeId: 'episode-1',
        pageSpacing: 12,
        images: const <ComicReaderImageState>[
          ComicReaderImageState(
            imageUrl: 'https://img.test/1.jpg',
            imageIndex: 0,
            cacheStatus: 'done',
            cacheKey: 'cache-1',
            width: 900,
            height: 1800,
          ),
        ],
      );

      expect(items, hasLength(1));
      expect(items.single.ownerId, 'episode-1');
      expect(items.single.id, 'episode-1:0:cache-1');
      expect(items.single.cacheKey, 'cache-1');
      expect(items.single.sourceKind, ContinuousImageSourceKind.comicPage);
      expect(items.single.knownWidth, 900);
      expect(items.single.knownHeight, 1800);
      expect(items.single.fallbackAspectRatio, 0.75);
      expect(items.single.spacingAfter, 12);
    });

    test('falls back to image url when cache key is absent', () {
      final item = adapter.mapImage(
        episodeId: 'episode-1',
        pageSpacing: 99,
        image: const ComicReaderImageState(
          imageUrl: 'https://img.test/1.jpg',
          imageIndex: 4,
          cacheStatus: 'none',
        ),
      );

      expect(item.id, 'episode-1:4:https://img.test/1.jpg');
      expect(item.cacheKey, 'https://img.test/1.jpg');
      expect(item.spacingAfter, 48);
    });
  });
}

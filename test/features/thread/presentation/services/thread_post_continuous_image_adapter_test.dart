import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_resource_layout_hints.dart';
import 'package:y300/features/thread/presentation/services/thread_post_continuous_image_adapter.dart';

void main() {
  group('ThreadPostContinuousImageAdapter', () {
    const adapter = ThreadPostContinuousImageAdapter();

    test('maps html dimensions before layout hints', () {
      final item = adapter.mapBlockImage(
        ownerId: 'tid-100',
        image: _image(
          url: 'https://img.test/1.jpg',
          index: 0,
          originalWidth: 900,
          originalHeight: 1800,
        ),
        cacheKey: 'cache-1',
        fallbackAspectRatio: 0.7,
        spacingAfter: 10,
        layoutHint: const ThreadPostBlockImageLayoutHint(
          aspectRatio: 1.5,
          source: ThreadPostResourceLayoutHintSource.cachedDimension,
          lockForCurrentBuild: false,
        ),
      );

      expect(item.ownerId, 'tid-100');
      expect(item.id, 'tid-100:0:cache-1');
      expect(item.sourceKind, ContinuousImageSourceKind.threadPostImage);
      expect(item.knownWidth, 900);
      expect(item.knownHeight, 1800);
      expect(item.knownDimensionSource, ContinuousImageDimensionSource.html);
      expect(item.spacingAfter, 10);
    });

    test('uses cached layout hint as ratio-preserving dimensions', () {
      final item = adapter.mapBlockImage(
        ownerId: 'tid-100',
        image: _image(url: 'https://img.test/1.jpg', index: 1),
        fallbackAspectRatio: 0.7,
        spacingAfter: 10,
        layoutHint: const ThreadPostBlockImageLayoutHint(
          aspectRatio: 0.5,
          source: ThreadPostResourceLayoutHintSource.cachedDimension,
          lockForCurrentBuild: false,
        ),
      );

      expect(item.knownWidth, 500);
      expect(item.knownHeight, 1000);
      expect(
        item.knownDimensionSource,
        ContinuousImageDimensionSource.persistedCache,
      );
    });

    test('ignores content default hints unless explicitly requested', () {
      final defaultItem = adapter.mapBlockImage(
        ownerId: 'tid-100',
        image: _image(url: 'https://img.test/1.jpg', index: 1),
        fallbackAspectRatio: 0.7,
        spacingAfter: 10,
        layoutHint: const ThreadPostBlockImageLayoutHint(
          aspectRatio: 1.2,
          source: ThreadPostResourceLayoutHintSource.contentDefault,
          lockForCurrentBuild: true,
        ),
      );
      final lockedItem = adapter.mapBlockImage(
        ownerId: 'tid-100',
        image: _image(url: 'https://img.test/1.jpg', index: 1),
        fallbackAspectRatio: 0.7,
        spacingAfter: 10,
        layoutHint: const ThreadPostBlockImageLayoutHint(
          aspectRatio: 1.2,
          source: ThreadPostResourceLayoutHintSource.contentDefault,
          lockForCurrentBuild: true,
        ),
        includeContentDefaultHint: true,
      );

      expect(defaultItem.knownDimensions, isNull);
      expect(lockedItem.knownWidth, 1200);
      expect(lockedItem.knownHeight, 1000);
      expect(
        lockedItem.knownDimensionSource,
        ContinuousImageDimensionSource.fallback,
      );
    });
  });
}

ThreadPostImageBlock _image({
  required String url,
  required int index,
  double? originalWidth,
  double? originalHeight,
}) {
  return ThreadPostImageBlock(
    url: url,
    rawUrl: url,
    index: index,
    originalWidth: originalWidth,
    originalHeight: originalHeight,
  );
}

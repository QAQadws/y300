import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/thread/domain/models/thread_image_open_models.dart';
import 'package:y300/features/thread/domain/models/thread_post_resource_layout_hints.dart';
import 'package:y300/features/thread/presentation/services/thread_image_reader_continuous_image_adapter.dart';

void main() {
  group('ThreadImageReaderContinuousImageAdapter', () {
    const adapter = ThreadImageReaderContinuousImageAdapter();

    test('maps thread image open request to reader continuous items', () {
      final items = adapter.mapRequest(
        _request(
          entries: const <ThreadPostImageEntry>[
            ThreadPostImageEntry(
              url: 'https://bbs.yamibo.com/data/attachment/forum/page-1.jpg',
              rawUrl: 'data/attachment/forum/page-1.jpg',
              indexInPost: 0,
              cacheKey: 'cache-0',
              aid: 'aid-1',
              layoutHint: ThreadPostBlockImageLayoutHint(
                aspectRatio: 0.5,
                source: ThreadPostResourceLayoutHintSource.cachedDimension,
                lockForCurrentBuild: false,
              ),
            ),
            ThreadPostImageEntry(
              url: 'https://bbs.yamibo.com/data/attachment/forum/page-2.jpg',
              rawUrl: 'data/attachment/forum/page-2.jpg',
              indexInPost: 1,
              cacheKey: 'cache-1',
            ),
          ],
        ),
        fallbackAspectRatio: 0.7,
      );

      expect(items, hasLength(2));
      expect(items.first.ownerId, 'thread:100:post:p1');
      expect(items.first.id, 'thread:100:post:p1:0:cache-0');
      expect(
        items.first.sourceKind,
        ContinuousImageSourceKind.threadImageReader,
      );
      expect(
        items.first.referer,
        Uri.parse('https://bbs.yamibo.com/thread-100-1-1.html'),
      );
      expect(items.first.knownWidth, 500);
      expect(items.first.knownHeight, 1000);
      expect(
        items.first.knownDimensionSource,
        ContinuousImageDimensionSource.persistedCache,
      );
      expect(items.first.spacingAfter, 0);
      expect(items.first.extra['rawUrl'], 'data/attachment/forum/page-1.jpg');
      expect(items.first.extra['aid'], 'aid-1');

      expect(items.last.id, 'thread:100:post:p1:1:cache-1');
      expect(items.last.knownDimensions, isNull);
      expect(items.last.fallbackAspectRatio, 0.7);
    });

    test('maps content default layout hint as fallback dimensions', () {
      final items = adapter.mapRequest(
        _request(
          entries: const <ThreadPostImageEntry>[
            ThreadPostImageEntry(
              url: 'https://bbs.yamibo.com/data/attachment/forum/page-1.jpg',
              rawUrl: 'data/attachment/forum/page-1.jpg',
              indexInPost: 0,
              cacheKey: 'cache-0',
              layoutHint: ThreadPostBlockImageLayoutHint(
                aspectRatio: 1.2,
                source: ThreadPostResourceLayoutHintSource.contentDefault,
                lockForCurrentBuild: true,
              ),
            ),
          ],
        ),
      );

      expect(items.single.knownWidth, 1200);
      expect(items.single.knownHeight, 1000);
      expect(
        items.single.knownDimensionSource,
        ContinuousImageDimensionSource.fallback,
      );
    });
  });
}

ThreadImageOpenRequest _request({required List<ThreadPostImageEntry> entries}) {
  return ThreadImageOpenRequest(
    tid: '100',
    pid: 'p1',
    postNumber: 1,
    referer: 'https://bbs.yamibo.com/thread-100-1-1.html',
    group: ThreadPostImageGroup(
      tid: '100',
      pid: 'p1',
      postNumber: 1,
      entries: entries,
    ),
    initialIndex: 0,
  );
}

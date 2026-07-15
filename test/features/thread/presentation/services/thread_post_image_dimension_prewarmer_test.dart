import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_resource_layout_hints.dart';
import 'package:y300/features/thread/presentation/services/thread_post_image_dimension_prewarmer.dart';
import 'package:y300/features/thread/presentation/services/thread_post_image_dimension_store.dart';

void main() {
  group('ThreadPostImageDimensionStore', () {
    test('advances signature and notifies only on real change', () {
      final store = ThreadPostImageDimensionStore();
      final firstSignature = store.signature;
      var notifications = 0;
      store.addListener(() => notifications += 1);

      const block = ThreadPostImageBlock(
        url: 'https://bbs.yamibo.com/a.jpg',
        rawUrl: 'a.jpg',
        index: 0,
      );

      store.recordAll(
        blockDimensions: {
          'block:0|https://bbs.yamibo.com/a.jpg|a.jpg':
              const ThreadPostResourceDimension(width: 800, height: 400),
        },
      );
      expect(notifications, 1);
      expect(store.signature, isNot(firstSignature));
      expect(store.blockImageDimension(block)?.aspectRatio, closeTo(2.0, 1e-9));

      // 写入相同值不应再次通知。
      store.recordAll(
        blockDimensions: {
          'block:0|https://bbs.yamibo.com/a.jpg|a.jpg':
              const ThreadPostResourceDimension(width: 800, height: 400),
        },
      );
      expect(notifications, 1);
    });

    test('ignores late writes after the owning page disposes the store', () {
      final store = ThreadPostImageDimensionStore();
      var notifications = 0;
      store.addListener(() => notifications += 1);
      store.dispose();

      expect(
        () => store.recordAll(
          blockDimensions: const <String, ThreadPostResourceDimension>{
            'block:late': ThreadPostResourceDimension(width: 800, height: 400),
          },
        ),
        returnsNormally,
      );
      expect(notifications, 0);
    });
  });

  group('ThreadPostImageDimensionPrewarmer', () {
    test('records cached dimensions for images lacking HTML size', () async {
      const block = ThreadPostImageBlock(
        url: 'https://bbs.yamibo.com/page.jpg',
        rawUrl: 'page.jpg',
        index: 0,
      );
      const document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[block],
      );
      final store = ThreadPostImageDimensionStore();
      final prewarmer = ThreadPostImageDimensionPrewarmer(
        imageCacheService: _SizedImageCacheService(<String, CachedImageResult>{
          'cache-0': const CachedImageResult(
            success: true,
            cacheKey: 'cache-0',
            width: 1000,
            height: 250,
          ),
        }),
        store: store,
      );

      await prewarmer.prewarmDocuments(<ThreadPostBodyDocument>[
        document,
      ], cacheKeyResolver: (_) => 'cache-0');

      expect(store.blockImageDimension(block)?.aspectRatio, closeTo(4.0, 1e-9));
    });

    test('skips images that already carry HTML dimensions', () async {
      const block = ThreadPostImageBlock(
        url: 'https://bbs.yamibo.com/page.jpg',
        rawUrl: 'page.jpg',
        index: 0,
        originalWidth: 600,
        originalHeight: 300,
      );
      final cacheService = _SizedImageCacheService(
        <String, CachedImageResult>{},
      );
      final store = ThreadPostImageDimensionStore();
      final prewarmer = ThreadPostImageDimensionPrewarmer(
        imageCacheService: cacheService,
        store: store,
      );

      await prewarmer.prewarmDocuments(const <ThreadPostBodyDocument>[
        ThreadPostBodyDocument(blocks: <ThreadPostBodyBlock>[block]),
      ], cacheKeyResolver: (_) => 'cache-0');

      expect(cacheService.lookups, isEmpty);
      expect(store.blockImageDimension(block), isNull);
    });
  });
}

class _SizedImageCacheService implements ImageCacheService {
  _SizedImageCacheService(this.results);

  final Map<String, CachedImageResult> results;
  final List<String> lookups = <String>[];

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async {
    lookups.add(cacheKey);
    return results[cacheKey];
  }

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult.failed;
  }

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult.failed;
  }

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async {
    return 0;
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }

  @override
  Future<void> clearUnprotected() async {}
}

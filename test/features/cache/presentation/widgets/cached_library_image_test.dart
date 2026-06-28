import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';

void main() {
  testWidgets('uses cached local result before starting a new cache request', (
    tester,
  ) async {
    final cacheService = _ImmediateCachedImageService(
      result: const CachedImageResult(
        success: true,
        cacheKey: 'thread-image',
        localPath: 'C:/cache/thread-image.jpg',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageCacheServiceProvider.overrideWithValue(cacheService)],
        child: const MaterialApp(
          home: CachedLibraryImage(
            request: ImageCacheRequest(
              cacheKey: 'thread-image',
              sourceUrl:
                  'https://bbs.yamibo.com/data/attachment/forum/page.jpg',
              ownerType: ImageCacheOwnerType.thread,
              ownerId: '100',
              role: ImageCacheRole.threadInline,
            ),
            fit: BoxFit.cover,
            placeholder: SizedBox(key: Key('placeholder')),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(cacheService.getCachedCount, 1);
    expect(cacheService.ensureStarted, isFalse);
  });

  testWidgets(
    'keeps displayed remote image instead of switching to local file mid-frame',
    (tester) async {
      final image = await tester.runAsync(
        () => createTestImage(width: 4, height: 3, cache: false),
      );
      final testImage = image!;
      addTearDown(testImage.dispose);
      final cacheService = _DeferredImageCacheService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageCacheServiceProvider.overrideWithValue(cacheService),
          ],
          child: MaterialApp(
            home: CachedLibraryImage(
              request: const ImageCacheRequest(
                cacheKey: 'thread-image',
                sourceUrl:
                    'https://bbs.yamibo.com/data/attachment/forum/page.jpg',
                ownerType: ImageCacheOwnerType.thread,
                ownerId: '100',
                role: ImageCacheRole.threadInline,
              ),
              fit: BoxFit.cover,
              placeholder: const SizedBox(key: Key('placeholder')),
              remoteImageProviderOverride: _SynchronousImageProvider(testImage),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(cacheService.ensureStarted, isTrue);
      expect(find.byType(Image), findsOneWidget);
      expect(
        tester.widget<Image>(find.byType(Image)).image,
        isA<_SynchronousImageProvider>(),
      );

      cacheService.complete(
        const CachedImageResult(
          success: true,
          cacheKey: 'thread-image',
          localPath: 'C:/cache/thread-image.jpg',
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(
        tester.widget<Image>(find.byType(Image)).image,
        isA<_SynchronousImageProvider>(),
      );
      expect(
        tester.widget<CachedLibraryImage>(find.byType(CachedLibraryImage)),
        isNotNull,
      );
    },
  );
}

class _ImmediateCachedImageService extends _DeferredImageCacheService {
  _ImmediateCachedImageService({required this.result});

  final CachedImageResult result;
  int getCachedCount = 0;

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async {
    getCachedCount++;
    return result;
  }
}

class _DeferredImageCacheService implements ImageCacheService {
  final Completer<CachedImageResult> _completer =
      Completer<CachedImageResult>();
  bool ensureStarted = false;

  void complete(CachedImageResult result) {
    _completer.complete(result);
  }

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) {
    ensureStarted = true;
    return _completer.future;
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

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
  Future<void> clearUnprotected() async {}
}

class _SynchronousImageProvider
    extends ImageProvider<_SynchronousImageProvider> {
  const _SynchronousImageProvider(this.image);

  final ui.Image image;

  @override
  Future<_SynchronousImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture<_SynchronousImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _SynchronousImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(ImageInfo(image: image)),
    );
  }
}

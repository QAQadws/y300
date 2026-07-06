import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/media/cover_aware_resize_image.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';

void main() {
  testWidgets(
    'shows placeholder and does not build remote image while cache lookup is pending',
    (tester) async {
      final cacheService = _ControlledImageCacheService();
      final image = await tester.runAsync(
        () => createTestImage(width: 4, height: 3, cache: false),
      );
      final testImage = image!;
      addTearDown(testImage.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageCacheServiceProvider.overrideWithValue(cacheService),
          ],
          child: MaterialApp(
            home: CachedLibraryImage(
              request: _request('thread-image'),
              fit: BoxFit.cover,
              placeholder: const SizedBox(key: Key('placeholder')),
              remoteImageProviderOverride: _SynchronousImageProvider(testImage),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(cacheService.getCachedCount('thread-image'), 1);
      expect(cacheService.ensureStarted('thread-image'), isFalse);
      expect(find.byKey(const Key('placeholder')), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    },
  );

  testWidgets('uses cached local result before starting a new cache request', (
    tester,
  ) async {
    final localFile = _createTempPng(tester);
    final cacheService = _ControlledImageCacheService();
    cacheService.completeGetCached(
      'thread-image',
      CachedImageResult(
        success: true,
        cacheKey: 'thread-image',
        localPath: localFile.path,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageCacheServiceProvider.overrideWithValue(cacheService)],
        child: MaterialApp(
          home: CachedLibraryImage(
            request: _request('thread-image'),
            fit: BoxFit.cover,
            placeholder: const SizedBox(key: Key('placeholder')),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(cacheService.getCachedCount('thread-image'), 1);
    expect(cacheService.ensureStarted('thread-image'), isFalse);
    expect(find.byType(Image), findsOneWidget);
    expect(
      _underlyingProvider(tester.widget<Image>(find.byType(Image)).image),
      isA<FileImage>(),
    );
  });

  testWidgets('allows remote fallback only after direct cache lookup misses', (
    tester,
  ) async {
    final image = await tester.runAsync(
      () => createTestImage(width: 4, height: 3, cache: false),
    );
    final testImage = image!;
    addTearDown(testImage.dispose);
    final cacheService = _ControlledImageCacheService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageCacheServiceProvider.overrideWithValue(cacheService)],
        child: MaterialApp(
          home: CachedLibraryImage(
            request: _request('thread-image'),
            fit: BoxFit.cover,
            placeholder: const SizedBox(key: Key('placeholder')),
            remoteImageProviderOverride: _SynchronousImageProvider(testImage),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(cacheService.ensureStarted('thread-image'), isFalse);

    cacheService.completeGetCached('thread-image', null);
    await tester.pump();
    await tester.pump();

    expect(cacheService.ensureStarted('thread-image'), isTrue);
    expect(find.byType(Image), findsOneWidget);
    expect(
      _underlyingProvider(tester.widget<Image>(find.byType(Image)).image),
      isA<_SynchronousImageProvider>(),
    );
  });

  testWidgets(
    'keeps displayed remote image instead of switching to local file mid-frame',
    (tester) async {
      final image = await tester.runAsync(
        () => createTestImage(width: 4, height: 3, cache: false),
      );
      final testImage = image!;
      addTearDown(testImage.dispose);
      final cacheService = _ControlledImageCacheService();
      cacheService.completeGetCached('thread-image', null);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageCacheServiceProvider.overrideWithValue(cacheService),
          ],
          child: MaterialApp(
            home: CachedLibraryImage(
              request: _request('thread-image'),
              fit: BoxFit.cover,
              placeholder: const SizedBox(key: Key('placeholder')),
              remoteImageProviderOverride: _SynchronousImageProvider(testImage),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(cacheService.ensureStarted('thread-image'), isTrue);
      expect(find.byType(Image), findsOneWidget);
      expect(
        _underlyingProvider(tester.widget<Image>(find.byType(Image)).image),
        isA<_SynchronousImageProvider>(),
      );

      cacheService.completeEnsure(
        'thread-image',
        const CachedImageResult(
          success: true,
          cacheKey: 'thread-image',
          localPath: 'C:/cache/thread-image.jpg',
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(
        _underlyingProvider(tester.widget<Image>(find.byType(Image)).image),
        isA<_SynchronousImageProvider>(),
      );
      expect(
        tester.widget<CachedLibraryImage>(find.byType(CachedLibraryImage)),
        isNotNull,
      );
    },
  );

  testWidgets('ignores stale cache lookup results after request changes', (
    tester,
  ) async {
    final oldFile = _createTempPng(tester);
    final newFile = _createTempPng(tester);
    final cacheService = _ControlledImageCacheService();

    Widget build(String cacheKey) {
      return ProviderScope(
        overrides: [imageCacheServiceProvider.overrideWithValue(cacheService)],
        child: MaterialApp(
          home: CachedLibraryImage(
            request: _request(cacheKey),
            fit: BoxFit.cover,
            placeholder: const SizedBox(key: Key('placeholder')),
          ),
        ),
      );
    }

    await tester.pumpWidget(build('old-image'));
    await tester.pump();
    expect(find.byType(Image), findsNothing);

    await tester.pumpWidget(build('new-image'));
    await tester.pump();

    cacheService.completeGetCached(
      'old-image',
      CachedImageResult(
        success: true,
        cacheKey: 'old-image',
        localPath: oldFile.path,
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(cacheService.ensureStarted('old-image'), isFalse);

    cacheService.completeGetCached(
      'new-image',
      CachedImageResult(
        success: true,
        cacheKey: 'new-image',
        localPath: newFile.path,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    final provider = _underlyingProvider(
      tester.widget<Image>(find.byType(Image)).image,
    );
    expect(provider, isA<FileImage>());
    expect((provider as FileImage).file.path, newFile.path);
  });
}

ImageCacheRequest _request(String cacheKey) {
  return ImageCacheRequest(
    cacheKey: cacheKey,
    sourceUrl: 'https://bbs.yamibo.com/data/attachment/forum/$cacheKey.jpg',
    ownerType: ImageCacheOwnerType.thread,
    ownerId: '100',
    role: ImageCacheRole.threadInline,
  );
}

io.File _createTempPng(WidgetTester tester) {
  final directory = io.Directory.systemTemp.createTempSync(
    'cached_library_image_test_',
  );
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  final file = io.File('${directory.path}/image.png');
  file.writeAsBytesSync(base64Decode(_onePixelPngBase64), flush: true);
  return file;
}

const _onePixelPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';

/// 解开降采样包裹，取底层真实 provider（Phase 0 起 provider 可能被 ResizeImage 包裹）。
ImageProvider _underlyingProvider(ImageProvider provider) {
  if (provider is ResizeImage) {
    return provider.imageProvider;
  }
  if (provider is CoverAwareResizeImage) {
    return provider.imageProvider;
  }
  return provider;
}

class _ControlledImageCacheService implements ImageCacheService {
  final Map<String, Completer<CachedImageResult?>> _getCachedCompleters =
      <String, Completer<CachedImageResult?>>{};
  final Map<String, Completer<CachedImageResult>> _ensureCompleters =
      <String, Completer<CachedImageResult>>{};
  final Map<String, int> _getCachedCounts = <String, int>{};

  int getCachedCount(String cacheKey) => _getCachedCounts[cacheKey] ?? 0;

  bool ensureStarted(String cacheKey) {
    return _ensureCompleters.containsKey(cacheKey);
  }

  void completeGetCached(String cacheKey, CachedImageResult? result) {
    final completer = _getCachedCompleters.putIfAbsent(
      cacheKey,
      () => Completer<CachedImageResult?>(),
    );
    if (!completer.isCompleted) {
      completer.complete(result);
    }
  }

  void completeEnsure(String cacheKey, CachedImageResult result) {
    final completer = _ensureCompleters.putIfAbsent(
      cacheKey,
      () => Completer<CachedImageResult>(),
    );
    if (!completer.isCompleted) {
      completer.complete(result);
    }
  }

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) {
    final cacheKey = request.cacheKey;
    return _ensureCompleters
        .putIfAbsent(cacheKey, () => Completer<CachedImageResult>())
        .future;
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) {
    _getCachedCounts[cacheKey] = (_getCachedCounts[cacheKey] ?? 0) + 1;
    return _getCachedCompleters
        .putIfAbsent(cacheKey, () => Completer<CachedImageResult?>())
        .future;
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

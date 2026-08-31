import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/media/cover_aware_resize_image.dart';
import 'package:y300/core/media/encoded_image_dimension_probe.dart';
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
          child: LocalizedTestApp(
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

  testWidgets('shows a loading indicator only after the configured delay', (
    tester,
  ) async {
    final cacheService = _ControlledImageCacheService();

    await tester.pumpWidget(
      _loadingHarness(
        cacheService,
        remoteImageProvider: const _PendingImageProvider(),
      ),
    );
    await tester.pump();

    expect(_loadingIndicator, findsNothing);
    await tester.pump(const Duration(milliseconds: 299));
    expect(_loadingIndicator, findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(_loadingIndicator, findsOneWidget);
  });

  testWidgets('keeps one loading deadline across cache and remote stages', (
    tester,
  ) async {
    final cacheService = _ControlledImageCacheService();

    await tester.pumpWidget(
      _loadingHarness(
        cacheService,
        remoteImageProvider: const _PendingImageProvider(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    cacheService.completeGetCached('thread-image', null);
    await tester.pump();
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(cacheService.ensureStarted('thread-image'), isTrue);
    expect(_loadingIndicator, findsNothing);

    await tester.pump(const Duration(milliseconds: 50));
    expect(_loadingIndicator, findsOneWidget);
  });

  testWidgets('fast image completion never flashes the delayed indicator', (
    tester,
  ) async {
    final image = await tester.runAsync(
      () => createTestImage(width: 4, height: 3, cache: false),
    );
    final testImage = image!;
    addTearDown(testImage.dispose);
    final cacheService = _ControlledImageCacheService();
    cacheService.completeGetCached('thread-image', null);

    await tester.pumpWidget(
      _loadingHarness(
        cacheService,
        remoteImageProvider: _SynchronousImageProvider(testImage),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(Image), findsOneWidget);
    expect(_loadingIndicator, findsNothing);
  });

  testWidgets('image failure settles and removes the loading indicator', (
    tester,
  ) async {
    final cacheService = _ControlledImageCacheService();
    final provider = _ControlledImageProvider();

    await tester.pumpWidget(
      _loadingHarness(cacheService, imageProvider: provider),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(_loadingIndicator, findsOneWidget);

    provider.fail();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('error-placeholder')), findsOneWidget);
    expect(_loadingIndicator, findsNothing);
  });

  testWidgets('changing requests resets and isolates the loading deadline', (
    tester,
  ) async {
    final cacheService = _ControlledImageCacheService();

    await tester.pumpWidget(
      _loadingHarness(
        cacheService,
        cacheKey: 'old-image',
        remoteImageProvider: const _PendingImageProvider(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.pumpWidget(
      _loadingHarness(
        cacheService,
        cacheKey: 'new-image',
        remoteImageProvider: const _PendingImageProvider(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(_loadingIndicator, findsNothing);

    await tester.pump(const Duration(milliseconds: 250));
    expect(_loadingIndicator, findsOneWidget);
  });

  testWidgets('the delayed indicator remains opt-in', (tester) async {
    final cacheService = _ControlledImageCacheService();

    await tester.pumpWidget(
      _loadingHarness(
        cacheService,
        showDelayedLoadingIndicator: false,
        remoteImageProvider: const _PendingImageProvider(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 301));

    expect(_loadingIndicator, findsNothing);
  });

  testWidgets(
    'eager remote first frame settles before cache-backed dimensions exist',
    (tester) async {
      final image = await tester.runAsync(
        () => createTestImage(width: 4, height: 3, cache: false),
      );
      final testImage = image!;
      addTearDown(testImage.dispose);
      final localFile = _createTempPng(tester);
      final cacheService = _ControlledImageCacheService();
      final dimensionProbe = _ControlledDimensionProbe();
      Size? resolvedSize;
      cacheService.completeGetCached('thread-image', null);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageCacheServiceProvider.overrideWithValue(cacheService),
            encodedImageDimensionProbeProvider.overrideWithValue(
              dimensionProbe,
            ),
          ],
          child: LocalizedTestApp(
            home: CachedLibraryImage(
              request: _request('thread-image'),
              fit: BoxFit.cover,
              placeholder: const SizedBox(key: Key('placeholder')),
              showDelayedLoadingIndicator: true,
              remoteImageProviderOverride: _SynchronousImageProvider(testImage),
              onImageResolved: (size) => resolvedSize = size,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(Image), findsOneWidget);
      expect(_loadingIndicator, findsNothing);
      expect(dimensionProbe.calls, 0);

      cacheService.completeEnsure(
        'thread-image',
        CachedImageResult(
          success: true,
          cacheKey: 'thread-image',
          localPath: localFile.path,
        ),
      );
      await tester.pump();

      expect(dimensionProbe.calls, 1);
      expect(resolvedSize, isNull);
      dimensionProbe.complete(const Size(900, 600));
      await tester.pump();

      expect(resolvedSize, const Size(900, 600));
      expect(_loadingIndicator, findsNothing);
    },
  );

  testWidgets(
    'local first frame settles before intrinsic dimension probing completes',
    (tester) async {
      final localFile = _createTempPng(tester);
      final image = await tester.runAsync(
        () => createTestImage(width: 4, height: 3, cache: false),
      );
      final testImage = image!;
      addTearDown(testImage.dispose);
      final cacheService = _ControlledImageCacheService();
      final dimensionProbe = _ControlledDimensionProbe();
      Size? resolvedSize;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageCacheServiceProvider.overrideWithValue(cacheService),
            encodedImageDimensionProbeProvider.overrideWithValue(
              dimensionProbe,
            ),
          ],
          child: LocalizedTestApp(
            home: SizedBox(
              width: 240,
              height: 240,
              child: CachedLibraryImage(
                request: _request('thread-image'),
                preferredLocalPath: localFile.path,
                imageProviderOverride: _SynchronousImageProvider(testImage),
                fit: BoxFit.contain,
                placeholder: const SizedBox(key: Key('placeholder')),
                showDelayedLoadingIndicator: true,
                onImageResolved: (size) => resolvedSize = size,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(Image), findsOneWidget);
      expect(_loadingIndicator, findsNothing);
      expect(dimensionProbe.calls, 1);
      expect(resolvedSize, isNull);

      dimensionProbe.complete(const Size(1200, 1800));
      await tester.pump();

      expect(resolvedSize, const Size(1200, 1800));
      expect(
        cacheService.recordedDimensions['thread-image'],
        const Size(1200, 1800),
      );
      expect(_loadingIndicator, findsNothing);
    },
  );

  testWidgets('dimension probe failure does not turn display into an error', (
    tester,
  ) async {
    final localFile = _createTempPng(tester);
    final image = await tester.runAsync(
      () => createTestImage(width: 4, height: 3, cache: false),
    );
    final testImage = image!;
    addTearDown(testImage.dispose);
    final cacheService = _ControlledImageCacheService();
    var imageFailed = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imageCacheServiceProvider.overrideWithValue(cacheService),
          encodedImageDimensionProbeProvider.overrideWithValue(
            const _FailingDimensionProbe(),
          ),
        ],
        child: LocalizedTestApp(
          home: CachedLibraryImage(
            request: _request('thread-image'),
            preferredLocalPath: localFile.path,
            imageProviderOverride: _SynchronousImageProvider(testImage),
            fit: BoxFit.contain,
            placeholder: const SizedBox(key: Key('placeholder')),
            errorPlaceholder: const SizedBox(key: Key('error-placeholder')),
            showDelayedLoadingIndicator: true,
            onImageResolved: (_) {},
            onImageFailed: () => imageFailed = true,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const Key('error-placeholder')), findsNothing);
    expect(_loadingIndicator, findsNothing);
    expect(imageFailed, isFalse);
  });

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
        child: LocalizedTestApp(
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

  testWidgets(
    'reports a local cache decode failure without exposing its path',
    (tester) async {
      final cacheService = _ControlledImageCacheService();
      final provider = _ControlledImageProvider();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageCacheServiceProvider.overrideWithValue(cacheService),
          ],
          child: LocalizedTestApp(
            home: CachedLibraryImage(
              request: _request('thread-image'),
              fit: BoxFit.cover,
              placeholder: const SizedBox(key: Key('placeholder')),
              errorPlaceholder: const SizedBox(key: Key('error-placeholder')),
              imageProviderOverride: provider,
            ),
          ),
        ),
      );
      await tester.pump();
      provider.fail();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('error-placeholder')), findsOneWidget);
      expect(cacheService.decodeFailures, hasLength(1));
      expect(cacheService.decodeFailures.single.cacheKey, 'thread-image');
    },
  );

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
        child: LocalizedTestApp(
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
    'afterCacheWrite waits for one cache write before showing local image',
    (tester) async {
      final localFile = _createTempPng(tester);
      final image = await tester.runAsync(
        () => createTestImage(width: 4, height: 3, cache: false),
      );
      final testImage = image!;
      addTearDown(testImage.dispose);
      final cacheService = _ControlledImageCacheService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imageCacheServiceProvider.overrideWithValue(cacheService),
          ],
          child: LocalizedTestApp(
            home: CachedLibraryImage(
              request: _request('thread-image'),
              fit: BoxFit.cover,
              placeholder: const SizedBox(key: Key('placeholder')),
              remoteImageProviderOverride: _SynchronousImageProvider(testImage),
              remoteDisplayPolicy:
                  CachedImageRemoteDisplayPolicy.afterCacheWrite,
            ),
          ),
        ),
      );
      await tester.pump();
      cacheService.completeGetCached('thread-image', null);
      await tester.pump();
      await tester.pump();

      expect(cacheService.ensureStarted('thread-image'), isTrue);
      expect(find.byType(Image), findsNothing);

      cacheService.completeEnsure(
        'thread-image',
        CachedImageResult(
          success: true,
          cacheKey: 'thread-image',
          localPath: localFile.path,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(cacheService.getCachedCount('thread-image'), 1);
      expect(find.byType(Image), findsOneWidget);
      expect(
        _underlyingProvider(tester.widget<Image>(find.byType(Image)).image),
        isA<FileImage>(),
      );
    },
  );

  testWidgets('afterCacheWrite failure settles on the error placeholder', (
    tester,
  ) async {
    final cacheService = _ControlledImageCacheService();
    var failedCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [imageCacheServiceProvider.overrideWithValue(cacheService)],
        child: LocalizedTestApp(
          home: CachedLibraryImage(
            request: _request('thread-image'),
            fit: BoxFit.cover,
            placeholder: const SizedBox(key: Key('placeholder')),
            errorPlaceholder: const SizedBox(key: Key('error-placeholder')),
            remoteDisplayPolicy: CachedImageRemoteDisplayPolicy.afterCacheWrite,
            onImageFailed: () => failedCount += 1,
          ),
        ),
      ),
    );
    await tester.pump();
    cacheService.completeGetCached('thread-image', null);
    await tester.pump();
    await tester.pump();
    cacheService.completeEnsure('thread-image', CachedImageResult.failed);
    await tester.pump();
    await tester.pump();

    expect(failedCount, 1);
    expect(find.byKey(const Key('error-placeholder')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
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
          child: LocalizedTestApp(
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
        child: LocalizedTestApp(
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

  testWidgets('ignores stale intrinsic dimensions after request changes', (
    tester,
  ) async {
    final oldFile = _createTempPng(tester);
    final newFile = _createTempPng(tester);
    final image = await tester.runAsync(
      () => createTestImage(width: 4, height: 3, cache: false),
    );
    final testImage = image!;
    addTearDown(testImage.dispose);
    final cacheService = _ControlledImageCacheService();
    final dimensionProbe = _KeyedControlledDimensionProbe();
    final resolvedSizes = <Size>[];

    Widget build(String cacheKey, String localPath) {
      return ProviderScope(
        overrides: [
          imageCacheServiceProvider.overrideWithValue(cacheService),
          encodedImageDimensionProbeProvider.overrideWithValue(dimensionProbe),
        ],
        child: LocalizedTestApp(
          home: CachedLibraryImage(
            request: _request(cacheKey),
            preferredLocalPath: localPath,
            imageProviderOverride: _SynchronousImageProvider(testImage),
            fit: BoxFit.contain,
            placeholder: const SizedBox(key: Key('placeholder')),
            onImageResolved: resolvedSizes.add,
          ),
        ),
      );
    }

    await tester.pumpWidget(build('old-image', oldFile.path));
    await tester.pump();
    await tester.pump();
    expect(dimensionProbe.startedKeys, contains('old-image'));

    await tester.pumpWidget(build('new-image', newFile.path));
    await tester.pump();
    await tester.pump();
    expect(dimensionProbe.startedKeys, contains('new-image'));

    dimensionProbe.complete('old-image', const Size(100, 200));
    await tester.pump();
    expect(resolvedSizes, isEmpty);

    dimensionProbe.complete('new-image', const Size(300, 400));
    await tester.pump();
    expect(resolvedSizes, <Size>[const Size(300, 400)]);
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

Finder get _loadingIndicator =>
    find.byKey(const Key('cached-library-image-loading-indicator'));

Widget _loadingHarness(
  ImageCacheService cacheService, {
  String cacheKey = 'thread-image',
  bool showDelayedLoadingIndicator = true,
  ImageProvider? imageProvider,
  ImageProvider? remoteImageProvider,
}) {
  return ProviderScope(
    overrides: [imageCacheServiceProvider.overrideWithValue(cacheService)],
    child: LocalizedTestApp(
      home: Center(
        child: SizedBox(
          width: 240,
          height: 240,
          child: CachedLibraryImage(
            request: _request(cacheKey),
            fit: BoxFit.contain,
            placeholder: const SizedBox(key: Key('placeholder')),
            errorPlaceholder: const SizedBox(key: Key('error-placeholder')),
            imageProviderOverride: imageProvider,
            showDelayedLoadingIndicator: showDelayedLoadingIndicator,
            remoteImageProviderOverride: remoteImageProvider,
          ),
        ),
      ),
    ),
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

class _ControlledImageCacheService
    implements
        ImageCacheService,
        ImageCacheDecodeFailureReporter,
        ImageCacheDimensionRecorder {
  final Map<String, Completer<CachedImageResult?>> _getCachedCompleters =
      <String, Completer<CachedImageResult?>>{};
  final Map<String, Completer<CachedImageResult>> _ensureCompleters =
      <String, Completer<CachedImageResult>>{};
  final Map<String, int> _getCachedCounts = <String, int>{};
  final List<ImageCacheRequest> decodeFailures = <ImageCacheRequest>[];
  final Map<String, Size> recordedDimensions = <String, Size>{};

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

  @override
  void reportDecodeFailure({
    required ImageCacheRequest request,
    required Object error,
    StackTrace? stackTrace,
  }) {
    decodeFailures.add(request);
  }

  @override
  Future<void> recordResolvedDimensions({
    required String cacheKey,
    required Size size,
  }) async {
    recordedDimensions[cacheKey] = size;
  }
}

class _ControlledDimensionProbe implements EncodedImageDimensionProbe {
  final Completer<Size> _completer = Completer<Size>();
  int calls = 0;

  void complete(Size size) {
    _completer.complete(size);
  }

  @override
  Future<Size> probe({required String cacheKey, required String localPath}) {
    calls += 1;
    return _completer.future;
  }
}

class _FailingDimensionProbe implements EncodedImageDimensionProbe {
  const _FailingDimensionProbe();

  @override
  Future<Size> probe({required String cacheKey, required String localPath}) {
    return Future<Size>.error(StateError('synthetic dimension failure'));
  }
}

class _KeyedControlledDimensionProbe implements EncodedImageDimensionProbe {
  final Map<String, Completer<Size>> _completers = <String, Completer<Size>>{};

  Iterable<String> get startedKeys => _completers.keys;

  void complete(String cacheKey, Size size) {
    _completers[cacheKey]!.complete(size);
  }

  @override
  Future<Size> probe({required String cacheKey, required String localPath}) {
    return _completers.putIfAbsent(cacheKey, Completer<Size>.new).future;
  }
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

class _PendingImageProvider extends ImageProvider<_PendingImageProvider> {
  const _PendingImageProvider();

  @override
  Future<_PendingImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_PendingImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _PendingImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
  }
}

class _ControlledImageProvider extends ImageProvider<_ControlledImageProvider> {
  final Completer<ImageInfo> _completer = Completer<ImageInfo>();

  void fail() {
    _completer.completeError(StateError('image failed'));
  }

  @override
  Future<_ControlledImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_ControlledImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _ControlledImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(_completer.future);
  }
}

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/image_loading/data/app_image_cache_manager.dart';
import 'package:y300/features/image_loading/data/app_image_providers.dart';

void main() {
  testWidgets('network image waits for the shared cache manager', (
    tester,
  ) async {
    final manager = Completer<AppImageCacheManager>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appImageCacheManagerProvider.overrideWith((ref) => manager.future),
        ],
        child: const LocalizedTestApp(
          home: LibraryCachedImage(
            imageUrl: 'https://bbs.yamibo.com/data/attachment/test.jpg',
            fit: BoxFit.cover,
            placeholder: SizedBox(key: Key('placeholder')),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('placeholder')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('svg remote url shows fallback instead of NetworkImage', (
    tester,
  ) async {
    await tester.pumpWidget(
      const LocalizedTestApp(
        home: LibraryCachedImage(
          imageUrl: 'https://bbs.yamibo.com/uc_server/data/avatar/noavatar.svg',
          fit: BoxFit.cover,
          placeholder: SizedBox(key: Key('placeholder')),
          errorPlaceholder: SizedBox(key: Key('svg-fallback')),
        ),
      ),
    );

    expect(find.byKey(const Key('svg-fallback')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('local image reports decoded dimensions', (tester) async {
    final image = await tester.runAsync(
      () => createTestImage(width: 3, height: 5, cache: false),
    );
    final testImage = image!;
    addTearDown(testImage.dispose);
    final provider = _SynchronousImageProvider(testImage);

    Size? resolvedSize;
    await tester.pumpWidget(
      LocalizedTestApp(
        home: LibraryCachedImage(
          imageProviderOverride: provider,
          fit: BoxFit.cover,
          placeholder: const SizedBox(key: Key('placeholder')),
          onImageResolved: (size) => resolvedSize = size,
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(resolvedSize, const Size(3, 5));
  });

  testWidgets('keeps the placeholder until an override emits its first frame', (
    tester,
  ) async {
    final image = await tester.runAsync(
      () => createTestImage(width: 3, height: 5, cache: false),
    );
    final testImage = image!;
    addTearDown(testImage.dispose);
    final provider = _DeferredImageProvider();

    await tester.pumpWidget(
      LocalizedTestApp(
        home: LibraryCachedImage(
          imageProviderOverride: provider,
          fit: BoxFit.cover,
          placeholder: const SizedBox(key: Key('placeholder')),
        ),
      ),
    );

    expect(find.byKey(const Key('placeholder')), findsOneWidget);

    provider.complete(testImage);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('placeholder')), findsNothing);
    expect(find.byType(RawImage), findsOneWidget);
  });

  testWidgets('cross-fades an asynchronously decoded first frame', (
    tester,
  ) async {
    final image = await tester.runAsync(
      () => createTestImage(width: 3, height: 5, cache: false),
    );
    final testImage = image!;
    addTearDown(testImage.dispose);
    final provider = _DeferredImageProvider();

    await tester.pumpWidget(
      LocalizedTestApp(
        home: LibraryCachedImage(
          imageProviderOverride: provider,
          fit: BoxFit.cover,
          placeholder: const SizedBox(key: Key('placeholder')),
          fadeInDuration: const Duration(milliseconds: 120),
        ),
      ),
    );

    provider.complete(testImage);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('placeholder')), findsOneWidget);
    expect(find.byType(RawImage), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byKey(const Key('placeholder')), findsOneWidget);
    expect(find.byType(RawImage), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byKey(const Key('placeholder')), findsNothing);
    expect(find.byType(RawImage), findsOneWidget);
  });

  testWidgets('shows a synchronously cached frame without fading', (
    tester,
  ) async {
    final image = await tester.runAsync(
      () => createTestImage(width: 3, height: 5, cache: false),
    );
    final testImage = image!;
    addTearDown(testImage.dispose);

    await tester.pumpWidget(
      LocalizedTestApp(
        home: LibraryCachedImage(
          imageProviderOverride: _SynchronousImageProvider(testImage),
          fit: BoxFit.cover,
          placeholder: const SizedBox(key: Key('placeholder')),
          fadeInDuration: const Duration(milliseconds: 120),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('placeholder')), findsNothing);
    expect(find.byType(RawImage), findsOneWidget);
  });

  testWidgets('disables the first-frame fade when animations are disabled', (
    tester,
  ) async {
    final image = await tester.runAsync(
      () => createTestImage(width: 3, height: 5, cache: false),
    );
    final testImage = image!;
    addTearDown(testImage.dispose);
    final provider = _DeferredImageProvider();

    await tester.pumpWidget(
      LocalizedTestApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: LibraryCachedImage(
            imageProviderOverride: provider,
            fit: BoxFit.cover,
            placeholder: const SizedBox(key: Key('placeholder')),
            fadeInDuration: const Duration(milliseconds: 120),
          ),
        ),
      ),
    );

    provider.complete(testImage);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('placeholder')), findsNothing);
    expect(find.byType(RawImage), findsOneWidget);
  });

  testWidgets('does not replay the fade for an unchanged image source', (
    tester,
  ) async {
    final image = await tester.runAsync(
      () => createTestImage(width: 3, height: 5, cache: false),
    );
    final testImage = image!;
    addTearDown(testImage.dispose);
    final provider = _DeferredImageProvider();

    Widget build() {
      return LocalizedTestApp(
        home: LibraryCachedImage(
          imageProviderOverride: provider,
          fit: BoxFit.cover,
          placeholder: const SizedBox(key: Key('placeholder')),
          fadeInDuration: const Duration(milliseconds: 120),
        ),
      );
    }

    await tester.pumpWidget(build());
    provider.complete(testImage);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(build());
    await tester.pump();

    expect(find.byKey(const Key('placeholder')), findsNothing);
    expect(find.byType(RawImage), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('bumping retryToken re-resolves a failed remote image', (
    tester,
  ) async {
    final image = await tester.runAsync(
      () => createTestImage(width: 3, height: 5, cache: false),
    );
    final testImage = image!;
    addTearDown(testImage.dispose);
    final provider = _FailThenSucceedImageProvider(testImage);

    Widget build(int retryToken) {
      return LocalizedTestApp(
        home: Center(
          child: SizedBox(
            width: 120,
            height: 200,
            child: LibraryCachedImage(
              imageUrl: 'https://bbs.yamibo.com/data/attachment/retry.jpg',
              remoteImageProviderOverride: provider,
              fit: BoxFit.cover,
              placeholder: const SizedBox(key: Key('placeholder')),
              errorPlaceholder: const SizedBox(key: Key('error')),
              retryToken: retryToken,
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(build(0));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('error')), findsOneWidget);
    expect(provider.loadCount, 1);

    // 失败后驱逐是异步微任务，先放行一帧再重试，模拟真实用户点击时序。
    await tester.pump();

    await tester.pumpWidget(build(1));
    await tester.pump();
    await tester.pump();

    expect(provider.loadCount, 2);
    expect(find.byKey(const Key('error')), findsNothing);
    expect(find.byType(RawImage), findsOneWidget);
  });

  testWidgets('retry also recovers an un-downscaled image', (tester) async {
    final image = await tester.runAsync(
      () => createTestImage(width: 3, height: 5, cache: false),
    );
    final testImage = image!;
    addTearDown(testImage.dispose);
    final provider = _FailThenSucceedImageProvider(testImage);

    // 横向无界 → 解码目标为 none → provider 不被 ResizeImage 包装。这条路径下
    // 失败的 completer 会滞留在图片缓存 pending 表中，只有显式驱逐才能重试。
    Widget build(int retryToken) {
      return LocalizedTestApp(
        home: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: LibraryCachedImage(
            imageUrl: 'https://bbs.yamibo.com/data/attachment/bare.jpg',
            remoteImageProviderOverride: provider,
            fit: BoxFit.cover,
            placeholder: const SizedBox(key: Key('placeholder')),
            errorPlaceholder: const SizedBox(key: Key('error')),
            retryToken: retryToken,
          ),
        ),
      );
    }

    await tester.pumpWidget(build(0));
    await tester.pump();
    await tester.pump();

    final displayed = tester.widget<Image>(find.byType(Image));
    expect(
      displayed.image,
      isA<_FailThenSucceedImageProvider>(),
      reason: '该布局下不应发生降采样包装，否则这条用例没有覆盖到目标路径',
    );
    expect(provider.loadCount, 1);

    await tester.pump();
    await tester.pumpWidget(build(1));
    await tester.pump();
    await tester.pump();

    expect(provider.loadCount, 2);
    expect(find.byType(RawImage), findsOneWidget);
  });

  testWidgets('an unchanged retryToken does not reload a settled image', (
    tester,
  ) async {
    final image = await tester.runAsync(
      () => createTestImage(width: 3, height: 5, cache: false),
    );
    final testImage = image!;
    addTearDown(testImage.dispose);
    final provider = _CountingImageProvider(testImage);

    Widget build() {
      return LocalizedTestApp(
        home: Center(
          child: SizedBox(
            width: 120,
            height: 200,
            child: LibraryCachedImage(
              imageUrl: 'https://bbs.yamibo.com/data/attachment/stable.jpg',
              remoteImageProviderOverride: provider,
              fit: BoxFit.cover,
              placeholder: const SizedBox(key: Key('placeholder')),
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(build());
    await tester.pump();
    await tester.pump();
    final settledCount = provider.loadCount;

    await tester.pumpWidget(build());
    await tester.pump();

    expect(provider.loadCount, settledCount);
  });
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

/// 第一次解码失败、之后成功，用来观察重试是否真的重新触发了一次解码。
class _FailThenSucceedImageProvider
    extends ImageProvider<_FailThenSucceedImageProvider> {
  _FailThenSucceedImageProvider(this.image);

  final ui.Image image;
  int loadCount = 0;

  @override
  Future<_FailThenSucceedImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture<_FailThenSucceedImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _FailThenSucceedImageProvider key,
    ImageDecoderCallback decode,
  ) {
    loadCount += 1;
    if (loadCount == 1) {
      return OneFrameImageStreamCompleter(
        Future<ImageInfo>.error(StateError('boom')),
      );
    }
    return OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(ImageInfo(image: image.clone())),
    );
  }
}

class _CountingImageProvider extends ImageProvider<_CountingImageProvider> {
  _CountingImageProvider(this.image);

  final ui.Image image;
  int loadCount = 0;

  @override
  Future<_CountingImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_CountingImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _CountingImageProvider key,
    ImageDecoderCallback decode,
  ) {
    loadCount += 1;
    return OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(ImageInfo(image: image.clone())),
    );
  }
}

class _DeferredImageProvider extends ImageProvider<_DeferredImageProvider> {
  final Completer<ImageInfo> _completer = Completer<ImageInfo>();

  void complete(ui.Image image) {
    _completer.complete(ImageInfo(image: image));
  }

  @override
  Future<_DeferredImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_DeferredImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _DeferredImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(_completer.future);
  }
}

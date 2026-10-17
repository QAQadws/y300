import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/media/encoded_image_dimension_probe.dart';
import 'package:y300/core/media/image_display_provider.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_dimension_index.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/services/default_forum_image_precache_service.dart';
import 'package:y300/features/cache/presentation/widgets/image_retry_placeholder.dart';
import 'package:y300/features/content_rendering_shared/application/host/cache_forum_html_image_host.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/thread/presentation/services/thread_image_preload_policy.dart';

import '../../../../test_support/localized_test_app.dart';
import 'forum_html_test_theme.dart';

void main() {
  testWidgets('first PNG keeps its bounds while delayed loading settles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2100);
    addTearDown(tester.view.resetPhysicalSize);
    final ready = Completer<void>();
    final probe = _ControlledDimensionProbe();
    final fixture = await _mountVisibleImage(
      tester,
      intrinsicSize: const Size(1000, 1501),
      displayWidth: 340,
      viewportHeight: 650,
      devicePixelRatio: 3,
      waitForFile: ready.future,
      waitForFirstFrame: false,
      dimensionProbe: probe,
      htmlPrefix:
          '<font size="5"><span style="background-color:#eeeeaa">'
          '翻译：译者<br>校对：校对者<br>嵌字：嵌字者</span></font><br><br>',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.byKey(const Key('cached-library-image-loading-indicator')),
      findsOneWidget,
    );
    final placeholderBounds = tester.getRect(fixture.imageRoot);
    expect(fixture.frame, findsNothing);
    ready.complete();

    var renderedFrames = 0;
    for (var pump = 0; pump < 40; pump++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
      final bounds = tester.getRect(fixture.imageRoot);
      expect(bounds.top, closeTo(placeholderBounds.top, 0.001));
      expect(bounds.width, closeTo(placeholderBounds.width, 0.001));
      if (fixture.frame.evaluate().isEmpty) continue;
      final bitmap = tester.widget<RawImage>(fixture.frame).image;
      if (bitmap == null) continue;
      final paint = _imagePaintGeometry(tester, fixture.frame);
      expect(paint.destination.top, closeTo(placeholderBounds.top, 0.001));
      expect(paint.destination.width, closeTo(placeholderBounds.width, 0.001));
      renderedFrames++;
      if (renderedFrames == 1) {
        expect(
          find.byKey(const Key('cached-library-image-loading-indicator')),
          findsOneWidget,
        );
        probe.complete(const Size(1000, 1501));
      }
    }
    expect(renderedFrames, greaterThan(1));
    expect(
      find.byKey(const Key('cached-library-image-loading-indicator')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  for (final originalSize in [const Size(1000, 1501), const Size(1001, 600)]) {
    testWidgets(
      'first PNG painted top stays anchored when '
      '${originalSize.width.toInt()}x${originalSize.height.toInt()} dimensions arrive',
      (tester) async {
        final probe = _ControlledDimensionProbe();
        final fixture = await _mountVisibleImage(
          tester,
          dimensionProbe: probe,
          intrinsicSize: originalSize,
          displayWidth: 360,
          devicePixelRatio: 2,
          maxDecodedBytesPerImage: 4000000,
        );
        final imageElement = tester.element(fixture.image);
        final bitmap = tester.widget<RawImage>(fixture.frame).image!;
        final provider = tester.widget<Image>(fixture.image).image;
        final key = await provider.obtainKey(ImageConfiguration.empty);
        final top = tester.getTopLeft(fixture.imageRoot).dy;
        expect(probe.requests, 1);
        expect(bitmap.width, 720);
        final firstPaint = _imagePaintGeometry(tester, fixture.frame);
        expect(firstPaint.destination.top, closeTo(top, 0.001));
        expect(
          firstPaint.source.top,
          closeTo(0, 0.001),
          reason: 'fallback height must not crop away the original top',
        );

        // The encoded ratio recovers after the first frame; integer resize
        // dimensions differ slightly from it. Compare painting, not just layout.
        probe.complete(originalSize);
        for (var frame = 0; frame < 8; frame++) {
          await tester.pump();
          expect(tester.getTopLeft(fixture.imageRoot).dy, closeTo(top, 0.001));
          final paint = _imagePaintGeometry(tester, fixture.frame);
          expect(
            paint.destination.top,
            closeTo(top, 0.001),
            reason: 'the recovered height must not shift the painted top',
          );
          expect(paint.source.top, closeTo(0, 0.001));
          expect(tester.element(fixture.image), same(imageElement));
          expect(tester.widget<RawImage>(fixture.frame).image, same(bitmap));
          expect(
            await tester
                .widget<Image>(fixture.image)
                .image
                .obtainKey(ImageConfiguration.empty),
            key,
          );
        }
        expect(
          tester.getSize(fixture.imageRoot).height,
          closeTo(360 / originalSize.aspectRatio, 0.001),
        );
        expect(probe.requests, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'visible PNG keeps its first frame while missing dimensions arrive',
    (tester) async {
      final probe = _ControlledDimensionProbe();
      final fixture = await _mountVisibleImage(tester, dimensionProbe: probe);
      expect(probe.requests, 1);
      expect(
        tester.getSize(fixture.imageRoot).height,
        closeTo(200 / 0.7, 0.01),
      );
      final imageElement = tester.element(fixture.image);
      expect(tester.widget<RawImage>(fixture.frame).image, isNotNull);

      // The production display probes missing metadata only after its first
      // frame. Complete that independent probe after the picture is painted.
      probe.complete(const Size(400, 200));
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump();
        expect(fixture.image, findsOneWidget);
        expect(tester.element(fixture.image), same(imageElement));
        expect(tester.widget<RawImage>(fixture.frame).image, isNotNull);
      }
      expect(tester.getSize(fixture.imageRoot).height, closeTo(100, 0.01));
      expect(probe.requests, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'visibly loaded PNG stays mounted during subpixel viewport edge crossings',
    (tester) async {
      final fixture = await _mountVisibleImage(
        tester,
        explicitDimensions: true,
      );
      final imageElement = tester.element(fixture.image);
      expect(tester.widget<RawImage>(fixture.frame).image, isNotNull);
      final leavingOffset = tester.getBottomLeft(fixture.imageRoot).dy;

      // This picture loaded through normal visible display; the Host has no
      // optional predecode service, so no successful prewarm can retain it.
      for (final delta in [0.5, -0.5, 0.5, -0.5, 0.5]) {
        fixture.controller.jumpTo(leavingOffset + delta);
        for (var frame = 0; frame < 3; frame++) {
          await tester.pump();
          expect(fixture.image, findsOneWidget);
          expect(tester.element(fixture.image), same(imageElement));
          expect(tester.widget<RawImage>(fixture.frame).image, isNotNull);
        }
      }
      expect(TickerMode.valuesOf(imageElement).enabled, isFalse);
      fixture.controller.jumpTo(0);
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump();
        expect(tester.element(fixture.image), same(imageElement));
        expect(tester.widget<RawImage>(fixture.frame).image, isNotNull);
      }
      expect(TickerMode.valuesOf(imageElement).enabled, isTrue);
      fixture.controller.jumpTo(fixture.controller.position.maxScrollExtent);
      await tester.pump();
      await tester.pump();
      expect(fixture.image, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed visible image keeps retry without retaining a frame', (
    tester,
  ) async {
    final fixture = await _mountVisibleImage(
      tester,
      explicitDimensions: true,
      failLoad: true,
    );
    final retry = find.descendant(
      of: fixture.imageRoot,
      matching: find.byType(ImageRetryPlaceholder),
    );
    expect(retry, findsOneWidget);
    expect(fixture.frame, findsNothing);
    final leavingOffset = tester.getBottomLeft(fixture.imageRoot).dy;
    fixture.controller.jumpTo(leavingOffset + 0.5);
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump();
    }
    expect(retry, findsNothing);
    fixture.controller.jumpTo(0);
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump();
    }
    expect(retry, findsOneWidget);
    expect(fixture.frame, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('visible PNG over retention budget is released offscreen', (
    tester,
  ) async {
    final fixture = await _mountVisibleImage(
      tester,
      explicitDimensions: true,
      maxDecodedBytesPerImage: 10000,
    );
    expect(tester.widget<RawImage>(fixture.frame).image, isNotNull);
    final leavingOffset = tester.getBottomLeft(fixture.imageRoot).dy;
    fixture.controller.jumpTo(leavingOffset + 0.5);
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump();
    }
    expect(fixture.image, findsNothing);
    expect(fixture.frame, findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final scenario in [
    (animated: false, highDpr: false),
    (animated: true, highDpr: false),
    (animated: false, highDpr: true),
  ]) {
    final animated = scenario.animated;
    final highDpr = scenario.highDpr;
    final devicePixelRatio = highDpr ? 4.0 : 1.0;
    final displayWidth = highDpr ? 336.0 : 200.0;
    final viewportHeight = highDpr ? 400.0 : 250.0;
    final imageHeight = highDpr ? 483.0 : 100.0;
    final firstImageHeight = highDpr ? imageHeight : 300.0;
    final intrinsicSize = highDpr
        ? const Size(2688, 3860)
        : animated
        ? const Size(1, 1)
        : const Size(400, 200);
    testWidgets(
      'prepared ${highDpr ? 'high-DPR ' : ''}${animated ? 'GIF' : 'PNG'} keeps its rendered frame across viewport edges',
      (tester) async {
        tester.view.devicePixelRatio = devicePixelRatio;
        addTearDown(tester.view.resetDevicePixelRatio);
        if (highDpr) {
          tester.view.physicalSize = const Size(1440, 2560);
          addTearDown(tester.view.resetPhysicalSize);
        }
        final extension = animated ? 'gif' : 'png';
        final directory = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('y300-predecode-'),
        ))!;
        addTearDown(() async {
          await directory.delete(recursive: true);
        });
        final paths = await tester.runAsync(() async {
          final bytes = await _imageBytes(
            animated: animated,
            size: intrinsicSize,
          );
          return [
            for (var i = 0; i < 8; i++)
              (await File('${directory.path}/$i.$extension')
                      .writeAsBytes(bytes))
                  .path,
          ];
        });
        final cache = _FileCache(paths!, intrinsicSize: intrinsicSize);
        final decodedKeys = <Object>[];
        final service = DefaultForumImagePrecacheService(
          imageCacheService: cache,
          imageRequestResolver: const DefaultForumImageRequestResolver(),
          precacheInvoker: (provider, config) async {
            decodedKeys.add(await provider.obtainKey(config));
            await defaultForumImagePrecacheInvoker(provider, config);
          },
        );
        final host = CacheForumHtmlImageHost(
          dimensionIndex: CacheRecordForumImageDimensionIndex(
            imageCacheService: cache,
            imageRequestResolver: const DefaultForumImageRequestResolver(),
          ),
        ).forContent(threadId: '100', imagePrecacheService: service);
        final coordinator = ForumHtmlImageViewportCoordinator(
          predecodePolicy: highDpr
              ? ThreadImagePreloadPolicy(
                  imageCacheBudgetBytes: 64 * 1024 * 1024,
                  isLowRamDevice: false,
                ).predecode
              : const ForumHtmlImagePredecodePolicy(
                  maxDecodedBytesPerImage: 1000000,
                ),
        );
        final controller = ScrollController();
        addTearDown(coordinator.dispose);
        addTearDown(controller.dispose);
        addTearDown(() {
          PaintingBinding.instance.imageCache.clear();
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [imageCacheServiceProvider.overrideWithValue(cache)],
            child: LocalizedTestApp(
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: displayWidth,
                    height: viewportHeight,
                    child: SingleChildScrollView(
                      controller: controller,
                      child: ForumHtmlWidgetPostRenderer(
                        html: [
                          for (var i = 0; i < paths.length; i++)
                            '<div><img src="https://example.invalid/$i.$extension" '
                                'width="${displayWidth.toInt()}" '
                                'height="${(i == 0 ? firstImageHeight : imageHeight).toInt()}"></div>',
                        ].join(),
                        sourceId: 'real-predecode',
                        theme: forumHtmlTestTheme,
                        buildAsync: false,
                        imageHost: host,
                        imageViewportCoordinator: coordinator,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 30; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(decodedKeys, hasLength(2));
        final next = find.byKey(
          const Key('thread-post-html-first-readable-image-real-predecode-1'),
        );
        expect(tester.getTopLeft(next).dy, greaterThan(viewportHeight));
        final nextImage = find.descendant(
          of: next,
          matching: find.byType(Image),
        );
        final nextFrame = find.descendant(
          of: next,
          matching: find.byType(RawImage),
        );
        expect(nextImage, findsOneWidget);
        expect(tester.widget<RawImage>(nextFrame).image, isNotNull);
        if (highDpr) {
          expect(tester.widget<RawImage>(nextFrame).image!.width, 1344);
        }
        final imageElement = tester.element(nextImage);
        expect(TickerMode.valuesOf(imageElement).enabled, isFalse);
        final pausedFrame = tester.widget<RawImage>(nextFrame).image;
        await tester.pump(const Duration(milliseconds: 500));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        expect(tester.widget<RawImage>(nextFrame).image, same(pausedFrame));
        final enteringOffset = tester.getTopLeft(next).dy - viewportHeight;
        for (final delta in [0.5, -0.5, 0.5, -0.5, 0.5]) {
          controller.jumpTo(enteringOffset + delta);
          for (var frame = 0; frame < 3; frame++) {
            await tester.pump();
            expect(tester.element(nextImage), same(imageElement));
            expect(tester.widget<RawImage>(nextFrame).image, isNotNull);
          }
        }
        expect(TickerMode.valuesOf(imageElement).enabled, isTrue);
        final display = resolveDownscaledFileImageProvider(
          localPath: paths[1],
          fit: BoxFit.fitWidth,
          displaySize: Size(displayWidth, imageHeight),
          devicePixelRatio: devicePixelRatio,
        );
        final key = await display.obtainKey(ImageConfiguration.empty);
        expect(decodedKeys, contains(key));
        expect(
          PaintingBinding.instance.imageCache.statusForKey(key).keepAlive,
          isTrue,
        );
        var synchronous = false;
        final stream = display.resolve(ImageConfiguration.empty);
        final listener = ImageStreamListener((image, sync) {
          synchronous = sync;
          image.dispose();
        });
        stream.addListener(listener);
        expect(synchronous, isTrue);
        stream.removeListener(listener);
        controller.jumpTo(200);
        for (var i = 0; i < 5; i++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        final visibleProviders = tester
            .widgetList<Image>(find.byType(Image))
            .map((image) => image.image);
        expect(visibleProviders, contains(display));
        expect(decodedKeys.where((value) => value == key), hasLength(1));
        controller.jumpTo(controller.position.maxScrollExtent);
        for (var i = 0; i < 5; i++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        expect(nextImage, findsNothing);
        coordinator.setActive(false);
        await tester.pump();
        expect(find.byType(Image), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        // Native codecs can still hold their encoded file until pending reads
        // and image-cache disposal finish, especially for animated GIFs.
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      },
    );
  }
}

Future<_VisibleImageFixture> _mountVisibleImage(
  WidgetTester tester, {
  bool explicitDimensions = false,
  bool failLoad = false,
  int maxDecodedBytesPerImage = 1000000,
  EncodedImageDimensionProbe? dimensionProbe,
  Size intrinsicSize = const Size(400, 200),
  double displayWidth = 200,
  double viewportHeight = 250,
  double devicePixelRatio = 1,
  Future<void>? waitForFile,
  bool waitForFirstFrame = true,
  String htmlPrefix = '',
}) async {
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.resetDevicePixelRatio);
  final directory = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('y300-visible-frame-'),
  ))!;
  final path = (await tester.runAsync(() async {
    final bytes = await _imageBytes(animated: false, size: intrinsicSize);
    return (await File('${directory.path}/image.png').writeAsBytes(bytes)).path;
  }))!;
  final cache = _FileCache(
    [path],
    intrinsicSize: explicitDimensions ? intrinsicSize : null,
    failRequests: failLoad,
    waitForFile: waitForFile,
  );
  final host = CacheForumHtmlImageHost(
    dimensionIndex: CacheRecordForumImageDimensionIndex(
      imageCacheService: cache,
      imageRequestResolver: const DefaultForumImageRequestResolver(),
    ),
  ).forContent(threadId: '100');
  final coordinator = ForumHtmlImageViewportCoordinator(
    predecodePolicy: ForumHtmlImagePredecodePolicy(
      maxDecodedBytesPerImage: maxDecodedBytesPerImage,
    ),
  );
  final controller = ScrollController();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    coordinator.dispose();
    controller.dispose();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.runAsync(() => directory.delete(recursive: true));
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        imageCacheServiceProvider.overrideWithValue(cache),
        if (dimensionProbe != null)
          encodedImageDimensionProbeProvider.overrideWithValue(dimensionProbe),
      ],
      child: LocalizedTestApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: displayWidth,
              height: viewportHeight,
              child: SingleChildScrollView(
                controller: controller,
                child: Column(
                  children: [
                    ForumHtmlWidgetPostRenderer(
                      html:
                          '$htmlPrefix<img src="https://example.invalid/0.png" '
                          '${explicitDimensions ? 'width="${intrinsicSize.width}" height="${intrinsicSize.height}"' : ''}>',
                      sourceId: 'visible-frame',
                      theme: forumHtmlTestTheme,
                      buildAsync: false,
                      imageHost: host,
                      imageViewportCoordinator: coordinator,
                    ),
                    const SizedBox(height: 1000),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; waitForFirstFrame && i < 30; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  final imageRoot = find.byKey(
    const Key('thread-post-html-first-readable-image-visible-frame-0'),
  );
  final image = find.descendant(of: imageRoot, matching: find.byType(Image));
  final frame = find.descendant(of: imageRoot, matching: find.byType(RawImage));
  if (!waitForFirstFrame || failLoad) {
    expect(frame, findsNothing);
  } else {
    expect(image, findsOneWidget);
    expect(tester.widget<RawImage>(frame).image, isNotNull);
  }
  return _VisibleImageFixture(controller, imageRoot, image, frame);
}

({Rect source, Rect destination}) _imagePaintGeometry(
  WidgetTester tester,
  Finder frame,
) {
  final raw = tester.widget<RawImage>(frame);
  final bitmap = raw.image!;
  final sourceSize = Size(bitmap.width / raw.scale, bitmap.height / raw.scale);
  final fitted = applyBoxFit(raw.fit!, sourceSize, tester.getSize(frame));
  final alignment = raw.alignment.resolve(TextDirection.ltr);
  final destination = alignment.inscribe(
    fitted.destination,
    Offset.zero & tester.getSize(frame),
  );
  return (
    source: alignment.inscribe(fitted.source, Offset.zero & sourceSize),
    destination: destination.shift(tester.getTopLeft(frame)),
  );
}

class _VisibleImageFixture {
  const _VisibleImageFixture(
    this.controller,
    this.imageRoot,
    this.image,
    this.frame,
  );

  final ScrollController controller;
  final Finder imageRoot;
  final Finder image;
  final Finder frame;
}

class _ControlledDimensionProbe implements EncodedImageDimensionProbe {
  final _result = Completer<Size>();
  var requests = 0;

  void complete(Size size) => _result.complete(size);

  @override
  Future<Size> probe({required String cacheKey, required String localPath}) {
    requests++;
    return _result.future;
  }
}

Future<List<int>> _imageBytes({
  required bool animated,
  Size size = const Size(400, 200),
}) async {
  if (animated) {
    // A looping 1x1 red/green GIF with two 100 ms frames.
    final bytes = Uint8List.fromList([
      ...'GIF89a'.codeUnits,
      1,
      0,
      1,
      0,
      0x80,
      0,
      0,
      255,
      0,
      0,
      0,
      255,
      0,
      0x21,
      0xff,
      11,
      ...'NETSCAPE2.0'.codeUnits,
      3,
      1,
      0,
      0,
      0,
      for (final pixel in [0x44, 0x4c]) ...[
        0x21,
        0xf9,
        4,
        0,
        10,
        0,
        0,
        0,
        0x2c,
        0,
        0,
        0,
        0,
        1,
        0,
        1,
        0,
        0,
        2,
        2,
        pixel,
        1,
        0,
      ],
      0x3b,
    ]);
    final codec = await ui.instantiateImageCodec(bytes);
    expect(codec.frameCount, 2);
    codec.dispose();
    return bytes;
  }
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(Offset.zero & size, Paint()..color = Colors.red);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

class _FileCache implements ImageCacheService {
  _FileCache(
    this.paths, {
    required this.intrinsicSize,
    this.failRequests = false,
    this.waitForFile,
  });
  final List<String> paths;
  final Size? intrinsicSize;
  final bool failRequests;
  final Future<void>? waitForFile;
  final records = <String, CachedImageResult>{};
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    await waitForFile;
    return failRequests
        ? CachedImageResult.failed
        : records.putIfAbsent(
            request.cacheKey,
            () => CachedImageResult(
              success: true,
              cacheKey: request.cacheKey,
              localPath: paths[request.imageIndex!],
              width: intrinsicSize?.width.toInt(),
              height: intrinsicSize?.height.toInt(),
              fromCache: true,
            ),
          );
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async =>
      records[cacheKey];
  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async => CachedImageResult.failed;
  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async => 0;
  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;
  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}
  @override
  Future<void> clearUnprotected() async {}
  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async => 0;
}

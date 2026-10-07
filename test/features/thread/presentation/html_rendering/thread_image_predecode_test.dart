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

import '../../../../test_support/localized_test_app.dart';
import 'forum_html_test_theme.dart';

void main() {
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

  for (final animated in [false, true]) {
    testWidgets(
      'prepared ${animated ? 'GIF' : 'PNG'} keeps its rendered frame across viewport edges',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        final extension = animated ? 'gif' : 'png';
        final directory = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('y300-predecode-'),
        ))!;
        addTearDown(() async {
          await directory.delete(recursive: true);
        });
        final paths = await tester.runAsync(() async {
          final bytes = await _imageBytes(animated: animated);
          return [
            for (var i = 0; i < 8; i++)
              (await File(
                '${directory.path}/$i.$extension',
              ).writeAsBytes(bytes)).path,
          ];
        });
        final cache = _FileCache(
          paths!,
          intrinsicSize: animated ? const Size(1, 1) : const Size(400, 200),
        );
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
          predecodePolicy: const ForumHtmlImagePredecodePolicy(
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
                    width: 200,
                    height: 250,
                    child: SingleChildScrollView(
                      controller: controller,
                      child: ForumHtmlWidgetPostRenderer(
                        html: [
                          for (var i = 0; i < paths.length; i++)
                            '<div><img src="https://example.invalid/$i.$extension" '
                                'width="200" height="${i == 0 ? 300 : 100}"></div>',
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
        expect(tester.getTopLeft(next).dy, greaterThan(250));
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
        final imageElement = tester.element(nextImage);
        expect(TickerMode.valuesOf(imageElement).enabled, isFalse);
        final pausedFrame = tester.widget<RawImage>(nextFrame).image;
        await tester.pump(const Duration(milliseconds: 500));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        expect(tester.widget<RawImage>(nextFrame).image, same(pausedFrame));
        final enteringOffset = tester.getTopLeft(next).dy - 250;
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
          displaySize: const Size(200, 100),
          devicePixelRatio: 1,
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
}) async {
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetDevicePixelRatio);
  final directory = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('y300-visible-frame-'),
  ))!;
  final path = (await tester.runAsync(() async {
    final bytes = await _imageBytes(animated: false);
    return (await File('${directory.path}/image.png').writeAsBytes(bytes)).path;
  }))!;
  final cache = _FileCache(
    [path],
    intrinsicSize: explicitDimensions ? const Size(400, 200) : null,
    failRequests: failLoad,
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
              width: 200,
              height: 250,
              child: SingleChildScrollView(
                controller: controller,
                child: Column(
                  children: [
                    ForumHtmlWidgetPostRenderer(
                      html:
                          '<img src="https://example.invalid/0.png" '
                          '${explicitDimensions ? 'width="200" height="100"' : ''}>',
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
  for (var i = 0; i < 30; i++) {
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
  if (failLoad) {
    expect(frame, findsNothing);
  } else {
    expect(image, findsOneWidget);
    expect(tester.widget<RawImage>(frame).image, isNotNull);
  }
  return _VisibleImageFixture(controller, imageRoot, image, frame);
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

Future<List<int>> _imageBytes({required bool animated}) async {
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
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 400, 200), Paint()..color = Colors.red);
  final picture = recorder.endRecording();
  final image = await picture.toImage(400, 200);
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
  });
  final List<String> paths;
  final Size? intrinsicSize;
  final bool failRequests;
  final records = <String, CachedImageResult>{};
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async =>
      failRequests
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

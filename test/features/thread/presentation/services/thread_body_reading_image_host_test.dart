import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/thread/presentation/services/thread_body_reading_image_host.dart';

import '../html_rendering/forum_html_test_theme.dart';

void main() {
  test(
    'dimension promotion forwards the optional port and falls back for legacy Hosts',
    () async {
      final tracker = ThreadBodyReadingImageTracker(() {});
      addTearDown(tracker.dispose);
      final delegate = _PriorityHost();
      final host = ThreadBodyReadingImageHost(
        delegate: delegate,
        tracker: tracker,
      );
      final image = _Image('forwarded');
      final initial = host.loadDimensions(image);
      final promoted = host.loadDimensionsWithPriority(
        image,
        priority: ForumHtmlImageDimensionPriority.visible,
      );
      expect(promoted, same(initial));
      expect(delegate.priorities, [
        ForumHtmlImageDimensionPriority.background,
        ForumHtmlImageDimensionPriority.visible,
      ]);
      delegate.pending.values.single.complete(_dimensions);
      expect((await promoted)?.size, const Size(400, 200));

      final legacy = _Host();
      final legacyWrapper = ThreadBodyReadingImageHost(
        delegate: legacy,
        tracker: tracker,
      );
      expect(
        await legacyWrapper.loadDimensionsWithPriority(
          image,
          priority: ForumHtmlImageDimensionPriority.visible,
        ),
        isNull,
      );
      expect(legacy.dimensionCalls, 1);
    },
  );

  for (final sizeCallbackFirst in [false, true]) {
    testWidgets(
      'source reading preserves late-hint compensation and old bindings: size callback first=$sizeCallbackFirst',
      (tester) async {
        final tracker = ThreadBodyReadingImageTracker(() {});
        addTearDown(tracker.dispose);
        final viewport = ForumHtmlImageViewportCoordinator();
        addTearDown(viewport.dispose);
        final oldDelegate = _PriorityHost();
        final currentDelegate = _PriorityHost();
        final shifts = <ForumHtmlImageLayoutShift>[];
        final viewportKey = GlobalKey();
        final document = const DefaultForumHtmlRenderPreparer().prepare(
          html:
              '<img src="https://bbs.yamibo.com/data/attachment/forum/one.jpg">',
          preferences: ForumHtmlReaderPreferences.defaults(),
          theme: forumHtmlTestTheme,
          sourceId: 'reading-priority',
          threadId: '100',
          imageCacheOwnerId: '100',
        );
        Widget scene(_PriorityHost delegate) => MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                key: viewportKey,
                width: 200,
                height: 300,
                child: SingleChildScrollView(
                  child: ForumHtmlRenderer(
                    preparedDocument: document,
                    sourceId: 'reading-priority',
                    theme: forumHtmlTestTheme,
                    options: const ForumHtmlRenderOptions(
                      fontScale: 1,
                      lineHeightScale: 1.5,
                      paragraphSpacing: 12,
                      preserveAuthorFontSize: true,
                    ),
                    labels: const ForumHtmlCollapseLabels(
                      fallbackTitle: 'Details',
                      expandedSemanticsLabel: 'Expanded',
                      collapsedSemanticsLabel: 'Collapsed',
                    ),
                    imageHost: ThreadBodyReadingImageHost(
                      delegate: delegate,
                      tracker: tracker,
                    ),
                    imageViewportCoordinator: viewport,
                    callbacks: ForumHtmlRenderCallbacks(
                      onImageLayoutShift: shifts.add,
                    ),
                    buildAsync: false,
                  ),
                ),
              ),
            ),
          ),
        );
        Future<void> frames() async {
          for (var i = 0; i < 5; i++) {
            await tester.pump();
          }
        }

        await tester.pumpWidget(scene(oldDelegate));
        await frames();
        expect(oldDelegate.pending, hasLength(1));
        expect(
          oldDelegate.priorities,
          contains(ForumHtmlImageDimensionPriority.visible),
        );
        await tester.pumpWidget(scene(currentDelegate));
        await frames();
        oldDelegate.pending.values.single.complete(_dimensions);
        await frames();
        expect(oldDelegate.blockSizes, isEmpty);
        expect(currentDelegate.blockSizes, isEmpty);
        expect(shifts, isEmpty);
        if (sizeCallbackFirst) {
          currentDelegate.resolved.values.single(const Size(800, 400));
          await frames();
        }
        currentDelegate.pending.values.single.complete(
          sizeCallbackFirst
              ? (
                  size: const Size(100, 200),
                  layout: const ForumHtmlImageLayout(aspectRatio: 0.5),
                )
              : _dimensions,
        );
        await frames();
        expect(
          tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
          2,
        );
        expect(shifts, hasLength(1));
        expect(currentDelegate.blockSizes, [
          sizeCallbackFirst ? const Size(800, 400) : const Size(400, 200),
        ]);
        final box =
            viewportKey.currentContext!.findRenderObject()! as RenderBox;
        expect(
          tracker.readyIn(box),
          isFalse,
          reason: 'a metadata hint is not first-frame reading evidence',
        );
        currentDelegate.firstFrames.values.single();
        expect(tracker.readyIn(box), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('waits only for viewport images and rejects old first frames', (
    tester,
  ) async {
    final viewportKey = GlobalKey();
    final delegate = _Host();
    final tracker = ThreadBodyReadingImageTracker(() {});
    addTearDown(tracker.dispose);
    final host = ThreadBodyReadingImageHost(
      delegate: delegate,
      tracker: tracker,
    );
    var identity = 'a';
    Widget scene() => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          key: viewportKey,
          width: 400,
          height: 200,
          child: SingleChildScrollView(
            child: Column(
              children: [
                host.buildImage(
                  image: _Image(identity),
                  fit: BoxFit.contain,
                  placeholder: const SizedBox(),
                  width: 400,
                  height: 120,
                ),
                const SizedBox(height: 300),
                host.buildImage(
                  image: _Image('offscreen'),
                  fit: BoxFit.contain,
                  placeholder: const SizedBox(),
                  width: 400,
                  height: 120,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(scene());
    final viewport =
        viewportKey.currentContext!.findRenderObject()! as RenderBox;
    expect(tracker.readyIn(viewport), isFalse);
    final oldFirstFrame = delegate.firstFrames['a']!;
    oldFirstFrame();
    expect(
      tracker.readyIn(viewport),
      isTrue,
      reason: 'screen-external image does not block',
    );
    identity = 'replacement';
    await tester.pumpWidget(scene());
    expect(tracker.readyIn(viewport), isFalse);
    oldFirstFrame();
    expect(tracker.readyIn(viewport), isFalse);
    delegate.firstFrames['replacement']!();
    expect(tracker.readyIn(viewport), isTrue);
  });

  testWidgets('retains bounded predecode and the original display callbacks', (
    tester,
  ) async {
    final delegate = _Host();
    final tracker = ThreadBodyReadingImageTracker(() {});
    addTearDown(tracker.dispose);
    final host = ThreadBodyReadingImageHost(
      delegate: delegate,
      tracker: tracker,
    );
    final image = _Image('image');
    final scope = ForumHtmlImageWorkToken();
    late BuildContext context;
    var firstFrames = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return host.buildImage(
              image: image,
              fit: BoxFit.contain,
              placeholder: const SizedBox(),
              onFirstFrameRendered: () => firstFrames++,
            );
          },
        ),
      ),
    );
    delegate.firstFrames['image']!();
    expect(firstFrames, 1);
    expect(
      host.canRetainDisplayedImage(
        image: image,
        intrinsicSize: const Size(200, 100),
        displaySize: const Size(100, 50),
        devicePixelRatio: 2,
        maxDecodedBytes: 1000,
      ),
      isTrue,
    );
    expect(
      await host.predecodeImage(
        image: image,
        context: context,
        displaySize: const Size(100, 50),
        scope: scope,
        maxDecodedBytes: 1000,
      ),
      ForumHtmlImagePreparationOutcome.decoded,
    );
    expect(delegate.predecodeCalls, 1);
    expect(delegate.diskCalls, 0);
    await host.prefetchDisk(image, scope: scope);
    expect(delegate.diskCalls, 1);
  });
}

class _Image implements ForumHtmlDisplayImage {
  _Image(this.identity);
  @override
  final String identity;
  @override
  String get cacheKey => identity;
  @override
  String get sourceUrl => 'https://example.test/$identity.jpg';
  @override
  bool get isSticker => false;
  @override
  Size? get htmlSize => const Size(400, 120);
  @override
  ForumHtmlImageLayout get initialLayout =>
      const ForumHtmlImageLayout(displaySize: Size(400, 120));
}

class _Host implements ForumHtmlImageHost, ForumHtmlImagePredecodeHost {
  final firstFrames = <String, VoidCallback>{};
  int predecodeCalls = 0;
  int diskCalls = 0;
  int dimensionCalls = 0;
  final resolved = <String, ValueChanged<Size>>{};
  @override
  ForumHtmlDisplayImage? resolveImage({
    required Uri url,
    required int? imageIndex,
    required bool isSticker,
    Size? htmlSize,
  }) => null;
  @override
  Future<({Size size, ForumHtmlImageLayout layout})?> loadDimensions(
    ForumHtmlDisplayImage image,
  ) async {
    dimensionCalls++;
    return null;
  }

  @override
  void onBlockImageResolved(ForumHtmlDisplayImage image, Size size) {}
  @override
  Future<void> prefetchDisk(
    ForumHtmlDisplayImage image, {
    required ForumHtmlImageWorkScope scope,
  }) async {
    diskCalls++;
  }

  @override
  bool canRetainDisplayedImage({
    required ForumHtmlDisplayImage image,
    required Size intrinsicSize,
    required Size displaySize,
    required double devicePixelRatio,
    required int maxDecodedBytes,
  }) => true;
  @override
  Future<ForumHtmlImagePreparationOutcome> predecodeImage({
    required ForumHtmlDisplayImage image,
    required BuildContext context,
    required Size displaySize,
    required ForumHtmlImageWorkScope scope,
    required int maxDecodedBytes,
  }) async {
    predecodeCalls++;
    return ForumHtmlImagePreparationOutcome.decoded;
  }

  @override
  Widget buildImage({
    required ForumHtmlDisplayImage image,
    required BoxFit fit,
    required Widget placeholder,
    double? width,
    double? height,
    Widget? errorPlaceholder,
    VoidCallback? onRetry,
    ValueChanged<Size>? onImageResolved,
    VoidCallback? onImageFailed,
    VoidCallback? onFirstFrameRendered,
    bool showDelayedLoadingIndicator = false,
    bool waitForCacheWrite = false,
    int retryToken = 0,
  }) {
    firstFrames[image.identity as String] = onFirstFrameRendered!;
    if (onImageResolved != null) {
      resolved[image.identity as String] = onImageResolved;
    }
    return SizedBox(width: width ?? 100, height: height ?? 100);
  }
}

typedef _Dimensions = ({Size size, ForumHtmlImageLayout layout});
const _dimensions = (
  size: Size(400, 200),
  layout: ForumHtmlImageLayout(aspectRatio: 2),
);

class _UnsizedImage extends _Image {
  _UnsizedImage(super.identity);
  @override
  String get sourceUrl => identity;
  @override
  Size? get htmlSize => null;
  @override
  ForumHtmlImageLayout get initialLayout =>
      const ForumHtmlImageLayout(isFallback: true, aspectRatio: 0.7);
}

class _PriorityHost extends _Host
    implements ForumHtmlImageDimensionPriorityHost {
  final priorities = <ForumHtmlImageDimensionPriority>[];
  final pending = <String, Completer<_Dimensions?>>{};
  final blockSizes = <Size>[];

  @override
  ForumHtmlDisplayImage resolveImage({
    required Uri url,
    required int? imageIndex,
    required bool isSticker,
    Size? htmlSize,
  }) => _UnsizedImage(url.toString());

  @override
  Future<_Dimensions?> loadDimensions(ForumHtmlDisplayImage image) =>
      loadDimensionsWithPriority(
        image,
        priority: ForumHtmlImageDimensionPriority.background,
      );

  @override
  Future<_Dimensions?> loadDimensionsWithPriority(
    ForumHtmlDisplayImage image, {
    required ForumHtmlImageDimensionPriority priority,
  }) {
    priorities.add(priority);
    return pending
        .putIfAbsent(image.sourceUrl, Completer<_Dimensions?>.new)
        .future;
  }

  @override
  void onBlockImageResolved(ForumHtmlDisplayImage image, Size size) =>
      blockSizes.add(size);
}

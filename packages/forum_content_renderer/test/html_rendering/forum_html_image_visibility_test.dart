import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'render_test_support.dart';

void main() {
  testWidgets('display fragments keep original occurrences for repeated URLs', (
    tester,
  ) async {
    final metrics = ForumHtmlImageVisibilityMetrics();
    final scene = _Scene(metrics);
    addTearDown(scene.dispose);
    scene.host.ready.value = true;
    final document = prepareRenderTestDocument(
      '<div><img src="https://example.invalid/shared.png" width="200" height="200"></div>'
      '<div><img src="https://example.invalid/shared.png" width="200" height="200"></div>',
      sourceId: 'scene',
    );
    final images = RegExp(
      r'<img\b[^>]*>',
    ).allMatches(document.preparedHtml).toList();
    expect(images, hasLength(2));
    for (final image in images) {
      await tester.pumpWidget(
        scene.widget(
          document: document.copyWith(
            preparedHtml: '<div>${image.group(0)}</div>',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    }
    expect(metrics.snapshot.values['completed'], 2);
    expect(metrics.snapshot.values['revisitEntries'], 0);
  });

  testWidgets('decode admission alone cannot complete a visible wait', (
    tester,
  ) async {
    final metrics = ForumHtmlImageVisibilityMetrics();
    final viewport = ForumHtmlImageViewportCoordinator(
      visibilityObserver: metrics,
    );
    addTearDown(viewport.dispose);
    final handle = viewport.register(observationIdentity: 'prepared');
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            height: 180,
            child: SingleChildScrollView(
              child: Builder(
                builder: (context) {
                  handle.bind(context);
                  return const SizedBox(width: 200, height: 200);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    handle.reportFirstFrameRendered(canRetain: true);
    await tester.pumpAndSettle();
    expect(metrics.snapshot.values['pending'], 1);
    expect(metrics.snapshot.values['completed'], 0);
  });

  testWidgets('same image occurrence remains a revisit after body remount', (
    tester,
  ) async {
    final metrics = ForumHtmlImageVisibilityMetrics();
    final scene = _Scene(metrics);
    addTearDown(scene.dispose);
    scene.host.ready.value = true;
    await tester.pumpWidget(scene.widget());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(scene.widget());
    await tester.pumpAndSettle();
    expect(metrics.snapshot.values['revisitEntries'], 1);
    expect(metrics.snapshot.values['completed'], 2);
  });

  testWidgets(
    'paint completes a visible wait; retained reentry is a zero wait',
    (tester) async {
      var elapsed = Duration.zero;
      final metrics = ForumHtmlImageVisibilityMetrics(elapsed: () => elapsed);
      final scene = _Scene(metrics);
      addTearDown(scene.dispose);
      await tester.pumpWidget(scene.widget());
      await tester.pumpAndSettle();
      expect(metrics.snapshot.values['entries'], 1);
      expect(metrics.snapshot.values['pending'], 1);
      expect(metrics.snapshot.values['completed'], 0);

      elapsed += const Duration(milliseconds: 80);
      scene.host.ready.value = true;
      await tester.pumpAndSettle();
      expect(metrics.snapshot.values['completed'], 1);
      expect((metrics.snapshot.values['successfulWaits'] as Map)['p95Ms'], 80);
      scene.scroll.jumpTo(210);
      await tester.pumpAndSettle();
      scene.scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(metrics.snapshot.values['revisitEntries'], 1);
      expect(metrics.snapshot.values['revisitFirstFrameHits'], 1);
      expect(
        (metrics.snapshot.values['successfulRevisitWaits'] as Map)['p95Ms'],
        0,
      );
    },
  );

  testWidgets('fully clipped horizontal images are not visible visits', (
    tester,
  ) async {
    final metrics = ForumHtmlImageVisibilityMetrics();
    final scene = _Scene(metrics);
    final horizontal = ScrollController();
    addTearDown(scene.dispose);
    addTearDown(horizontal.dispose);
    scene.host.ready.value = true;
    await tester.pumpWidget(scene.widget(horizontal: horizontal));
    await tester.pumpAndSettle();
    expect(metrics.snapshot.values['entries'], 0);
    horizontal.jumpTo(400);
    await tester.pumpAndSettle();
    expect(metrics.snapshot.values['entries'], 1);
    expect(metrics.snapshot.values['completed'], 1);
    horizontal.jumpTo(0);
    await tester.pumpAndSettle();
    expect(metrics.snapshot.values['pending'], 0);
  });

  testWidgets('inactive, rebinding and unmount retire pending visits', (
    tester,
  ) async {
    final metrics = ForumHtmlImageVisibilityMetrics();
    final scene = _Scene(metrics);
    addTearDown(scene.dispose);
    await tester.pumpWidget(scene.widget());
    await tester.pumpAndSettle();
    scene.viewport.setActive(false);
    await tester.pumpAndSettle();
    expect(metrics.snapshot.values['abandoned'], 1);
    scene.viewport.setActive(true);
    await tester.pumpAndSettle();
    await tester.pumpWidget(scene.widget(source: 'replacement'));
    await tester.pumpAndSettle();
    expect(metrics.snapshot.values['abandoned'], 2);
    await tester.pumpWidget(const SizedBox());
    expect(metrics.snapshot.values['abandoned'], 3);
    expect(metrics.snapshot.values['pending'], 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a throwing optional observer cannot stop image display', (
    tester,
  ) async {
    final scene = _Scene(_ThrowingObserver());
    addTearDown(scene.dispose);
    scene.host.ready.value = true;
    await tester.pumpWidget(scene.widget());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('painted-image-0')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}

final class _Scene {
  _Scene(ForumHtmlImageVisibilityObserver observer)
    : viewport = ForumHtmlImageViewportCoordinator(
        visibilityObserver: observer,
        maxConcurrentOptionalWork: 0,
        predecodePolicy: const ForumHtmlImagePredecodePolicy(
          maxDecodedBytesPerImage: 1000000,
        ),
      );
  final ForumHtmlImageViewportCoordinator viewport;
  final host = _Images();
  final scroll = ScrollController();

  Widget widget({
    ScrollController? horizontal,
    String source = 'scene',
    ForumHtmlPreparedRenderDocument? document,
  }) {
    Widget body = ForumHtmlRenderer(
      preparedDocument:
          document ??
          prepareRenderTestDocument(
            [
              for (var i = 0; i < 3; i++)
                '<div><img src="https://example.invalid/$i.png" width="200" height="200"></div>',
            ].join(),
            sourceId: source,
          ),
      theme: forumHtmlTestTheme,
      options: renderTestOptions,
      labels: renderTestLabels,
      imageHost: host,
      imageViewportCoordinator: viewport,
      buildAsync: false,
      enableCaching: true,
    );
    if (horizontal != null) {
      body = SingleChildScrollView(
        controller: horizontal,
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 400),
            SizedBox(width: 200, child: body),
          ],
        ),
      );
    }
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            height: 180,
            child: SingleChildScrollView(controller: scroll, child: body),
          ),
        ),
      ),
    );
  }

  void dispose() {
    viewport.dispose();
    host.ready.dispose();
    scroll.dispose();
  }
}

final class _Images implements ForumHtmlImageHost, ForumHtmlImagePredecodeHost {
  final ready = ValueNotifier(false);
  @override
  ForumHtmlDisplayImage resolveImage({
    required Uri url,
    required int? imageIndex,
    required bool isSticker,
    Size? htmlSize,
  }) => _Image(url.toString());
  @override
  Future<({Size size, ForumHtmlImageLayout layout})?> loadDimensions(
    ForumHtmlDisplayImage image,
  ) async => null;
  @override
  void onBlockImageResolved(ForumHtmlDisplayImage image, Size size) {}
  @override
  Future<void> prefetchDisk(
    ForumHtmlDisplayImage image, {
    required ForumHtmlImageWorkScope scope,
  }) async {}
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
  }) async => ForumHtmlImagePreparationOutcome.diskOnly;
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
  }) => ValueListenableBuilder<bool>(
    valueListenable: ready,
    builder: (_, painted, _) {
      if (!painted) return placeholder;
      onImageResolved?.call(const Size(200, 200));
      onFirstFrameRendered?.call();
      return ColoredBox(
        key: Key(
          'painted-image-${Uri.parse(image.sourceUrl).pathSegments.last.split('.').first}',
        ),
        color: Colors.blue,
      );
    },
  );
}

final class _Image implements ForumHtmlDisplayImage {
  _Image(this.sourceUrl);
  @override
  final String sourceUrl;
  @override
  String get cacheKey => sourceUrl;
  @override
  Object get identity => sourceUrl;
  @override
  bool get isSticker => false;
  @override
  Size get htmlSize => const Size(200, 200);
  @override
  ForumHtmlImageLayout get initialLayout =>
      const ForumHtmlImageLayout(aspectRatio: 1);
}

final class _ThrowingObserver implements ForumHtmlImageVisibilityObserver {
  @override
  void observe(
    Object identity, {
    required bool visible,
    required bool painted,
    required bool failed,
  }) => throw StateError('observer unavailable');
  @override
  void retire(Object identity) => throw StateError('observer unavailable');
}

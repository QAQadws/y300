import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../../../../test_support/localized_test_app.dart';
import 'forum_html_test_theme.dart';

void main() {
  testWidgets('dimension lookup failure leaves the displayed fallback intact', (
    tester,
  ) async {
    final dimensions = _Dimensions(deferred: true);
    final host = _ImageHost(dimensions);
    await tester.pumpWidget(_host(host));
    await tester.pump();

    expect(
      tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
      0.7,
    );
    dimensions.pending.single.completeError(StateError('metadata unavailable'));
    await tester.pump();

    expect(find.byType(_DisplayedImage), findsOneWidget);
    expect(
      tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
      0.7,
    );
    expect(host.blockSizes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dimension lookup completing after unmount cannot report a size',
    (tester) async {
      final dimensions = _Dimensions(deferred: true);
      final host = _ImageHost(dimensions);
      await tester.pumpWidget(_host(host));
      await tester.pump();
      expect(dimensions.pending, hasLength(1));
      await tester.pumpWidget(_host(host, shown: false));
      dimensions.pending.single.complete((
        size: const Size(100, 200),
        layout: const ForumHtmlImageLayout(aspectRatio: 0.5),
      ));
      await tester.pump();

      expect(find.byType(_DisplayedImage), findsNothing);
      expect(host.blockSizes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('A to B to A rejects both old dimension results', (tester) async {
    final dimensions = _Dimensions(deferred: true);
    final host = _ImageHost(dimensions);
    for (final prefix in ['a', 'b', 'a']) {
      await tester.pumpWidget(_host(host, imagePrefix: prefix));
      await tester.pump();
    }
    expect(dimensions.pending, hasLength(3));

    for (final old in dimensions.pending.take(2)) {
      old.complete((
        size: const Size(100, 200),
        layout: const ForumHtmlImageLayout(aspectRatio: 0.5),
      ));
      await tester.pump();
      expect(host.blockSizes, isEmpty);
      expect(
        tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
        0.7,
      );
    }
    dimensions.pending.last.complete((
      size: const Size(300, 150),
      layout: const ForumHtmlImageLayout(aspectRatio: 2),
    ));
    await _frames(tester);

    expect(host.blockSizes, [const Size(300, 150)]);
    expect(tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'retired Host callbacks cannot report sizes or settle new images',
    (tester) async {
      final host = _ImageHost(_Dimensions());
      final viewport = ForumHtmlImageViewportCoordinator(
        maxVisibleFirstFrames: 1,
      );
      addTearDown(viewport.dispose);
      Widget build({bool shown = true}) => _host(
        host,
        shown: shown,
        viewport: viewport,
        imageCount: 3,
        height: 450,
      );
      await tester.pumpWidget(build());
      await _frames(tester);
      final old = tester.widget<_DisplayedImage>(find.byType(_DisplayedImage));
      viewport.setActive(false);
      await _frames(tester);
      old.reportAll();
      await _frames(tester);
      expect(host.blockSizes, isEmpty);
      expect(find.byType(_DisplayedImage), findsNothing);

      viewport.setActive(true);
      await _frames(tester);
      expect(find.byType(_DisplayedImage), findsOneWidget);
      old.reportAll();
      await _frames(tester);
      expect(host.blockSizes, isEmpty);
      expect(find.byType(_DisplayedImage), findsOneWidget);

      final current = tester.widget<_DisplayedImage>(
        find.byType(_DisplayedImage),
      );
      await tester.pumpWidget(build(shown: false));
      current.reportAll();
      await _frames(tester);
      expect(host.blockSizes, isEmpty);
      expect(viewport.registeredImageCount, 0);
      expect(find.byType(_DisplayedImage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('replacing the Host preserves the ready body and local expansion', (
    tester,
  ) async {
    const html =
        '<p>Body before the fold</p>'
        '<div id="fold" class="showcollapse_box">'
        '<div class="showcollapse_title">Details</div>'
        '<div class="showcollapse_content"><p>Expanded body remains visible</p>'
        '<img src="https://example.invalid/body.jpg" width="200" height="120">'
        '<p>A second paragraph inside the fold</p></div></div>';
    final presentation = ForumHtmlBodyPresentation();
    addTearDown(presentation.dispose);
    final firstHost = _ImageHost(_Dimensions());
    final secondHost = _ImageHost(_Dimensions());
    var bodyBuilt = 0;
    Widget build(_ImageHost host) => _host(
      host,
      html: html,
      bodyPresentation: presentation,
      onBodyBuilt: () => bodyBuilt++,
      enableCaching: true,
      height: 550,
    );
    Finder htmlBody(String sourceId) => find.byWidgetPredicate(
      (widget) =>
          widget is HtmlWidget &&
          widget.key == Key('forum-html-renderer-$sourceId'),
    );
    final body = htmlBody('host-lifecycle');
    final innerBody = htmlBody('host-lifecycle-fold-content');
    final expanded = find.textContaining(
      'Expanded body remains visible',
      findRichText: true,
    );
    double bodyHeight() => tester.getSize(body).height;
    await tester.pumpWidget(build(firstHost));
    await _frames(tester);
    expect(bodyBuilt, greaterThan(0));
    expect(expanded, findsNothing);
    final collapsedHeight = bodyHeight();
    await tester.tap(
      find.byKey(const Key('forum-html-collapse-toggle-host-lifecycle-fold')),
    );
    await tester.pumpAndSettle();
    expect(expanded, findsOneWidget);
    final element = tester.element(body);
    final innerElement = tester.element(innerBody);
    final expandedHeight = bodyHeight();
    final innerHeight = tester.getSize(innerBody).height;
    expect(expandedHeight, greaterThan(collapsedHeight));
    final oldImage = tester.widget<_DisplayedImage>(
      find.byType(_DisplayedImage),
    );

    await tester.pumpWidget(build(secondHost));
    expect(find.byKey(ValueKey(secondHost)), findsOneWidget);
    expect(find.byKey(ValueKey(firstHost)), findsNothing);
    expect(tester.element(body), same(element));
    expect(tester.element(innerBody), same(innerElement));
    expect(expanded, findsOneWidget);
    expect(bodyHeight(), closeTo(expandedHeight, 0.5));
    expect(tester.getSize(innerBody).height, closeTo(innerHeight, 0.5));
    oldImage.reportAll();
    expect(firstHost.blockSizes, isEmpty);
    expect(secondHost.blockSizes, isEmpty);
    tester.widget<_DisplayedImage>(find.byType(_DisplayedImage)).onResolved!(
      const Size(200, 120),
    );
    expect(secondHost.blockSizes, [const Size(200, 120)]);
    for (var frame = 0; frame < 3; frame++) {
      await tester.pump();
      expect(tester.element(body), same(element));
      expect(tester.element(innerBody), same(innerElement));
      expect(expanded, findsOneWidget);
      expect(bodyHeight(), closeTo(expandedHeight, 0.5));
      expect(tester.getSize(innerBody).height, closeTo(innerHeight, 0.5));
    }
    expect(firstHost.blockSizes, isEmpty);
    expect(bodyBuilt, greaterThan(0));
    expect(presentation.collapseExpansion, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final failed in [false, true]) {
    testWidgets(
      '${failed ? 'failure' : 'first frame'} releases another visible image',
      (tester) async {
        final host = _ImageHost(_Dimensions());
        final viewport = ForumHtmlImageViewportCoordinator(
          maxVisibleFirstFrames: 1,
        );
        addTearDown(viewport.dispose);
        await tester.pumpWidget(
          _host(host, viewport: viewport, imageCount: 3, height: 450),
        );
        await _frames(tester);
        expect(find.byType(_DisplayedImage), findsOneWidget);
        final first = tester.widget<_DisplayedImage>(
          find.byType(_DisplayedImage),
        );

        if (failed) {
          expect(first.onFailed, isNotNull);
          first.onFailed!();
        } else {
          expect(first.onFirstFrame, isNotNull);
          first.onFirstFrame!();
        }
        await _frames(tester);

        final displayed = tester.widgetList<_DisplayedImage>(
          find.byType(_DisplayedImage),
        );
        expect(displayed, hasLength(2));
        expect(displayed.map((image) => image.url).toSet(), hasLength(2));
        expect(displayed.map((image) => image.url), contains(first.url));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final unmount in [false, true]) {
    testWidgets(
      'scoped disk prefetch is cancelled when ${unmount ? 'unmounted' : 'inactive'}',
      (tester) async {
        final precache = _DiskPrecache();
        final host = _ImageHost(_Dimensions(), precache: precache);
        final viewport = ForumHtmlImageViewportCoordinator(
          maxVisibleFirstFrames: 1,
          prefetchExtentFactor: 2,
        );
        addTearDown(viewport.dispose);
        Widget build({bool shown = true}) => _host(
          host,
          shown: shown,
          viewport: viewport,
          imageCount: 3,
          height: 150,
        );
        await tester.pumpWidget(build());
        await _frames(tester);
        expect(precache.work, isEmpty);
        tester
            .widget<_DisplayedImage>(find.byType(_DisplayedImage))
            .onFirstFrame!();
        await _frames(tester);
        expect(precache.work, hasLength(1));
        final old = precache.work.single;
        expect(old.scope.isActive, isTrue);

        if (unmount) {
          await tester.pumpWidget(build(shown: false));
        } else {
          viewport.setActive(false);
          await _frames(tester);
        }
        expect(old.scope.isActive, isFalse);
        expect(find.byType(_DisplayedImage), findsNothing);
        old.complete();
        await _frames(tester);
        expect(precache.work, hasLength(1));
        expect(find.byType(_DisplayedImage), findsNothing);

        if (!unmount) {
          viewport.setActive(true);
          await _frames(tester);
          tester
              .widget<_DisplayedImage>(find.byType(_DisplayedImage))
              .onFirstFrame!();
          await _frames(tester);
          expect(precache.work, hasLength(2));
          final current = precache.work.last;
          expect(current.scope, isNot(same(old.scope)));
          expect(current.scope.isActive, isTrue);
          current.complete();
        } else {
          expect(viewport.registeredImageCount, 0);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var frame = 0; frame < 3; frame++) {
    await tester.pump();
  }
}

Widget _host(
  _ImageHost host, {
  bool shown = true,
  ForumHtmlImageViewportCoordinator? viewport,
  int imageCount = 1,
  String imagePrefix = 'image',
  double height = 300,
  String? html,
  ForumHtmlBodyPresentation? bodyPresentation,
  VoidCallback? onBodyBuilt,
  bool enableCaching = false,
}) => LocalizedTestApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 200,
        height: height,
        child: SingleChildScrollView(
          child: shown
              ? ForumHtmlWidgetPostRenderer(
                  theme: forumHtmlTestTheme,
                  sourceId: 'host-lifecycle',
                  threadId: '100',
                  buildAsync: false,
                  enableCaching: enableCaching,
                  html:
                      html ??
                      [
                        for (var image = 0; image < imageCount; image++)
                          '<div><img src="https://example.invalid/$imagePrefix-$image.jpg" '
                              '${viewport == null ? '' : 'width="200" height="200"'}></div>',
                      ].join(),
                  imageHost: host,
                  imageViewportCoordinator: viewport,
                  bodyPresentation: bodyPresentation,
                  onBodyBuilt: onBodyBuilt,
                )
              : const SizedBox.shrink(),
        ),
      ),
    ),
  ),
);

typedef _DimensionResult = ({Size size, ForumHtmlImageLayout layout});

final class _Dimensions {
  _Dimensions({this.deferred = false});

  final bool deferred;
  final pending = <Completer<_DimensionResult?>>[];

  Future<_DimensionResult?> load() {
    if (!deferred) return Future.value(null);
    final result = Completer<_DimensionResult?>();
    pending.add(result);
    return result.future;
  }
}

final class _ImageHost implements ForumHtmlImageHost {
  _ImageHost(this.dimensions, {this.precache});

  final _Dimensions dimensions;
  final _DiskPrecache? precache;
  final blockSizes = <Size>[];

  @override
  ForumHtmlDisplayImage resolveImage({
    required Uri url,
    required int? imageIndex,
    required bool isSticker,
    Size? htmlSize,
  }) => _ImageBinding(
    sourceUrl: url.toString(),
    isSticker: isSticker,
    htmlSize: htmlSize,
  );

  @override
  Future<_DimensionResult?> loadDimensions(ForumHtmlDisplayImage image) =>
      dimensions.load();

  @override
  void onBlockImageResolved(ForumHtmlDisplayImage image, Size size) =>
      blockSizes.add(size);

  @override
  Future<void> prefetchDisk(
    ForumHtmlDisplayImage image, {
    required ForumHtmlImageWorkScope scope,
  }) => precache?.start(scope) ?? Future.value();

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
  }) => _DisplayedImage(
    key: ValueKey(this),
    url: image.sourceUrl,
    onResolved: onImageResolved,
    onFirstFrame: onFirstFrameRendered,
    onFailed: onImageFailed,
  );
}

final class _ImageBinding implements ForumHtmlDisplayImage {
  const _ImageBinding({
    required this.sourceUrl,
    required this.isSticker,
    required this.htmlSize,
  });

  @override
  final String sourceUrl;
  @override
  final bool isSticker;
  @override
  final Size? htmlSize;
  @override
  String get cacheKey => 'test:$sourceUrl';
  @override
  Object get identity => (sourceUrl, isSticker, htmlSize);
  @override
  ForumHtmlImageLayout get initialLayout => htmlSize == null
      ? const ForumHtmlImageLayout(isFallback: true, aspectRatio: 0.7)
      : ForumHtmlImageLayout(aspectRatio: htmlSize!.aspectRatio);
}

final class _DisplayedImage extends StatelessWidget {
  const _DisplayedImage({
    super.key,
    required this.url,
    required this.onResolved,
    required this.onFirstFrame,
    required this.onFailed,
  });

  final String url;
  final ValueChanged<Size>? onResolved;
  final VoidCallback? onFirstFrame;
  final VoidCallback? onFailed;

  void reportAll() {
    onResolved?.call(const Size(800, 400));
    onFirstFrame?.call();
    onFailed?.call();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

final class _DiskWork {
  _DiskWork(this.scope);

  final ForumHtmlImageWorkScope scope;
  final result = Completer<void>();

  void complete() => result.complete();
}

final class _DiskPrecache {
  final work = <_DiskWork>[];

  Future<void> start(ForumHtmlImageWorkScope scope) {
    final request = _DiskWork(scope);
    work.add(request);
    return request.result.future;
  }
}

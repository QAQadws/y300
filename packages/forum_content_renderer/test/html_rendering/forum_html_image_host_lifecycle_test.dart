import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'render_test_support.dart';

void main() {
  for (final caption in ['', 'Image caption<br><br>']) {
    testWidgets('unsized table image displays with caption "$caption"', (
      tester,
    ) async {
      final dimensions = _Dimensions(deferred: true);
      final host = _ImageHost(dimensions);
      final viewport = ForumHtmlImageViewportCoordinator();
      addTearDown(viewport.dispose);
      await tester.pumpWidget(
        _host(
          host,
          viewport: viewport,
          width: 376,
          height: 600,
          html:
              '<div align="center"><table><tr><td><div align="center">'
              '$caption<a href="data/attachment/forum/example.png" class="orange" />'
              '<img id="aimg_1058403" src="data/attachment/forum/example.png" '
              'alt="image" loading="lazy" /></a>'
              '</div></td></tr></table></div>',
        ),
      );
      await _frames(tester);
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      final image = find.byType(_DisplayedImage);
      expect(image, findsOneWidget);
      final bounds = tester.getRect(image);
      expect(bounds.width, greaterThan(0));
      expect(bounds.height, greaterThan(0));
      expect(bounds.width, lessThanOrEqualTo(376));
      final element = tester.element(image);
      tester.widget<_DisplayedImage>(image).onFirstFrame!();
      dimensions.pending.single.complete((
        size: const Size(1100, 720),
        layout: const ForumHtmlImageLayout(aspectRatio: 1100 / 720),
      ));
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump();
        expect(image, findsOneWidget);
        expect(tester.element(image), same(element));
      }
      expect(tester.getSize(image).aspectRatio, closeTo(1100 / 720, 0.001));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('late dimension hints preserve the mounted visible image', (
    tester,
  ) async {
    final dimensions = _Dimensions(deferred: true);
    final host = _ImageHost(dimensions);
    final viewport = ForumHtmlImageViewportCoordinator();
    addTearDown(viewport.dispose);
    await tester.pumpWidget(
      _host(
        host,
        viewport: viewport,
        html: '<img src="https://example.invalid/unknown.jpg">',
      ),
    );
    await _frames(tester);
    final image = find.byType(_DisplayedImage);
    final element = tester.element(image);
    tester.widget<_DisplayedImage>(image).onFirstFrame!();
    dimensions.pending.single.complete((
      size: const Size(400, 200),
      layout: const ForumHtmlImageLayout(aspectRatio: 2),
    ));
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump();
      expect(image, findsOneWidget);
      expect(tester.element(image), same(element));
      expect(
        tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
        2,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('visible dimension promotion joins a pending initial hint', (
    tester,
  ) async {
    final host = _PriorityImageHost();
    final viewport = ForumHtmlImageViewportCoordinator();
    addTearDown(viewport.dispose);
    final shifts = <ForumHtmlImageLayoutShift>[];
    await tester.pumpWidget(
      _host(
        host,
        viewport: viewport,
        htmlDimensions: false,
        onImageLayoutShift: shifts.add,
      ),
    );
    await _frames(tester);
    expect(host.dimensionReads, hasLength(1));
    expect(host.dimensionCalls.map((call) => call.priority), [
      ForumHtmlImageDimensionPriority.background,
      ForumHtmlImageDimensionPriority.visible,
    ]);
    final image = find.byType(_DisplayedImage);
    final element = tester.element(image);
    final body = tester.element(find.byType(HtmlWidget));
    host.dimensionReads.single.result.complete(_wideDimensions);
    await _frames(tester);
    expect(tester.getSize(image).aspectRatio, closeTo(2, 0.001));
    expect(tester.element(image), same(element));
    expect(tester.element(find.byType(HtmlWidget)), same(body));
    expect(host.blockSizes, [const Size(400, 200)]);
    expect(shifts, hasLength(1));
    expect(shifts.single.oldAspectRatio, 0.7);
    expect(shifts.single.newAspectRatio, 2);
    expect(host.dimensionReads, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final recovered in [true, false]) {
    testWidgets(
      'a shared missing hint retries once while still visible: $recovered',
      (tester) async {
        final host = _PriorityImageHost();
        final viewport = ForumHtmlImageViewportCoordinator();
        addTearDown(viewport.dispose);
        await tester.pumpWidget(
          _host(host, viewport: viewport, htmlDimensions: false),
        );
        await _frames(tester);
        expect(host.dimensionReads, hasLength(1));
        host.dimensionReads.single.result.complete(null);
        await _frames(tester);
        expect(host.dimensionReads, hasLength(2));
        expect(
          host.dimensionCalls.last.priority,
          ForumHtmlImageDimensionPriority.visible,
        );
        host.dimensionReads.last.result.complete(
          recovered ? _wideDimensions : null,
        );
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump();
        }
        expect(host.dimensionReads, hasLength(2));
        expect(host.dimensionCalls, hasLength(3));
        expect(
          tester.getSize(find.byType(_DisplayedImage)).aspectRatio,
          closeTo(recovered ? 2 : 0.7, 0.001),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'nearby hints are promoted while distant initial geometry still loads',
    (tester) async {
      final host = _PriorityImageHost();
      final viewport = ForumHtmlImageViewportCoordinator(
        prefetchExtentFactor: 1,
      );
      addTearDown(viewport.dispose);
      await tester.pumpWidget(
        _host(
          host,
          viewport: viewport,
          imageCount: 3,
          height: 150,
          htmlDimensions: false,
        ),
      );
      await _frames(tester);
      expect(host.dimensionReads, hasLength(3));
      expect(
        host.dimensionCalls.where(
          (call) => call.priority == ForumHtmlImageDimensionPriority.background,
        ),
        hasLength(3),
      );
      expect(
        host.dimensionCalls
            .where(
              (call) =>
                  call.priority == ForumHtmlImageDimensionPriority.visible,
            )
            .map((call) => call.url),
        ['https://example.invalid/image-0.jpg'],
      );
      expect(
        host.dimensionCalls
            .where(
              (call) => call.priority == ForumHtmlImageDimensionPriority.nearby,
            )
            .map((call) => call.url),
        ['https://example.invalid/image-1.jpg'],
      );
      for (final read in host.dimensionReads.toList()) {
        read.result.complete(_wideDimensions);
      }
      await _frames(tester);
      expect(host.blockSizes, hasLength(3));
      expect(host.dimensionReads, hasLength(3));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late metadata cannot replace an earlier image size callback', (
    tester,
  ) async {
    final host = _PriorityImageHost();
    final viewport = ForumHtmlImageViewportCoordinator();
    addTearDown(viewport.dispose);
    final shifts = <ForumHtmlImageLayoutShift>[];
    await tester.pumpWidget(
      _host(
        host,
        viewport: viewport,
        htmlDimensions: false,
        onImageLayoutShift: shifts.add,
      ),
    );
    await _frames(tester);
    tester.widget<_DisplayedImage>(find.byType(_DisplayedImage)).onResolved!(
      const Size(800, 400),
    );
    await _frames(tester);
    host.dimensionReads.single.result.complete((
      size: const Size(100, 200),
      layout: const ForumHtmlImageLayout(aspectRatio: 0.5),
    ));
    await _frames(tester);
    expect(
      tester.getSize(find.byType(_DisplayedImage)).aspectRatio,
      closeTo(2, 0.001),
    );
    expect(host.blockSizes, [const Size(800, 400)]);
    expect(shifts, hasLength(1));
    expect(host.dimensionReads, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final change in ['Host', 'source', 'unmount']) {
    testWidgets('promoted dimension completion is retired after $change', (
      tester,
    ) async {
      final host = _PriorityImageHost();
      final nextHost = _PriorityImageHost();
      final viewport = ForumHtmlImageViewportCoordinator();
      addTearDown(viewport.dispose);
      final shifts = <ForumHtmlImageLayoutShift>[];
      Widget build(
        _ImageHost current, {
        bool shown = true,
        String prefix = 'image',
      }) => _host(
        current,
        viewport: viewport,
        htmlDimensions: false,
        shown: shown,
        imagePrefix: prefix,
        onImageLayoutShift: shifts.add,
      );
      await tester.pumpWidget(build(host));
      await _frames(tester);
      final old = host.dimensionReads.single;
      switch (change) {
        case 'Host':
          await tester.pumpWidget(build(nextHost));
        case 'source':
          await tester.pumpWidget(build(host, prefix: 'next'));
        case 'unmount':
          await tester.pumpWidget(build(host, shown: false));
      }
      await _frames(tester);
      old.result.complete(_wideDimensions);
      await _frames(tester);
      expect(host.blockSizes, isEmpty);
      expect(nextHost.blockSizes, isEmpty);
      expect(shifts, isEmpty);
      if (change != 'unmount') {
        expect(
          tester.getSize(find.byType(_DisplayedImage)).aspectRatio,
          closeTo(0.7, 0.001),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('HTML dimensions keep the existing no-query path', (
    tester,
  ) async {
    final host = _PriorityImageHost();
    final viewport = ForumHtmlImageViewportCoordinator();
    addTearDown(viewport.dispose);
    await tester.pumpWidget(_host(host, viewport: viewport));
    await _frames(tester);
    expect(host.dimensionCalls, isEmpty);
    expect(host.dimensionReads, isEmpty);
  });

  for (final change in ['inactive', 'unmounted', 'Host', 'width', 'DPR']) {
    testWidgets('predecode rejects late results after $change changes', (
      tester,
    ) async {
      final host = _PredecodeHost();
      final viewport = ForumHtmlImageViewportCoordinator(
        predecodePolicy: const ForumHtmlImagePredecodePolicy(
          maxDecodedBytesPerImage: 1000000,
        ),
      );
      addTearDown(viewport.dispose);
      await tester.pumpWidget(
        _host(host, viewport: viewport, imageCount: 3, height: 150),
      );
      await _frames(tester);
      expect(host.work, hasLength(1));
      final old = host.work.single;
      expect(old.scope.isActive, isTrue);
      expect(old.size.width, 200);
      expect(old.size.height, 200);
      switch (change) {
        case 'inactive':
          viewport.setActive(false);
        case 'unmounted':
          await tester.pumpWidget(
            _host(host, shown: false, viewport: viewport),
          );
        case 'Host':
          await tester.pumpWidget(
            _host(
              _PredecodeHost(),
              viewport: viewport,
              imageCount: 3,
              height: 150,
            ),
          );
        case 'width':
          await tester.pumpWidget(
            _host(
              host,
              viewport: viewport,
              imageCount: 3,
              height: 150,
              width: 180,
            ),
          );
        case 'DPR':
          addTearDown(tester.view.resetDevicePixelRatio);
          tester.view.devicePixelRatio = tester.view.devicePixelRatio * 2;
      }
      await _frames(tester);
      expect(old.scope.isActive, isFalse);
      old.result.complete(ForumHtmlImagePreparationOutcome.decoded);
      await _frames(tester);
      expect(tester.takeException(), isNull);
      if (change == 'inactive' || change == 'unmounted') {
        expect(host.work, hasLength(1));
      } else if (change == 'width' || change == 'DPR') {
        expect(host.work, hasLength(2));
        expect(host.work.last.size.width, change == 'width' ? 180 : 200);
        host.work.last.result.complete(
          ForumHtmlImagePreparationOutcome.decoded,
        );
      }
    });
  }

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

  testWidgets('two disk leases survive Host retirement until I/O completes', (
    tester,
  ) async {
    final oldPrecache = _DiskPrecache();
    final oldHost = _ImageHost(_Dimensions(), precache: oldPrecache);
    final currentPrecache = _DiskPrecache();
    final currentHost = _ImageHost(_Dimensions(), precache: currentPrecache);
    final viewport = ForumHtmlImageViewportCoordinator(
      maxVisibleFirstFrames: 2,
      maxPrefetchCandidates: 2,
      maxConcurrentOptionalWork: 2,
      prefetchExtentFactor: 2,
    );
    addTearDown(viewport.dispose);
    Widget build(_ImageHost host) =>
        _host(host, viewport: viewport, imageCount: 4, height: 150);
    await tester.pumpWidget(build(oldHost));
    await _frames(tester);
    tester
        .widget<_DisplayedImage>(find.byType(_DisplayedImage))
        .onFirstFrame!();
    await _frames(tester);
    expect(oldPrecache.work, hasLength(2));
    expect(oldPrecache.work.map((w) => w.url).toSet(), hasLength(2));
    final completed = oldPrecache.work.first;
    final pending = oldPrecache.work.last;
    completed.complete();
    await _frames(tester);
    expect(pending.scope.isActive, isTrue);

    await tester.pumpWidget(build(currentHost));
    await _frames(tester);
    expect(pending.scope.isActive, isFalse);
    tester
        .widget<_DisplayedImage>(find.byType(_DisplayedImage))
        .onFirstFrame!();
    await _frames(tester);
    // The available second slot belongs to a distinct handle. It cannot restart
    // the retired binding of the image whose original I/O is still pending.
    expect(currentPrecache.work, hasLength(1));
    expect(currentPrecache.work.single.url, completed.url);
    expect(currentPrecache.work.single.url, isNot(pending.url));
    expect(currentPrecache.work.single.scope.isActive, isTrue);
    pending.complete();
    await _frames(tester);
    expect(currentPrecache.work, hasLength(2));
    expect(currentPrecache.work.last.url, pending.url);
    expect(currentPrecache.work.every((w) => w.scope.isActive), isTrue);
    for (final work in currentPrecache.work) {
      work.complete();
    }
    await _frames(tester);
    expect(currentPrecache.work, hasLength(2));
    expect(viewport.registeredImageCount, 4);
    expect(tester.takeException(), isNull);
  });

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
  double width = 200,
  String? html,
  ForumHtmlBodyPresentation? bodyPresentation,
  VoidCallback? onBodyBuilt,
  bool enableCaching = false,
  bool htmlDimensions = true,
  ValueChanged<ForumHtmlImageLayoutShift>? onImageLayoutShift,
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        height: height,
        child: SingleChildScrollView(
          child: shown
              ? ForumHtmlRenderer(
                  theme: forumHtmlTestTheme,
                  options: renderTestOptions,
                  labels: renderTestLabels,
                  sourceId: 'host-lifecycle',
                  buildAsync: false,
                  enableCaching: enableCaching,
                  preparedDocument: prepareRenderTestDocument(
                    html ??
                        [
                          for (var image = 0; image < imageCount; image++)
                            '<div><img src="https://example.invalid/$imagePrefix-$image.jpg" '
                                '${viewport == null || !htmlDimensions ? '' : 'width="200" height="200"'}></div>',
                        ].join(),
                    sourceId: 'host-lifecycle',
                  ),
                  imageHost: host,
                  imageViewportCoordinator: viewport,
                  bodyPresentation: bodyPresentation,
                  onBodyBuilt: onBodyBuilt,
                  callbacks: ForumHtmlRenderCallbacks(
                    onImageLayoutShift: onImageLayoutShift,
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    ),
  ),
);

typedef _DimensionResult = ({Size size, ForumHtmlImageLayout layout});

const _wideDimensions = (
  size: Size(400, 200),
  layout: ForumHtmlImageLayout(aspectRatio: 2),
);

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
  }) => precache?.start(scope, image.sourceUrl) ?? Future.value();

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

final class _PriorityImageHost extends _ImageHost
    implements ForumHtmlImageDimensionPriorityHost {
  _PriorityImageHost() : super(_Dimensions());
  final dimensionCalls =
      <({String url, ForumHtmlImageDimensionPriority priority})>[];
  final dimensionReads =
      <({String url, Completer<_DimensionResult?> result})>[];
  final _pendingDimensions = <String, Completer<_DimensionResult?>>{};

  @override
  Future<_DimensionResult?> loadDimensions(ForumHtmlDisplayImage image) =>
      loadDimensionsWithPriority(
        image,
        priority: ForumHtmlImageDimensionPriority.background,
      );

  @override
  Future<_DimensionResult?> loadDimensionsWithPriority(
    ForumHtmlDisplayImage image, {
    required ForumHtmlImageDimensionPriority priority,
  }) {
    final url = image.sourceUrl;
    dimensionCalls.add((url: url, priority: priority));
    final existing = _pendingDimensions[url];
    if (existing != null && !existing.isCompleted) return existing.future;
    final result = Completer<_DimensionResult?>();
    _pendingDimensions[url] = result;
    dimensionReads.add((url: url, result: result));
    return result.future;
  }
}

final class _PredecodeHost extends _ImageHost
    implements ForumHtmlImagePredecodeHost {
  _PredecodeHost() : super(_Dimensions());
  @override
  bool canRetainDisplayedImage({
    required ForumHtmlDisplayImage image,
    required Size intrinsicSize,
    required Size displaySize,
    required double devicePixelRatio,
    required int maxDecodedBytes,
  }) => true;

  final work =
      <
        ({
          ForumHtmlImageWorkScope scope,
          Size size,
          Completer<ForumHtmlImagePreparationOutcome> result,
        })
      >[];
  @override
  Future<ForumHtmlImagePreparationOutcome> predecodeImage({
    required ForumHtmlDisplayImage image,
    required BuildContext context,
    required Size displaySize,
    required ForumHtmlImageWorkScope scope,
    required int maxDecodedBytes,
  }) {
    final result = Completer<ForumHtmlImagePreparationOutcome>();
    work.add((scope: scope, size: displaySize, result: result));
    return result.future;
  }
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
  _DiskWork(this.scope, this.url);

  final ForumHtmlImageWorkScope scope;
  final String url;
  final result = Completer<void>();

  void complete() => result.complete();
}

final class _DiskPrecache {
  final work = <_DiskWork>[];

  Future<void> start(ForumHtmlImageWorkScope scope, String url) {
    final request = _DiskWork(scope, url);
    work.add(request);
    return request.result.future;
  }
}

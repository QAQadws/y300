import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'test_support/inline_image_fixture.dart';

final class _Pixels extends StatelessWidget {
  const _Pixels({required this.image, this.resolved, this.frame, this.failed});
  final ForumHtmlDisplayImage image;
  final ValueChanged<Size>? resolved;
  final VoidCallback? frame, failed;
  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.orange);
}

final class _Host implements ForumHtmlImageHost {
  _Host(this.fixture);
  final InlineImageFixture fixture;
  ForumHtmlDisplayImage? displayOverride;
  int builds = 0;
  @override
  ForumHtmlDisplayImage resolveImage({
    required Uri url,
    required int? imageIndex,
    required bool isSticker,
    Size? htmlSize,
  }) => displayOverride ?? fixture.images[imageIndex ?? 0]!.image;
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
    builds++;
    expect(fit, BoxFit.contain);
    return _Pixels(
      image: image,
      resolved: onImageResolved,
      frame: onFirstFrameRendered,
      failed: onImageFailed,
    );
  }
}

Widget _host(Widget child) => MaterialApp(
  home: Align(alignment: Alignment.topLeft, child: child),
);

void main() {
  testWidgets('mounted inline anchors reveal the exact repeated image slot', (
    tester,
  ) async {
    final fixture = InlineImageFixture(
      sticker: false,
      size: const Size(70, 20),
    );
    final view = fixture.view();
    final controller = ForumHtmlImageAnchorController();
    final scroll = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scroll.dispose);
    final entries = fixture.images.values.map((image) => image.entry!).toList();
    controller.bindSequence(
      ForumHtmlReadableImageSequence(
        sourceId: fixture.document.identity.sourceId,
        entries: entries,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          controller: scroll,
          child: Column(
            children: [
              const SizedBox(height: 100),
              ForumBodyInlineImageSurface(
                view: view,
                imageHost: _Host(fixture),
                imageAnchorController: controller,
              ),
              const SizedBox(height: 900),
            ],
          ),
        ),
      ),
    );
    final images = find.byType(ForumHtmlImageView);
    final target = tester.getTopLeft(images.last).dy;
    expect(target, greaterThan(tester.getTopLeft(images.first).dy));
    final entry = entries.last;
    Future<bool> reveal() => controller.revealImage(
      index: entry.index,
      cacheKey: entry.cacheKey,
      url: entry.url,
      scrollController: scroll,
      isCurrent: () => true,
    );
    final result = reveal();
    await tester.pump();
    expect(await result, isTrue);
    expect(scroll.offset, closeTo(target, 0.5));

    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          controller: scroll,
          child: const SizedBox(height: 1000),
        ),
      ),
    );
    expect(await reveal(), isFalse);
    expect(fixture.cache.activeLeases, 0);
  });

  for (final changeHost in [false, true]) {
    testWidgets(
      'a pending image tap retires without remounting pixels: Host=$changeHost',
      (tester) async {
        final f = InlineImageFixture(sticker: false),
            a = _Host(f),
            b = _Host(f),
            view = f.view();
        final taps = <ForumBodyInlineImageBinding>[];
        Widget build(_Host host, String identity) => _host(
          ForumBodyInlineImageSurface(
            view: view,
            imageHost: host,
            interactionIdentity: identity,
            onImageTap: taps.add,
          ),
        );
        await tester.pumpWidget(build(a, 'first'));
        await tester.pump();
        final element = tester.element(find.byType(ForumHtmlImageView).at(1));
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(ForumHtmlImageView).at(1)),
        );
        await tester.pumpWidget(
          build(changeHost ? b : a, changeHost ? 'first' : 'second'),
        );
        await gesture.up();
        await tester.pump();
        expect(taps, isEmpty);
        expect(
          tester.element(find.byType(ForumHtmlImageView).at(1)),
          same(element),
        );
        await tester.tap(find.byType(ForumHtmlImageView).at(1));
        expect(taps.single, same(view.images[1]));
        await tester.pumpWidget(const SizedBox.shrink());
        expect(f.cache.activeLeases, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'a replacement view cannot report retired resources as the new delivery',
    (tester) async {
      final f = InlineImageFixture(), other = InlineImageFixture(before: 'X');
      final a = _Host(f),
          b = _Host(other),
          first = f.view(),
          next = other.view();
      final events = <ForumBodyInlineImageBinding>[];
      Widget build(ForumBodyInlineParagraphView view, _Host host) => _host(
        ForumBodyInlineImageSurface(
          key: const ValueKey('stable-slot'),
          view: view,
          imageHost: host,
          onImageDisplayChanged: (image, frame) {
            expect(view.images[image.atomIndex], same(image));
            events.add(image);
          },
        ),
      );
      await tester.pumpWidget(build(first, a));
      await tester.pump();
      final retired = tester.widget<_Pixels>(find.byType(_Pixels).first);
      retired.frame!();
      expect(events, hasLength(1));
      events.clear();
      await tester.pumpWidget(build(next, b));
      await tester.pump();
      expect(events, isEmpty);
      expect(first.isActive, isFalse);
      retired.frame!();
      retired.failed!();
      retired.resolved!(const Size(60, 30));
      expect(events, isEmpty);
      expect(next.hasRenderedImages, isFalse);
      tester.widget<_Pixels>(find.byType(_Pixels).first).frame!();
      expect(events.single, same(next.images[0]));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(f.cache.activeLeases, 0);
      expect(other.cache.activeLeases, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an unmounted image Surface without a Host leaves ownership with its caller',
    (tester) async {
      final f = InlineImageFixture(), view = f.view();
      await tester.pumpWidget(_host(ForumBodyInlineImageSurface(view: view)));
      expect(tester.takeException(), isA<ForumBodyInlineViewException>());
      await tester.pumpWidget(const SizedBox.shrink());
      expect(view.isActive, isTrue);
      view.close();
      expect(f.cache.activeLeases, 0);
    },
  );

  testWidgets(
    'shared image views report frames independently from dimensions and glyphs',
    (tester) async {
      final f = InlineImageFixture(), host = _Host(f), view = f.view();
      final events = <(int, bool)>[];
      final sizes = <(int, ForumHtmlImageLayout)>[];
      final builds = f.cache.layoutBuildCount;
      await tester.pumpWidget(
        _host(
          ForumBodyInlineImageSurface(
            view: view,
            imageHost: host,
            onImageDisplayChanged: (image, frame) =>
                events.add((image.atomIndex, frame)),
            onImageLayoutResolved: (image, layout) =>
                sizes.add((image.atomIndex, layout)),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ForumHtmlImageView), findsNWidgets(2));
      final pixels = tester.widgetList<_Pixels>(find.byType(_Pixels)).toList();
      final bounds = tester.getRect(find.byType(ForumHtmlImageView).first);
      expect(view.hasRenderedImages, isFalse);
      pixels[0].resolved!(const Size(60, 30));
      await tester.pump();
      expect(sizes.single.$1, 0);
      expect(sizes.single.$2.displaySize, const Size(60, 30));
      expect(tester.getRect(find.byType(ForumHtmlImageView).first), bounds);
      expect(view.hasRenderedImages, isFalse);
      pixels[0].frame!();
      pixels[1].frame!();
      expect(view.hasRenderedImages, isTrue);
      pixels[0].failed!();
      expect(view.hasRenderedImages, isFalse);
      expect(events, [(0, true), (1, true), (0, false)]);
      expect(f.cache.layoutBuildCount, builds);
      await tester.pumpWidget(const SizedBox.shrink());
      pixels[0].frame!();
      pixels[0].resolved!(const Size(90, 30));
      expect(events, hasLength(3));
      expect(sizes, hasLength(1));
      expect(view.isActive, isFalse);
      expect(f.cache.activeLeases, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Host A to B to A retires pixel callbacks without remounting text or images',
    (tester) async {
      final f = InlineImageFixture(),
          a = _Host(f),
          b = _Host(f),
          view = f.view();
      final events = <(int, bool)>[];
      final sizes = <ForumHtmlImageLayout>[];
      Widget build(_Host host) => _host(
        ForumBodyInlineImageSurface(
          key: const ValueKey('inline'),
          view: view,
          imageHost: host,
          onImageDisplayChanged: (image, frame) =>
              events.add((image.atomIndex, frame)),
          onImageLayoutResolved: (_, layout) => sizes.add(layout),
        ),
      );
      await tester.pumpWidget(build(a));
      await tester.pump();
      final element = tester.element(find.byType(ForumHtmlImageView).first);
      final retiredA = tester
          .widgetList<_Pixels>(find.byType(_Pixels))
          .toList();
      for (final p in retiredA) {
        p.frame!();
      }
      expect(view.hasRenderedImages, isTrue);
      final builds = f.cache.layoutBuildCount;
      await tester.pumpWidget(build(b));
      await tester.pump();
      final retiredB = tester.widget<_Pixels>(find.byType(_Pixels).first);
      expect(view.hasRenderedImages, isFalse);
      await tester.pumpWidget(build(a));
      await tester.pump();
      retiredA[0].frame!();
      retiredA[0].resolved!(const Size(60, 30));
      retiredB.frame!();
      retiredB.resolved!(const Size(60, 30));
      expect(view.hasRenderedImages, isFalse);
      expect(sizes, isEmpty);
      expect(events, [(0, true), (1, true), (0, false), (1, false)]);
      expect(
        tester.element(find.byType(ForumHtmlImageView).first),
        same(element),
      );
      expect(f.cache.layoutBuildCount, builds);
      for (final p in tester.widgetList<_Pixels>(find.byType(_Pixels))) {
        p.frame!();
      }
      expect(view.hasRenderedImages, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(f.cache.activeLeases, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real source-bound image taps never enter the text tap callback',
    (tester) async {
      final f = InlineImageFixture(sticker: false),
          a = _Host(f),
          b = _Host(f),
          view = f.view();
      final taps = <ForumBodyInlineImageBinding>[],
          newer = <ForumBodyInlineImageBinding>[];
      var textTaps = 0;
      Widget build(_Host host, ValueChanged<ForumBodyInlineImageBinding> tap) =>
          _host(
            ForumBodyInlineImageSurface(
              view: view,
              imageHost: host,
              onImageTap: tap,
              onSourceTap: (_) => textTaps++,
            ),
          );
      await tester.pumpWidget(build(a, taps.add));
      await tester.pump();
      await tester.tap(find.byType(ForumHtmlImageView).at(1));
      expect(taps.single, same(view.images[1]));
      expect(textTaps, 0);
      final oldTap = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .where((g) => g.properties.label == 'server image')
          .last
          .properties
          .onTap!;
      await tester.pumpWidget(build(a, newer.add));
      oldTap();
      expect(newer.single, same(view.images[1]));
      await tester.pumpWidget(build(b, newer.add));
      await tester.pumpWidget(build(a, newer.add));
      oldTap();
      expect(newer, hasLength(1));
      final origin = tester.getTopLeft(
        find.byType(ForumBodyInlineImageSurface),
      );
      await tester.tapAt(origin + const Offset(2, 10));
      expect(textTaps, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      oldTap();
      expect(newer, hasLength(1));
      expect(f.cache.activeLeases, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final wrong in [
    const InlineImageDescription(
      sourceUrl: 'https://example.invalid/other.png',
    ),
    const InlineImageDescription(keyOverride: 'other'),
    const InlineImageDescription(isSticker: false),
    const InlineImageDescription(htmlSize: Size(30, 30)),
  ]) {
    testWidgets(
      'a different display binding cannot substitute ${wrong.identity}',
      (tester) async {
        final f = InlineImageFixture(),
            host = _Host(f)..displayOverride = wrong,
            view = f.view();
        await tester.pumpWidget(
          _host(ForumBodyInlineImageSurface(view: view, imageHost: host)),
        );
        expect(tester.takeException(), isA<ForumBodyInlineViewException>());
        expect(host.builds, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        view.close();
        expect(f.cache.activeLeases, 0);
      },
    );
  }

  testWidgets(
    'retired owner callbacks cannot confirm images still mounted in a Surface',
    (tester) async {
      final f = InlineImageFixture(), host = _Host(f), view = f.view();
      final events = <bool>[];
      await tester.pumpWidget(
        _host(
          ForumBodyInlineImageSurface(
            view: view,
            imageHost: host,
            onImageDisplayChanged: (_, frame) => events.add(frame),
          ),
        ),
      );
      await tester.pump();
      final retired = tester.widget<_Pixels>(find.byType(_Pixels).first);
      f.cache.close();
      retired.frame!();
      retired.resolved!(const Size(60, 30));
      expect(events, isEmpty);
      expect(view.hasRenderedImages, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(f.cache.activeLeases, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'typed Page Surface forwards only the current inline resource delivery',
    (tester) async {
      final f = InlineImageFixture(sticker: false),
          host = _Host(f),
          input = f.content();
      final composer = ForumBodyTextPageComposer(
        identity: f.document.identity,
        layoutId: 'inline-images',
        width: 100,
        height: 100,
        maxPages: 10,
        maxFragments: 10,
      );
      addTearDown(composer.close);
      composer.appendInline(
        lease: f.parent(input: input),
        paragraphIndex: 0,
        left: 0,
        spaceBefore: 0,
        spaceAtPageStart: 0,
        nativeHandleCountInRange: (_, _) => 1,
      );
      while (!composer.needsInput) {
        composer.advance(maxLines: 1);
      }
      composer.finish();
      final view = f.view(input: input),
          prepared = ForumBodyPreparedInlineFragment(view);
      final frames = <ForumBodyInlineImageBinding>[],
          taps = <ForumBodyInlineImageBinding>[];
      await tester.pumpWidget(
        _host(
          ForumBodyTextPageSurface.prepared(
            snapshot: composer.snapshot,
            pageIndex: 0,
            layoutId: 'inline-images',
            fragments: [prepared],
            imageHost: host,
            onInlineImageDisplayChanged: (fragment, image, rendered) {
              expect(fragment, same(prepared));
              if (rendered) frames.add(image);
            },
            onInlineImageTap: (fragment, image) {
              expect(fragment, same(prepared));
              taps.add(image);
            },
          ),
        ),
      );
      await tester.pump();
      final pixels = tester.widgetList<_Pixels>(find.byType(_Pixels)).toList();
      pixels[1].frame!();
      expect(frames.single, same(view.images[1]));
      await tester.tap(find.byType(ForumHtmlImageView).at(1));
      expect(taps.single, same(view.images[1]));
      final image = view.images[1]!;
      expect(
        forumBodyTextSelectionAt(
          binding: prepared,
          fragment: composer.snapshot.single.fragments.single,
          pageSize: const Size(100, 100),
          point: image.rect.center,
        ),
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      pixels[1].frame!();
      expect(frames, hasLength(1));
      expect(f.cache.activeLeases, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

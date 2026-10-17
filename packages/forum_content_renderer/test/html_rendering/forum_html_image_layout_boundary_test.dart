import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'render_test_support.dart';

void main() {
  for (final (fails, mixedText) in [
    (true, false),
    (false, false),
    (true, true),
    (false, true),
  ]) {
    testWidgets(
      '${fails ? 'failed' : 'displayed'} ${mixedText ? 'mixed-text' : 'standalone'} table images change viewport mode without laying out the body',
      (tester) async {
        final scroll = ScrollController();
        final viewport = _viewport();
        final host = _LocalImageHost(fails: fails);
        final document = prepareRenderTestDocument(
          _nestedImages(mixedText: mixedText),
          sourceId: 'layout',
        );
        addTearDown(scroll.dispose);
        addTearDown(viewport.dispose);
        var layouts = 0;
        await tester.pumpWidget(
          _page(
            document: document,
            host: host,
            scroll: scroll,
            viewport: viewport,
            onLayout: () => layouts++,
          ),
        );
        await _settle(tester);
        expect(scroll.position.maxScrollExtent, greaterThan(500));
        expect(host.mounts, greaterThan(0));
        final initialLayouts = layouts;
        final initialMounts = host.mounts;
        final initialSizes = [
          for (var index = 0; index < 6; index++) tester.getSize(_image(index)),
        ];
        for (var index = 0; index < 6; index++) {
          _expectImageFitsCell(tester, index);
        }

        for (final fraction in [
          0.2,
          0.4,
          0.6,
          0.8,
          1.0,
          0.8,
          0.6,
          0.4,
          0.2,
          0.0,
        ]) {
          scroll.jumpTo(scroll.position.maxScrollExtent * fraction);
          await _settle(tester);
          expect(
            layouts,
            initialLayouts,
            reason: 'A viewport mode change preserves the image geometry.',
          );
          for (var index = 0; index < 6; index++) {
            expect(tester.getSize(_image(index)), initialSizes[index]);
            _expectImageFitsCell(tester, index);
          }
        }

        // The geometry assertion must include real mount/unmount transitions,
        // rather than passing because all images stayed active throughout.
        expect(host.mounts, greaterThan(initialMounts));
        expect(host.disposals, greaterThan(0));
        expect(viewport.registeredImageCount, 6);
      },
    );
  }

  testWidgets('real dimensions and width changes still update table geometry', (
    tester,
  ) async {
    final scroll = ScrollController();
    final viewport = _viewport();
    final anchors = ForumHtmlImageAnchorController();
    final host = _LocalImageHost(fails: false);
    final document = prepareRenderTestDocument(
      _nestedImages(mixedText: true),
      sourceId: 'layout',
    );
    addTearDown(scroll.dispose);
    addTearDown(viewport.dispose);
    addTearDown(anchors.dispose);
    var layouts = 0;
    Widget page(double width) => _page(
      document: document,
      host: host,
      scroll: scroll,
      viewport: viewport,
      anchors: anchors,
      width: width,
      onLayout: () => layouts++,
    );
    await tester.pumpWidget(page(320));
    await _settle(tester);
    final first = _image(0);
    final before = tester.getSize(first);
    _expectImageFitsCell(tester, 0);
    final beforeDimensions = layouts;
    host.active['https://example.invalid/layout/0.png']!.resolveSize(
      const Size(160, 320),
    );
    await _settle(tester);
    expect(layouts, greaterThan(beforeDimensions));
    expect(tester.getSize(first).height, closeTo(before.height * 2, 0.5));
    _expectImageFitsCell(tester, 0);

    final target = _image(3);
    final targetElement = tester.element(target);
    final beforeWidthChange = layouts;
    await tester.pumpWidget(page(280));
    await _settle(tester);
    expect(layouts, greaterThan(beforeWidthChange));
    expect(tester.getSize(find.byType(_LayoutCounter)).width, 280);
    expect(tester.element(target), same(targetElement));
    for (var index = 0; index < 6; index++) {
      _expectImageFitsCell(tester, index);
    }

    final entry = document.sequence.entries[3];
    final revealed = anchors.revealImage(
      index: entry.index,
      cacheKey: entry.cacheKey,
      url: entry.url,
      scrollController: scroll,
      isCurrent: () => true,
    );
    await _settle(tester);
    expect(await revealed, isTrue);
    expect(
      tester.getTopLeft(target).dy,
      closeTo(tester.getTopLeft(find.byKey(const Key('viewport'))).dy, 0.5),
    );
  });
}

ForumHtmlImageViewportCoordinator _viewport() =>
    ForumHtmlImageViewportCoordinator(
      maxVisibleFirstFrames: 4,
      maxPrefetchCandidates: 0,
      maxConcurrentOptionalWork: 0,
      prefetchExtentFactor: 0,
    );

Finder _image(int index) =>
    find.byKey(Key('thread-post-html-first-readable-image-layout-$index'));

void _expectImageFitsCell(WidgetTester tester, int index) {
  final image = _image(index);
  final box = tester.renderObject<RenderBox>(image);
  RenderBox? cell;
  tester.element(image).visitAncestorElements((element) {
    if (element.widget is HtmlTableCell) {
      cell = element.findRenderObject()! as RenderBox;
      return false;
    }
    return true;
  });
  expect(cell, isNotNull);
  final imageRect = MatrixUtils.transformRect(
    box.getTransformTo(cell),
    Offset.zero & box.size,
  );
  expect(imageRect.left, greaterThanOrEqualTo(-0.5));
  expect(imageRect.right, lessThanOrEqualTo(cell!.size.width + 0.5));
  expect(imageRect.top, greaterThanOrEqualTo(-0.5));
  expect(imageRect.bottom, lessThanOrEqualTo(cell!.size.height + 0.5));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 16),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 2),
  );
  expect(tester.binding.hasScheduledFrame, isFalse);
  expect(tester.takeException(), isNull);
}

String _nestedImages({bool mixedText = false}) => [
  for (var index = 0; index < 6; index++)
    '<table><tr><td>Section $index</td><td>'
        '<table><tr><td>'
        '${mixedText ? 'Text before the image. ' : ''}'
        '<img src="https://example.invalid/layout/$index.png" width="240">'
        '${mixedText ? ' Text after the image.' : ''}'
        '</td></tr></table>'
        '</td></tr></table><p>Additional sample details.</p>',
].join();

Widget _page({
  required ForumHtmlPreparedRenderDocument document,
  required _LocalImageHost host,
  required ScrollController scroll,
  required ForumHtmlImageViewportCoordinator viewport,
  required VoidCallback onLayout,
  ForumHtmlImageAnchorController? anchors,
  double width = 320,
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        key: const Key('viewport'),
        width: width,
        height: 260,
        child: SingleChildScrollView(
          controller: scroll,
          child: _LayoutCounter(
            onLayout: onLayout,
            child: ForumHtmlRenderer(
              preparedDocument: document,
              theme: forumHtmlTestTheme,
              options: renderTestOptions,
              labels: renderTestLabels,
              sourceId: 'layout',
              imageHost: host,
              imageViewportCoordinator: viewport,
              imageAnchorController: anchors,
              buildAsync: false,
              enableCaching: true,
            ),
          ),
        ),
      ),
    ),
  ),
);

class _LayoutCounter extends SingleChildRenderObjectWidget {
  const _LayoutCounter({required this.onLayout, required super.child});

  final VoidCallback onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _LayoutCounterRenderObject(onLayout);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _LayoutCounterRenderObject renderObject,
  ) {
    renderObject.onLayout = onLayout;
  }
}

class _LayoutCounterRenderObject extends RenderProxyBox {
  _LayoutCounterRenderObject(this.onLayout);

  VoidCallback onLayout;

  @override
  void performLayout() {
    onLayout();
    super.performLayout();
  }
}

final class _LocalImageHost implements ForumHtmlImageHost {
  _LocalImageHost({required this.fails});

  final bool fails;
  final active = <String, _LocalImageSlotState>{};
  var mounts = 0;
  var disposals = 0;

  @override
  ForumHtmlDisplayImage resolveImage({
    required Uri url,
    required int? imageIndex,
    required bool isSticker,
    Size? htmlSize,
  }) => _LocalImage(url.toString(), isSticker, htmlSize);

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
  }) => _LocalImageSlot(
    host: this,
    image: image,
    placeholder: placeholder,
    onImageResolved: onImageResolved,
    onImageFailed: onImageFailed,
    onFirstFrameRendered: onFirstFrameRendered,
  );
}

final class _LocalImage implements ForumHtmlDisplayImage {
  const _LocalImage(this.sourceUrl, this.isSticker, this.htmlSize);

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
  ForumHtmlImageLayout get initialLayout =>
      const ForumHtmlImageLayout(isFallback: true, aspectRatio: 1);
}

class _LocalImageSlot extends StatefulWidget {
  const _LocalImageSlot({
    required this.host,
    required this.image,
    required this.placeholder,
    this.onImageResolved,
    this.onImageFailed,
    this.onFirstFrameRendered,
  });

  final _LocalImageHost host;
  final ForumHtmlDisplayImage image;
  final Widget placeholder;
  final ValueChanged<Size>? onImageResolved;
  final VoidCallback? onImageFailed;
  final VoidCallback? onFirstFrameRendered;

  @override
  State<_LocalImageSlot> createState() => _LocalImageSlotState();
}

class _LocalImageSlotState extends State<_LocalImageSlot> {
  var _settled = false;

  @override
  void initState() {
    super.initState();
    widget.host.mounts++;
    widget.host.active[widget.image.sourceUrl] = this;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _settled = true);
      if (widget.host.fails) {
        widget.onImageFailed?.call();
      } else {
        widget.onFirstFrameRendered?.call();
      }
    });
  }

  void resolveSize(Size size) => widget.onImageResolved?.call(size);

  @override
  Widget build(BuildContext context) => !_settled
      ? widget.placeholder
      : widget.host.fails
      ? const Center(child: Icon(Icons.broken_image_outlined))
      : const ColoredBox(color: Colors.teal);

  @override
  void dispose() {
    widget.host.active.remove(widget.image.sourceUrl);
    widget.host.disposals++;
    super.dispose();
  }
}

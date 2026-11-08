import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/experimental_continuous.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'continuous_test_support.dart';

Map<String, ForumBodyInlineImageSource> sources(
  ForumBodyDocument body, {
  double ratio = 1,
}) => {
  for (final element in body.imageElements)
    element.path: ForumBodyInlineImageSource(
      document: body,
      element: element,
      image: _Image(element.resource!.rawSource!, ratio),
      entry: ForumHtmlReadableImageEntry(
        index: body.imageElements.indexOf(element),
        url: element.resource!.rawSource!,
        rawSrc: element.resource!.rawSource!,
        resource: _Resource(element.resource!.rawSource!),
      ),
    ),
};

const imageHtml = '<img src="https://example.invalid/image.png">';

void main() {
  testWidgets('actual image child paints and owns taps between source text', (
    tester,
  ) async {
    final body = document('<p>before</p>$imageHtml<p>after</p>');
    final c = ForumBodyContinuousController(), host = _Host();
    final images = sources(body);
    final boundary = GlobalKey();
    ForumBodyInlineImageSource? tapped;
    await tester.pumpWidget(
      scene(
        body,
        c,
        images: images,
        imageHost: host,
        boundary: boundary,
        onImageTap: (source) => tapped = source,
      ),
    );
    expect(c.isReady, isTrue);
    expect(c.size!.height, closeTo(170, .01));
    expect(c.copyText, 'before\nafter');
    expect(c.hitTest(const Offset(5, 60)), isNull);
    expect(c.hitTest(const Offset(5, 165))!.source.sourceRune, 6);
    expect(tester.getSize(find.byType(_Pixels)), const Size(150, 150));
    final red = await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final pixels = await render.toImage();
      final bytes = (await pixels.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      var red = 0;
      for (var i = 0; i < bytes.lengthInBytes; i += 4) {
        if (bytes.getUint8(i) > 230 &&
            bytes.getUint8(i + 1) < 100 &&
            bytes.getUint8(i + 2) < 100 &&
            bytes.getUint8(i + 3) > 240) {
          red++;
        }
      }
      pixels.dispose();
      return red;
    });
    expect(red, greaterThan(22000));
    await tester.tapAt(tester.getCenter(find.byType(_Pixels)));
    expect(tapped, same(images.values.single));
    expect(host.pending, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    host.pending.single.complete(null);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dimension reflow repositions text and retains its text painters',
    (tester) async {
      final body = document('<p>before</p>$imageHtml<p>after</p>');
      final c = ForumBodyContinuousController(), host = _Host();
      await tester.pumpWidget(
        scene(body, c, images: sources(body), imageHost: host),
      );
      final shaped = c.textPainterCreationCount, layouts = c.layoutCount;
      host.pending.single.complete((
        size: const Size(400, 200),
        layout: const ForumHtmlImageLayout(
          aspectRatio: 2,
          displaySize: Size(400, 200),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(c.size!.height, closeTo(95, .01));
      expect(c.layoutCount, greaterThan(layouts));
      expect(c.textPainterCreationCount, shaped);
      expect(c.hitTest(const Offset(5, 90))!.source.sourceRune, 6);
      expect(c.copyText, 'before\nafter');
      await tester.pumpWidget(const SizedBox.shrink());
      expect(c.isReady, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('A to B to A Host replacement rejects old dimensions and taps', (
    tester,
  ) async {
    final body = document('<p>before</p>$imageHtml<p>after</p>');
    final c = ForumBodyContinuousController(), a = _Host(), b = _Host();
    final images = sources(body);
    var taps = 0;
    Widget build(_Host host) => scene(
      body,
      c,
      images: images,
      imageHost: host,
      onImageTap: (_) => taps++,
    );
    await tester.pumpWidget(build(a));
    final retired = tester.widget<_Pixels>(find.byType(_Pixels));
    final shaped = c.textPainterCreationCount;
    final gesture = await tester.startGesture(const Offset(50, 50));
    await tester.pumpWidget(build(b));
    await gesture.up();
    await tester.pumpWidget(build(a));
    expect(taps, 0);
    expect(a.pending, hasLength(2));
    a.pending.first.complete((
      size: const Size(400, 100),
      layout: const ForumHtmlImageLayout(aspectRatio: 4),
    ));
    b.pending.single.complete((
      size: const Size(400, 100),
      layout: const ForumHtmlImageLayout(aspectRatio: 4),
    ));
    retired.onResolved?.call(const Size(800, 100));
    retired.onFrame?.call();
    await tester.pump();
    await tester.pump();
    expect(c.size!.height, closeTo(170, .01));
    expect(c.textPainterCreationCount, shaped);
    a.pending.last.complete((
      size: const Size(400, 200),
      layout: const ForumHtmlImageLayout(aspectRatio: 2),
    ));
    await tester.pump();
    await tester.pump();
    expect(c.size!.height, closeTo(95, .01));
    expect(c.textPainterCreationCount, shaped);
    await tester.pumpWidget(const SizedBox.shrink());
    retired.onResolved?.call(const Size(100, 800));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('CSS percentage width is applied once and explicit height wins', (
    tester,
  ) async {
    final body = document(
      '<img src="https://example.invalid/image.png" '
      'style="width:50%;height:60px">',
    );
    final c = ForumBodyContinuousController(), host = _Host();
    await tester.pumpWidget(
      scene(body, c, images: sources(body), imageHost: host),
    );
    expect(tester.getSize(find.byType(_Pixels)), const Size(75, 60));
    expect(c.size!.height, 60);
    await tester.pumpWidget(const SizedBox.shrink());
    host.pending.single.complete(null);
    await tester.pump();
  });

  testWidgets('a long continuous image has no page-height cap', (tester) async {
    final body = document('$imageHtml<p>after</p>');
    final c = ForumBodyContinuousController(), host = _Host();
    await tester.pumpWidget(
      scene(body, c, images: sources(body, ratio: .1), imageHost: host),
    );
    expect(tester.getSize(find.byType(_Pixels)), const Size(150, 1500));
    expect(c.size!.height, 1510);
    expect(c.hitTest(const Offset(5, 1505))!.source.sourceRune, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    host.pending.single.complete(null);
    await tester.pump();
  });

  testWidgets('border-box height subtracts padding at the containing width', (
    tester,
  ) async {
    final body = document(
      '<img src="https://example.invalid/image.png" '
      'style="width:50%;height:120px;box-sizing:border-box;padding:10% 0">',
    );
    final c = ForumBodyContinuousController(), host = _Host();
    await tester.pumpWidget(
      scene(body, c, images: sources(body), imageHost: host),
    );
    expect(tester.getSize(find.byType(_Pixels)), const Size(75, 90));
    expect(tester.getTopLeft(find.byType(_Pixels)), const Offset(0, 15));
    expect(c.size!.height, 120);
    await tester.pumpWidget(const SizedBox.shrink());
    host.pending.single.complete(null);
    await tester.pump();
  });

  testWidgets(
    'inline images remain explicit until mixed flow owns their rows',
    (tester) async {
      final body = document(
        '<p>before<img src="https://example.invalid/image.png" '
        'style="display:inline">after</p>',
      );
      final c = ForumBodyContinuousController(), host = _Host();
      await tester.pumpWidget(
        scene(body, c, images: sources(body), imageHost: host),
      );
      expect(
        tester.takeException(),
        isA<ForumBodyContinuousUnsupported>().having(
          (e) => e.kind,
          'kind',
          'inline-image',
        ),
      );
      expect(host.pending, isEmpty);
      expect(c.isReady, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'hidden resources have geometry without requiring a display Host',
    (tester) async {
      final body = document(
        '<p>a</p><div style="visibility:hidden">'
        '<img src="https://example.invalid/hidden.png" width="30" height="20">'
        '</div><div style="display:none">$imageHtml</div><p>b</p>',
      );
      final c = ForumBodyContinuousController();
      await tester.pumpWidget(scene(body, c));
      expect(c.isReady, isTrue);
      expect(c.size!.height, closeTo(120, .01));
      expect(c.copyText, 'a\nb');
      expect(find.byType(ForumHtmlImageView), findsNothing);
      expect(c.hitTest(const Offset(5, 50)), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

final class _Image implements ForumHtmlDisplayImage {
  const _Image(this.sourceUrl, this.ratio);
  @override
  final String sourceUrl;
  final double ratio;
  @override
  String get cacheKey => sourceUrl;
  @override
  Object get identity => (sourceUrl, ratio);
  @override
  bool get isSticker => false;
  @override
  Size? get htmlSize => null;
  @override
  ForumHtmlImageLayout get initialLayout =>
      ForumHtmlImageLayout(isFallback: true, aspectRatio: ratio);
}

final class _Resource implements ForumHtmlPreparedImageResource {
  const _Resource(this.cacheKey);
  @override
  final String cacheKey;
}

typedef _Dimensions = ({Size size, ForumHtmlImageLayout layout});

final class _Host implements ForumHtmlImageHost {
  final pending = <Completer<_Dimensions?>>[];
  @override
  Future<_Dimensions?> loadDimensions(ForumHtmlDisplayImage image) {
    final result = Completer<_Dimensions?>();
    pending.add(result);
    return result.future;
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
  }) => _Pixels(onResolved: onImageResolved, onFrame: onFirstFrameRendered);
  @override
  void onBlockImageResolved(ForumHtmlDisplayImage image, Size size) {}
  @override
  Future<void> prefetchDisk(
    ForumHtmlDisplayImage image, {
    required ForumHtmlImageWorkScope scope,
  }) async {}
  @override
  ForumHtmlDisplayImage? resolveImage({
    required Uri url,
    required int? imageIndex,
    required bool isSticker,
    Size? htmlSize,
  }) => throw UnimplementedError();
}

final class _Pixels extends StatelessWidget {
  const _Pixels({this.onResolved, this.onFrame});
  final ValueChanged<Size>? onResolved;
  final VoidCallback? onFrame;
  @override
  Widget build(BuildContext context) =>
      const RepaintBoundary(child: ColoredBox(color: Colors.red));
}

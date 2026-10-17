import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'render_test_support.dart';

void main() {
  testWidgets('block frame geometry never queries transient image content', (
    tester,
  ) async {
    final contentKey = GlobalKey();
    final meterKey = GlobalKey();
    await tester.pumpWidget(
      _host(
        width: 240,
        child: _IntrinsicLayoutMeter(
          key: meterKey,
          geometryContentKey: contentKey,
          child: _renderBlockImage(
            ratio: 2,
            child: _ContentProbe(key: contentKey, rejectGeometryQueries: true),
          ),
        ),
      ),
    );
    final content =
        contentKey.currentContext!.findRenderObject()! as _ContentProbeBox;
    final frame = _imageFrame(content);
    final meter =
        meterKey.currentContext!.findRenderObject()!
            as _IntrinsicLayoutMeterBox;
    expect(frame.size, const Size(240, 120));
    expect(content.size, frame.size);
    expect(frame.getMinIntrinsicWidth(30), 60);
    expect(frame.getMaxIntrinsicWidth(30), 60);
    expect(frame.getMinIntrinsicHeight(120), 60);
    expect(frame.getMaxIntrinsicHeight(120), 60);
    expect(frame.getMinIntrinsicWidth(double.infinity), 0);
    expect(frame.getMaxIntrinsicWidth(double.infinity), 0);
    expect(frame.getMinIntrinsicHeight(double.infinity), 0);
    expect(frame.getMaxIntrinsicHeight(double.infinity), 0);
    expect(
      frame.getDryLayout(const BoxConstraints.tightFor(width: 120)),
      const Size(120, 60),
    );
    // Actual baselines must be read by the parent during layout, per SDK API.
    expect(meter.actualBaseline, isNull);
    expect(
      frame.getDryBaseline(
        const BoxConstraints.tightFor(width: 120),
        TextBaseline.alphabetic,
      ),
      isNull,
    );
    expect(content.geometryQueries, 0);
    expect(tester.takeException(), isNull);
  });

  for (final isolateContent in [false, true]) {
    testWidgets(
      '${isolateContent ? 'block frame isolates' : 'default aspect ratio forwards'} '
      'cached intrinsic dependencies',
      (tester) async {
        final meterKey = GlobalKey();
        final contentKey = GlobalKey();
        Widget page({double ratio = 2, double width = 240}) {
          final content = _ContentProbe(key: contentKey);
          return _host(
            width: width,
            child: _IntrinsicLayoutMeter(
              key: meterKey,
              geometryContentKey: isolateContent ? contentKey : null,
              child: isolateContent
                  ? _renderBlockImage(ratio: ratio, child: content)
                  : AspectRatio(aspectRatio: ratio, child: content),
            ),
          );
        }

        await tester.pumpWidget(page());
        final meter =
            meterKey.currentContext!.findRenderObject()!
                as _IntrinsicLayoutMeterBox;
        final content =
            contentKey.currentContext!.findRenderObject()! as _ContentProbeBox;
        final initialLayouts = meter.layouts;
        final initialContentLayouts = content.layouts;
        expect(content.geometryQueries, isolateContent ? 0 : greaterThan(0));

        // This leaf accepts intrinsic queries in debug and release alike. Its
        // cached queries make the SDK control propagate past a tight boundary.
        content.markNeedsLayout();
        await tester.pump();
        expect(content.layouts, initialContentLayouts + 1);
        expect(meter.layouts, initialLayouts + (isolateContent ? 0 : 1));

        final beforeRatioChange = meter.layouts;
        await tester.pumpWidget(page(ratio: 1));
        expect(meter.layouts, greaterThan(beforeRatioChange));
        expect(meter.size, const Size(240, 240));

        final beforeWidthChange = meter.layouts;
        await tester.pumpWidget(page(ratio: 1, width: 180));
        expect(meter.layouts, greaterThan(beforeWidthChange));
        expect(meter.size, const Size(180, 180));
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Widget _host({required double width, required Widget child}) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: width, child: child),
    ),
  ),
);

Widget _renderBlockImage({required double ratio, required Widget child}) =>
    ForumHtmlRenderer(
      preparedDocument: prepareRenderTestDocument(
        '<img src="https://example.invalid/frame.png">',
      ),
      theme: forumHtmlTestTheme,
      options: renderTestOptions,
      labels: renderTestLabels,
      imageHost: _ProbeImageHost(ratio: ratio, child: child),
      buildAsync: false,
      enableCaching: true,
    );

RenderAspectRatio _imageFrame(RenderObject content) {
  // Locate the frame produced by the public renderer, keeping its concrete
  // widget and render-object implementation private to the package.
  RenderObject? ancestor = content.parent;
  while (ancestor != null) {
    if (ancestor is RenderAspectRatio) return ancestor;
    ancestor = ancestor.parent;
  }
  throw StateError('The block image has no aspect-ratio frame');
}

final class _ProbeImageHost implements ForumHtmlImageHost {
  const _ProbeImageHost({required this.ratio, required this.child});

  final double ratio;
  final Widget child;

  @override
  ForumHtmlDisplayImage resolveImage({
    required Uri url,
    required int? imageIndex,
    required bool isSticker,
    Size? htmlSize,
  }) => _ProbeImage(url.toString(), ratio);

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
  }) => child;
}

final class _ProbeImage implements ForumHtmlDisplayImage {
  const _ProbeImage(this.sourceUrl, this.ratio);

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
      ForumHtmlImageLayout(aspectRatio: ratio);
}

class _IntrinsicLayoutMeter extends SingleChildRenderObjectWidget {
  const _IntrinsicLayoutMeter({
    super.key,
    required super.child,
    this.geometryContentKey,
  });

  final GlobalKey? geometryContentKey;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _IntrinsicLayoutMeterBox(geometryContentKey);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _IntrinsicLayoutMeterBox renderObject,
  ) {
    renderObject.geometryContentKey = geometryContentKey;
  }
}

class _IntrinsicLayoutMeterBox extends RenderProxyBox {
  _IntrinsicLayoutMeterBox(this.geometryContentKey);

  GlobalKey? geometryContentKey;
  var layouts = 0;
  double? actualBaseline;

  @override
  void performLayout() {
    layouts++;
    final geometry = geometryContentKey == null
        ? child!
        : _imageFrame(geometryContentKey!.currentContext!.findRenderObject()!);
    // A crowded table can ask these before assigning a final cell width.
    // Gesture wrappers do not implement dry baselines; query the real frame
    // while still laying out the complete public renderer below this meter.
    geometry.getMinIntrinsicWidth(double.infinity);
    geometry.getMaxIntrinsicWidth(double.infinity);
    geometry.getMinIntrinsicHeight(double.infinity);
    geometry.getMaxIntrinsicHeight(double.infinity);
    geometry.getDryBaseline(
      BoxConstraints.tightFor(width: constraints.maxWidth),
      TextBaseline.alphabetic,
    );
    child!.layout(
      BoxConstraints.tightFor(width: constraints.maxWidth),
      parentUsesSize: true,
    );
    // The SDK requires actual baselines to be requested by the direct parent
    // during layout. Proxy boxes delegate this call down to the image frame.
    actualBaseline = child!.getDistanceToBaseline(
      TextBaseline.alphabetic,
      onlyReal: true,
    );
    size = constraints.constrain(child!.size);
  }
}

class _ContentProbe extends LeafRenderObjectWidget {
  const _ContentProbe({super.key, this.rejectGeometryQueries = false});

  final bool rejectGeometryQueries;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ContentProbeBox(rejectGeometryQueries);
}

class _ContentProbeBox extends RenderBox {
  _ContentProbeBox(this.rejectGeometryQueries);

  final bool rejectGeometryQueries;
  var layouts = 0;
  var geometryQueries = 0;

  void _geometryQuery() {
    geometryQueries++;
    if (rejectGeometryQueries) {
      throw StateError('Transient image content cannot supply frame geometry');
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    _geometryQuery();
    return 30;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    _geometryQuery();
    return 60;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    _geometryQuery();
    return 30;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    _geometryQuery();
    return 60;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    _geometryQuery();
    return 10;
  }

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    _geometryQuery();
    return 10;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    _geometryQuery();
    return constraints.constrain(const Size(60, 30));
  }

  @override
  void performLayout() {
    layouts++;
    size = constraints.constrain(const Size(60, 30));
  }
}

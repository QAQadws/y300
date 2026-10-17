import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/src/html_rendering/widgets/forum_html_block_image_frame.dart';

void main() {
  testWidgets('block frame geometry never queries transient image content', (
    tester,
  ) async {
    final frameKey = GlobalKey();
    final contentKey = GlobalKey();
    final meterKey = GlobalKey();
    await tester.pumpWidget(
      _host(
        width: 240,
        child: _IntrinsicLayoutMeter(
          key: meterKey,
          child: ForumHtmlBlockImageFrame(
            key: frameKey,
            aspectRatio: 2,
            child: _ContentProbe(key: contentKey, rejectGeometryQueries: true),
          ),
        ),
      ),
    );
    final frame = frameKey.currentContext!.findRenderObject()! as RenderBox;
    final content =
        contentKey.currentContext!.findRenderObject()! as _ContentProbeBox;
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
              child: isolateContent
                  ? ForumHtmlBlockImageFrame(aspectRatio: ratio, child: content)
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

Widget _host({required double width, required Widget child}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: width, child: child),
  ),
);

class _IntrinsicLayoutMeter extends SingleChildRenderObjectWidget {
  const _IntrinsicLayoutMeter({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _IntrinsicLayoutMeterBox();
}

class _IntrinsicLayoutMeterBox extends RenderProxyBox {
  var layouts = 0;
  double? actualBaseline;

  @override
  void performLayout() {
    layouts++;
    // A crowded table can ask these before assigning a final cell width.
    child!.getMinIntrinsicWidth(double.infinity);
    child!.getMaxIntrinsicWidth(double.infinity);
    child!.getMinIntrinsicHeight(double.infinity);
    child!.getMaxIntrinsicHeight(double.infinity);
    child!.getDryBaseline(
      BoxConstraints.tightFor(width: constraints.maxWidth),
      TextBaseline.alphabetic,
    );
    child!.layout(
      BoxConstraints.tightFor(width: constraints.maxWidth),
      parentUsesSize: true,
    );
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

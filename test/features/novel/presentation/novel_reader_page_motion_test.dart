import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_page_motion.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_paragraph_motion.dart';

void main() {
  test('live snap speed changes time without changing page destination', () {
    var scale = 1.0;
    final physics = NovelReaderPageScrollPhysics(durationScale: () => scale);
    final metrics = PageMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 640,
      pixels: 200,
      viewportDimension: 320,
      axisDirection: AxisDirection.right,
      viewportFraction: 1,
      devicePixelRatio: 1,
    );
    for (final velocity in [0.0, 20.0, -20.0, 800.0]) {
      scale = NovelReaderPageSpeed.relaxed.durationScale;
      final relaxed = physics.createBallisticSimulation(metrics, velocity)!;
      scale = NovelReaderPageSpeed.brisk.durationScale;
      final brisk = physics.createBallisticSimulation(metrics, velocity)!;
      expect(brisk.x(10), relaxed.x(10));
      var slowEnd = 0.0;
      while (!relaxed.isDone(slowEnd)) {
        slowEnd += 0.001;
      }
      var fastEnd = 0.0;
      while (!brisk.isDone(fastEnd)) {
        fastEnd += 0.001;
      }
      expect(fastEnd, lessThan(slowEnd));
    }
  });

  for (final direction in TextDirection.values) {
    for (final reverse in [false, true]) {
      for (final effect in NovelReaderPageEffect.values) {
        testWidgets(
          '$effect paints layered pages in $direction reverse=$reverse without relayout',
          (tester) async {
            final controller = PageController();
            addTearDown(controller.dispose);
            final boundaryKey = GlobalKey();
            var layouts = 0;
            await tester.pumpWidget(
              Directionality(
                textDirection: direction,
                child: Center(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: SizedBox(
                      width: 320,
                      height: 480,
                      child: PageView.builder(
                        controller: controller,
                        reverse: reverse,
                        itemCount: 2,
                        itemBuilder: (context, index) =>
                            NovelReaderPageTransition(
                              controller: controller,
                              index: index,
                              effect: effect,
                              reverse: reverse,
                              paperColor: Colors.white,
                              child: decorateNovelReaderParagraph(
                                context,
                                _CountLayout(
                                  onLayout: () => layouts++,
                                  child: ColoredBox(
                                    color: index == 0
                                        ? Colors.red
                                        : Colors.blue,
                                  ),
                                ),
                              ),
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            controller.jumpTo(160);
            await tester.pump();
            final boundary =
                boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final snapshot = (await tester.runAsync(() => boundary.toImage()))!;
            final pixels = (await tester.runAsync(
              () => snapshot.toByteData(format: ui.ImageByteFormat.rawRgba),
            ))!;
            Color pixel(int x) {
              final i = (240 * snapshot.width + x) * 4;
              return Color.fromARGB(
                pixels.getUint8(i + 3),
                pixels.getUint8(i),
                pixels.getUint8(i + 1),
                pixels.getUint8(i + 2),
              );
            }

            final physicalReverse = reverse != (direction == TextDirection.rtl);
            if (effect == NovelReaderPageEffect.fade) {
              expect(
                pixel(32).r,
                closeTo((Colors.red.r + Colors.blue.r) / 2, 0.01),
              );
              expect(pixel(288), pixel(32));
            } else {
              expect(
                pixel(physicalReverse ? 288 : 32).toARGB32(),
                Colors.red.toARGB32(),
              );
              expect(
                pixel(physicalReverse ? 32 : 288).toARGB32(),
                Colors.blue.toARGB32(),
              );
              if (effect == NovelReaderPageEffect.paper) {
                // The illuminated paper back is visible between the two sheets.
                final fold = pixel(physicalReverse ? 186 : 134);
                expect(fold.g, greaterThan(0.6));
              }
            }
            snapshot.dispose();
            final settledLayouts = layouts;
            controller.jumpTo(180);
            await tester.pump();
            expect(layouts, settledLayouts);
            controller.jumpToPage(1);
            await tester.pump();
            expect(controller.page, 1);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}

class _CountLayout extends SingleChildRenderObjectWidget {
  const _CountLayout({required this.onLayout, required super.child});
  final VoidCallback onLayout;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _LayoutCounter(onLayout);
}

class _LayoutCounter extends RenderProxyBox {
  _LayoutCounter(this.onLayout);
  final VoidCallback onLayout;
  @override
  void performLayout() {
    onLayout();
    super.performLayout();
  }
}

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_page_motion.dart';

void main() {
  const red = Color(0xFFFF0000), blue = Color(0xFF0000FF);
  test('fade and cover match the reference click clock and release speed', () {
    for (final (effect, milliseconds) in [
      (NovelReaderPageEffect.fade, 300),
      (NovelReaderPageEffect.cover, 340),
    ]) {
      expect(NovelReaderPageMotion.curve(effect), same(Curves.linear));
      for (final speed in NovelReaderPageSpeed.values) {
        expect(
          NovelReaderPageMotion.duration(effect, speed),
          Duration(milliseconds: (milliseconds * speed.durationScale).round()),
        );
        expect(
          NovelReaderPageMotion.snapDurationScale(effect, speed),
          speed.durationScale,
        );
      }
    }
  });

  for (final effect in [
    NovelReaderPageEffect.fade,
    NovelReaderPageEffect.cover,
  ]) {
    for (final direction in TextDirection.values) {
      for (final reverse in [false, true]) {
        testWidgets(
          '$effect covers full margins with reversible paint in $direction reverse=$reverse',
          (tester) async {
            final controller = PageController();
            final boundaryKey = GlobalKey();
            var layouts = 0;
            await tester.pumpWidget(
              Directionality(
                textDirection: direction,
                child: Center(
                  child: RepaintBoundary(
                    key: boundaryKey,
                    child: ColoredBox(
                      color: Colors.green,
                      child: SizedBox(
                        width: 360,
                        height: 520,
                        child: Center(
                          child: SizedBox(
                            width: 280,
                            height: 400,
                            child: PageView.builder(
                              controller: controller,
                              reverse: reverse,
                              clipBehavior: Clip.none,
                              itemCount: 2,
                              itemBuilder: (context, index) =>
                                  NovelReaderPageTransition(
                                    controller: controller,
                                    index: index,
                                    effect: effect,
                                    reverse: reverse,
                                    paperColor: index == 0 ? red : blue,
                                    paperInsets: const EdgeInsets.fromLTRB(
                                      40,
                                      60,
                                      40,
                                      60,
                                    ),
                                    child: _Counter(
                                      onLayout: () => layouts++,
                                      child: const SizedBox.expand(),
                                    ),
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
            final physicalReverse = reverse != (direction == TextDirection.rtl);
            for (final fraction in [.25, .5, .75, .5]) {
              controller.jumpTo(fraction * 280);
              await tester.pump();
              final settledLayouts = layouts;
              final boundary =
                  boundaryKey.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final snapshot = (await tester.runAsync(
                () => boundary.toImage(),
              ))!;
              final bytes = (await tester.runAsync(
                () => snapshot.toByteData(format: ui.ImageByteFormat.rawRgba),
              ))!;
              Color pixel(int x, [int y = 8]) {
                final i = (y * snapshot.width + x) * 4;
                return Color.fromARGB(
                  bytes.getUint8(i + 3),
                  bytes.getUint8(i),
                  bytes.getUint8(i + 1),
                  bytes.getUint8(i + 2),
                );
              }

              // Top/bottom and side margins participate in the same sheet as
              // its ink. A green gap would expose the outer host background.
              if (effect == NovelReaderPageEffect.fade) {
                for (final point in [(8, 8), (352, 512), (180, 260)]) {
                  final color = pixel(point.$1, point.$2);
                  expect(color.r, closeTo(1 - fraction, .005));
                  expect(color.b, closeTo(fraction, .005));
                  expect(color.g, 0);
                  expect(color.a, 1);
                }
              } else {
                final edge = (physicalReverse ? fraction : 1 - fraction) * 360;
                final lower = edge + (physicalReverse ? 36 : -36);
                final front = edge + (physicalReverse ? -2 : 2);
                final shadow = edge + (physicalReverse ? 2 : -2);
                expect(pixel(lower.round()), red);
                expect(pixel(front.round()), blue);
                expect(pixel(shadow.round()).r, lessThan(.99));
                expect(pixel(shadow.round()).b, 0);
                expect(pixel(physicalReverse ? 8 : 352, 512), blue);
              }
              snapshot.dispose();
              controller.jumpTo(fraction * 280 + .1);
              await tester.pump();
              expect(layouts, settledLayouts);
            }
            // Returning to the origin and turning back from page 1 must not
            // leave an alpha layer, shadow, or stale transformed child behind.
            controller.jumpToPage(1);
            await tester.pump();
            controller.jumpTo(140);
            await tester.pump();
            controller.jumpToPage(0);
            await tester.pump();
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            controller.dispose();
          },
        );
      }
    }
  }

  testWidgets('sheet effect changes retain the exact measured content box', (
    tester,
  ) async {
    final controller = PageController();
    final effect = ValueNotifier(NovelReaderPageEffect.slide);
    var layouts = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 280,
            height: 400,
            child: ValueListenableBuilder<NovelReaderPageEffect>(
              valueListenable: effect,
              builder: (context, value, _) => PageView(
                controller: controller,
                clipBehavior: Clip.none,
                children: [
                  NovelReaderPageTransition(
                    controller: controller,
                    index: 0,
                    effect: value,
                    reverse: false,
                    paperColor: Colors.white,
                    paperInsets: const EdgeInsets.fromLTRB(40, 60, 40, 60),
                    child: _Counter(
                      onLayout: () => layouts++,
                      child: const SizedBox.expand(
                        key: Key('retained-sheet-content'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final content = find.byKey(const Key('retained-sheet-content'));
    final rect = tester.getRect(content),
        element = tester.element(content),
        count = layouts;
    for (final value in [
      NovelReaderPageEffect.fade,
      NovelReaderPageEffect.cover,
      NovelReaderPageEffect.paper,
      NovelReaderPageEffect.slide,
    ]) {
      effect.value = value;
      await tester.pump();
      expect(tester.getRect(content), rect);
      expect(tester.element(content), same(element));
      expect(layouts, count);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    effect.dispose();
    controller.dispose();
  });
}

class _Counter extends SingleChildRenderObjectWidget {
  const _Counter({required this.onLayout, required super.child});
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

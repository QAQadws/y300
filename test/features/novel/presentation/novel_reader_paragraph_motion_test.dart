import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_paragraph_clock.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_page_motion.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_paragraph_motion.dart';

void main() {
  test(
    'drag settling uses the selected speed without a second relay clock',
    () {
      for (final speed in NovelReaderPageSpeed.values) {
        expect(
          NovelReaderPageMotion.snapDurationScale(
            NovelReaderPageEffect.staggered,
            speed,
          ),
          speed.durationScale,
        );
        expect(
          NovelReaderPageMotion.duration(
            NovelReaderPageEffect.staggered,
            speed,
          ),
          Duration(milliseconds: (620 * speed.durationScale).round()),
        );
      }
    },
  );

  test('relay samples match the reference sine interval on a linear clock', () {
    for (final (turn, expected) in [
      (0.02, 0.0),
      (0.22, 0.13703918457031247),
      (0.42, 0.502783190459013),
      (0.62, 0.8669293820858001),
      (0.82, 1.0),
    ]) {
      expect(
        NovelReaderParagraphMotion.progress(turn, 0),
        closeTo(expected, 1e-4),
      );
      expect(
        NovelReaderParagraphMotion.progress(turn + 0.18, 1),
        closeTo(expected, 1e-4),
      );
    }
  });

  for (final reverse in [false, true]) {
    testWidgets(
      'BR paragraphs relay backwards, reuse texture and cancel, reverse=$reverse',
      (tester) async {
        final controller = PageController(initialPage: 1);
        final clock = NovelReaderParagraphClock(controller);
        var layouts = 0;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: 320,
                height: 480,
                child: PageView.builder(
                  controller: controller,
                  reverse: reverse,
                  itemCount: 2,
                  itemBuilder: (context, index) => NovelReaderPageTransition(
                    controller: controller,
                    paragraphClock: clock,
                    index: index,
                    effect: NovelReaderPageEffect.staggered,
                    reverse: reverse,
                    paperColor: Colors.white,
                    child: decorateNovelReaderParagraph(
                      context,
                      _Counter(
                        onLayout: () => layouts++,
                        child: ForumHtmlParagraphMetrics(
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                fontSize: 18,
                                height: 1.6,
                                color: Colors.black,
                              ),
                              text:
                                  'Page $index first 😀\n\nSecond paragraph wraps into several shaped lines. '
                                  'Keep its style, spacing and complete lines intact.\nLast paragraph.',
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
        controller.jumpTo(160);
        await tester.pump();
        expect(clock.source, 1);
        expect(clock.target, 0);
        final snapshots = tester
            .widgetList<SnapshotWidget>(find.byType(SnapshotWidget))
            .where(
              (s) =>
                  s.painter.runtimeType.toString() ==
                  '_ParagraphSnapshotPainter',
            )
            .toList();
        expect(snapshots, hasLength(2));
        expect(snapshots.every((s) => s.controller.allowSnapshotting), isTrue);
        final parts = tester.allRenderObjects
            .where((r) => r.runtimeType.toString() == '_ParagraphPartRender')
            .toList();
        final motions = [
          for (final part in parts)
            List<Offset>.from((part as dynamic).paragraphDisplacements),
        ];
        expect(motions.every((m) => m.length == 3), isTrue);
        expect(
          motions.every((m) => m.map((d) => d.dx).toSet().length == 3),
          isTrue,
        );
        final count = layouts;
        controller.jumpTo(80);
        await tester.pump();
        controller.jumpTo(160);
        await tester.pump();
        expect(clock.source, 1);
        expect(clock.target, 0);
        expect(layouts, count);
        for (var i = 0; i < parts.length; i++) {
          expect((parts[i] as dynamic).paragraphDisplacements, motions[i]);
        }
        expect(
          snapshots.map((s) => (s.painter as dynamic).snapshotCount),
          everyElement(1),
        );
        controller.jumpToPage(1);
        await tester.pump();
        expect(snapshots.every((s) => !s.controller.allowSnapshotting), isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        clock.dispose();
        controller.dispose();
      },
    );
  }

  for (final reverse in [false, true]) {
    testWidgets(
      'unequal paragraphs relay without overlap or relayout, reverse=$reverse',
      (tester) async {
        final controller = PageController();
        addTearDown(controller.dispose);
        var layouts = 0;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: 320,
                height: 480,
                child: PageView.builder(
                  controller: controller,
                  reverse: reverse,
                  itemCount: 2,
                  itemBuilder: (context, page) => NovelReaderPageTransition(
                    controller: controller,
                    index: page,
                    effect: NovelReaderPageEffect.staggered,
                    reverse: reverse,
                    paperColor: Colors.white,
                    child: Column(
                      children: [
                        for (final (i, height) in [60.0, 180.0, 90.0].indexed)
                          decorateNovelReaderParagraph(
                            context,
                            _Counter(
                              onLayout: () => layouts++,
                              child: SizedBox(
                                key: ValueKey('part-$page-$i'),
                                height: height,
                                width: 320,
                                child: ColoredBox(
                                  color: page == 0 ? Colors.red : Colors.blue,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        controller.jumpTo(160);
        await tester.pump();
        final beforeLayouts = layouts;
        final oldRects = [
          for (var i = 0; i < 3; i++)
            tester.getRect(find.byKey(ValueKey('part-0-$i'))),
        ];
        final newRects = [
          for (var i = 0; i < 3; i++)
            tester.getRect(find.byKey(ValueKey('part-1-$i'))),
        ];
        final sign = reverse ? -1 : 1;
        expect(oldRects[0].left * sign, lessThan(oldRects[1].left * sign));
        expect(oldRects[1].left * sign, lessThan(oldRects[2].left * sign));
        expect(newRects[0].left * sign, lessThan(newRects[1].left * sign));
        for (var i = 0; i < 3; i++) {
          expect(
            reverse ? newRects[i].right : oldRects[i].right,
            lessThanOrEqualTo(reverse ? oldRects[i].left : newRects[i].left),
          );
        }
        controller.jumpTo(240);
        await tester.pump();
        controller.jumpTo(160);
        await tester.pump();
        expect(layouts, beforeLayouts);
        for (var i = 0; i < 3; i++) {
          expect(
            tester.getRect(find.byKey(ValueKey('part-0-$i'))),
            oldRects[i],
          );
          expect(
            tester.getRect(find.byKey(ValueKey('part-1-$i'))),
            newRects[i],
          );
        }
        controller.jumpToPage(0);
        await tester.pump();
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('part-0-0'))).dx,
          240,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        // A disposed part cannot remain subscribed to an old page clock.
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: PageView(
              controller: controller,
              children: const [SizedBox(), SizedBox()],
            ),
          ),
        );
        controller.jumpTo(10);
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

class _Counter extends SingleChildRenderObjectWidget {
  const _Counter({required this.onLayout, required super.child});
  final VoidCallback onLayout;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _CounterRender(onLayout);
}

class _CounterRender extends RenderProxyBox {
  _CounterRender(this.onLayout);
  final VoidCallback onLayout;
  @override
  void performLayout() {
    onLayout();
    super.performLayout();
  }
}

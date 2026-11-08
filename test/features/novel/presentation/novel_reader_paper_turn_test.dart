import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_page_motion.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_paper_turn.dart';

void main() {
  for (final reverse in [false, true]) {
    testWidgets('paper drag reverses and settles in reverse=$reverse', (
      tester,
    ) async {
      final controller = PageController();
      final clock = NovelReaderPaperClock(controller);
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
                pageSnapping: false,
                physics: NovelReaderPageScrollPhysics(durationScale: () => 1.6),
                itemCount: 2,
                itemBuilder: (context, index) => NovelReaderPageTransition(
                  controller: controller,
                  paperClock: clock,
                  index: index,
                  effect: NovelReaderPageEffect.paper,
                  reverse: reverse,
                  paperColor: Colors.white,
                  child: Text('Retained page $index'),
                ),
              ),
            ),
          ),
        ),
      );
      final direction = reverse ? 1.0 : -1.0;
      final page = find.byType(PageView);
      final gesture = await tester.startGesture(tester.getCenter(page));
      await gesture.moveBy(Offset(110 * direction, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(Offset(-60 * direction, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(controller.page, 0);
      expect(
        tester
            .widgetList<SnapshotWidget>(find.byType(SnapshotWidget))
            .every((s) => !s.controller.allowSnapshotting),
        isTrue,
      );
      await tester.drag(page, Offset(240 * direction, 0));
      await tester.pumpAndSettle();
      expect(controller.page, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      clock.dispose();
      controller.dispose();
    });
  }

  testWidgets(
    'each face captures once per turn and releases its texture at rest',
    (tester) async {
      final controller = PageController();
      final clock = NovelReaderPaperClock(controller);
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
                itemCount: 2,
                itemBuilder: (context, index) => NovelReaderPageTransition(
                  controller: controller,
                  paperClock: clock,
                  index: index,
                  effect: NovelReaderPageEffect.paper,
                  reverse: false,
                  paperColor: Colors.white,
                  child: _Counter(
                    onLayout: () => layouts++,
                    child: Text('Page $index retained texture'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      controller.jumpTo(80);
      await tester.pump();
      final snapshots = tester
          .widgetList<SnapshotWidget>(find.byType(SnapshotWidget))
          .toList();
      expect(snapshots, hasLength(2));
      expect(snapshots.every((s) => s.controller.allowSnapshotting), isTrue);
      expect(
        snapshots.map((s) => (s.painter as dynamic).snapshotCount),
        everyElement(1),
      );
      final initialLayouts = layouts;
      final geometry = clock.geometry(const Size(320, 480));
      expect(clock.geometry(const Size(320, 480)), same(geometry));
      clock.touchY = 0.1;
      expect(clock.geometry(const Size(320, 480)), isNot(same(geometry)));
      // Reversing an unfinished turn must reuse both faces, with no replay or
      // new layout when the user drags back towards the starting page.
      for (final pixels in [120.0, 160.0, 220.0, 160.0, 100.0, 140.0]) {
        controller.jumpTo(pixels);
        await tester.pump();
      }
      expect(layouts, initialLayouts);
      expect(
        snapshots.map((s) => (s.painter as dynamic).snapshotCount),
        everyElement(1),
      );
      controller.jumpToPage(1);
      await tester.pump();
      expect(snapshots.every((s) => !s.controller.allowSnapshotting), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      clock.dispose();
      controller.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expanding paper through margins preserves the measured content box',
    (tester) async {
      final controller = PageController();
      final effect = ValueNotifier(NovelReaderPageEffect.slide);
      var layouts = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 320,
              height: 480,
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
                      paperInsets: const EdgeInsets.fromLTRB(40, 24, 40, 32),
                      child: _Counter(
                        onLayout: () => layouts++,
                        child: const SizedBox.expand(
                          key: Key('paper-content-box'),
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
      final content = find.byKey(const Key('paper-content-box'));
      final box = tester.getRect(content),
          element = tester.element(content),
          count = layouts;
      effect.value = NovelReaderPageEffect.paper;
      await tester.pump();
      expect(tester.getRect(content), box);
      expect(tester.element(content), same(element));
      expect(layouts, count);
      await tester.pumpWidget(const SizedBox.shrink());
      effect.dispose();
      controller.dispose();
    },
  );
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

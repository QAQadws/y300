import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/presentation/widgets/comic_comment_scroll_support.dart';

void main() {
  testWidgets(
    'cached offscreen tail does not fetch; visible tail fetches once per page',
    (tester) async {
      var calls = 0;
      final controller = ScrollController();
      final page = ValueNotifier(2);
      addTearDown(controller.dispose);
      addTearDown(page.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: page,
              builder: (_, value, _) => ListView(
                controller: controller,
                scrollCacheExtent: const ScrollCacheExtent.pixels(5000),
                children: [
                  const SizedBox(height: 1600),
                  ComicCommentLoadMoreTrigger(
                    identity: value,
                    onVisible: () => calls++,
                    child: const SizedBox(height: 100),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(calls, 0);
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      await tester.pump();
      expect(calls, 1);
      await tester.pump();
      expect(calls, 1);
      page.value = 3;
      await tester.pump();
      await tester.pump();
      expect(calls, 2);
    },
  );
  testWidgets(
    'changing content above the visible floor preserves its viewport position',
    (tester) async {
      final controller = _CountingScrollController();
      final headerHeight = ValueNotifier(100.0);
      addTearDown(controller.dispose);
      addTearDown(headerHeight.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: headerHeight,
              builder: (_, height, _) => ListView(
                controller: controller,
                children: [
                  SizedBox(height: height),
                  for (var i = 0; i < 15; i++)
                    ComicCommentScrollAnchor(
                      key: ValueKey(i),
                      owner: 'test-owner',
                      contentRevision: height,
                      child: SizedBox(key: Key('floor-$i'), height: 100),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final before = tester.getTopLeft(find.byKey(const Key('floor-0'))).dy;
      headerHeight.value = 200;
      await tester.pump();
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(const Key('floor-0'))).dy,
        closeTo(before, 0.5),
      );
      expect(controller.offset, closeTo(250, 0.5));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.corrections, 1);
    },
  );
  for (final kind in ['rebuild', 'append', 'owner', 'gesture', 'overscroll']) {
    testWidgets('$kind cannot start an anchor correction', (tester) async {
      final controller = _CountingScrollController();
      final layout = ValueNotifier((
        height: 100.0,
        revision: 0,
        owner: 'a',
        count: 15,
      ));
      addTearDown(controller.dispose);
      addTearDown(layout.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: layout,
              builder: (_, value, _) => ListView(
                controller: controller,
                children: [
                  SizedBox(height: value.height),
                  for (var i = 0; i < value.count; i++)
                    ComicCommentScrollAnchor(
                      key: ValueKey(i),
                      owner: value.owner,
                      contentRevision: value.revision,
                      child: const SizedBox(height: 100),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      if (kind == 'overscroll') {
        controller.position.correctPixels(-20);
      }
      if (kind == 'gesture') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          controller.position.isScrollingNotifier.value = true;
          controller.position.isScrollingNotifier.value = false;
        });
      }
      layout.value = (
        height: kind == 'append' ? 100.0 : 200.0,
        revision: kind == 'rebuild' ? 0 : 1,
        owner: kind == 'owner' ? 'b' : 'a',
        count: kind == 'append' ? 25 : 15,
      );
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(controller.corrections, 0);
      if (kind != 'overscroll') expect(controller.offset, closeTo(150, 0.5));
    });
  }
}

class _CountingScrollController extends ScrollController {
  _CountingScrollController() : super(initialScrollOffset: 150);
  int corrections = 0;
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _CountingScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    onCorrection: () => corrections++,
  );
}

class _CountingScrollPosition extends ScrollPositionWithSingleContext {
  _CountingScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required this.onCorrection,
  }) : super(initialPixels: 150);
  final VoidCallback onCorrection;
  @override
  void jumpTo(double value) {
    onCorrection();
    super.jumpTo(value);
  }
}

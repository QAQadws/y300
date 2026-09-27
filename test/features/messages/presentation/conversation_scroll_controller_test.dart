import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/messages/presentation/conversation_scroll_controller.dart';
import 'package:y300/features/messages/presentation/widgets/conversation_scroll_view.dart';

void main() {
  late ConversationScrollController controller;
  late GlobalKey center;
  const viewportKey = Key('conversation-viewport');

  setUp(() {
    controller = ConversationScrollController();
    center = GlobalKey();
  });
  tearDown(() => controller.dispose());

  Future<void> pumpTimeline(
    WidgetTester tester, {
    required double height,
    required int historyCount,
    required double Function(int index) historyHeight,
    int newerCount = 0,
    double newerHeight = 100,
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            key: viewportKey,
            width: 320,
            height: height,
            child: ConversationScrollView(
              controller: controller,
              center: center,
              slivers: [
                SliverList.builder(
                  itemCount: newerCount,
                  itemBuilder: (_, index) => SizedBox(
                    key: ValueKey('newer-$index'),
                    height: newerHeight,
                  ),
                ),
                SliverList.builder(
                  key: center,
                  itemCount: historyCount,
                  itemBuilder: (_, index) => SizedBox(
                    key: ValueKey('history-$index'),
                    height: historyHeight(index),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('slow dragging escapes latest while lazy row estimates change', (
    tester,
  ) async {
    await pumpTimeline(
      tester,
      height: 200,
      historyCount: 100,
      // The taller row first enters the one-screen cache during the drag.
      historyHeight: (index) => index == 4 ? 200 : 100,
    );
    expect(controller.followingLatest.value, isTrue);
    final gesture = await tester.startGesture(
      tester.getTopLeft(find.byKey(viewportKey)) + const Offset(160, 30),
    );
    late double draggedDistance;
    late bool followingDuringDrag;
    try {
      for (var step = 0; step < 10; step++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 32));
      }
      draggedDistance = controller.offset - controller.position.minScrollExtent;
      followingDuringDrag = controller.followingLatest.value;
    } finally {
      await gesture.up();
    }
    await tester.pumpAndSettle();

    // Inspect the actual drag, before release can introduce a ballistic fling.
    expect(draggedDistance, greaterThan(80));
    expect(followingDuringDrag, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final append in [true, false]) {
    testWidgets(
      '${append ? 'appending' : 'resizing'} newer content during a held short drag updates following',
      (tester) async {
        await pumpTimeline(
          tester,
          height: 400,
          historyCount: 10,
          historyHeight: (_) => 80,
          newerCount: 1,
        );
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(viewportKey)),
        );
        try {
          await gesture.moveBy(
            const Offset(0, 40),
            timeStamp: const Duration(milliseconds: 40),
          );
          await tester.pump(const Duration(milliseconds: 40));
          final heldOffset = controller.offset;
          final heldDistance = heldOffset - controller.position.minScrollExtent;
          expect(heldDistance, greaterThan(0));
          expect(heldDistance, lessThan(80));
          expect(controller.followingLatest.value, isTrue);

          await pumpTimeline(
            tester,
            height: 400,
            historyCount: 10,
            historyHeight: (_) => 80,
            newerCount: append ? 3 : 1,
            newerHeight: append ? 100 : 300,
          );
          expect(controller.offset, closeTo(heldOffset, 0.001));
          expect(
            controller.offset - controller.position.minScrollExtent,
            greaterThan(80),
          );
          expect(controller.followingLatest.value, isFalse);

          // A stationary release must not rely on another pixel update to
          // notice that new content has moved the latest edge away.
          await gesture.moveBy(
            Offset.zero,
            timeStamp: const Duration(milliseconds: 1000),
          );
        } finally {
          await gesture.up(timeStamp: const Duration(milliseconds: 1020));
        }
        await tester.pumpAndSettle();
        expect(controller.followingLatest.value, isFalse);
        expect(
          controller.offset - controller.position.minScrollExtent,
          greaterThan(80),
        );
        controller.showLatest();
        await tester.pumpAndSettle();
        expect(controller.followingLatest.value, isTrue);
        expect(
          controller.offset,
          closeTo(controller.position.minScrollExtent, 0.001),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('fitting the full conversation restores following as it grows', (
    tester,
  ) async {
    await pumpTimeline(
      tester,
      height: 200,
      historyCount: 5,
      historyHeight: (_) => 80,
    );
    controller.jumpTo(100);
    await tester.pumpAndSettle();
    expect(controller.followingLatest.value, isFalse);

    await pumpTimeline(
      tester,
      height: 600,
      historyCount: 5,
      historyHeight: (_) => 80,
    );
    final bounds = tester.getRect(find.byKey(viewportKey));
    expect(controller.position.minScrollExtent, closeTo(0, 0.001));
    expect(controller.position.maxScrollExtent, closeTo(0, 0.001));
    expect(controller.offset, closeTo(0, 0.001));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('history-4'))).dy,
      closeTo(bounds.top, 0.001),
    );
    expect(controller.followingLatest.value, isTrue);

    await pumpTimeline(
      tester,
      height: 600,
      historyCount: 5,
      historyHeight: (_) => 80,
      newerCount: 3,
    );
    expect(controller.followingLatest.value, isTrue);
    expect(
      controller.offset,
      closeTo(controller.position.minScrollExtent, 0.001),
    );
    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('newer-2'))).dy,
      closeTo(bounds.bottom, 0.001),
    );
    expect(tester.takeException(), isNull);
  });
}

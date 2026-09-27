import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/messages/presentation/widgets/conversation_scroll_view.dart';

void main() {
  late ScrollController controller;
  late GlobalKey center;
  const viewportKey = Key('conversation-viewport');

  setUp(() {
    controller = ScrollController();
    center = GlobalKey();
  });
  tearDown(() => controller.dispose());

  Widget row(String id, double height) =>
      SizedBox(key: ValueKey(id), height: height);

  Future<void> pumpTimeline(
    WidgetTester tester, {
    required List<Widget> history,
    List<Widget> newer = const [],
    double height = 400,
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
                SliverList.list(children: newer),
                SliverList.list(
                  key: center,
                  children: history.reversed.toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double top(WidgetTester tester, String id) =>
      tester.getTopLeft(find.byKey(ValueKey(id))).dy;

  testWidgets(
    'short history starts at the top without scrollable blank space',
    (tester) async {
      await pumpTimeline(tester, history: [row('old', 60), row('latest', 90)]);
      final bounds = tester.getRect(find.byKey(viewportKey));
      expect(top(tester, 'old'), closeTo(bounds.top, 0.001));
      expect(top(tester, 'latest'), closeTo(bounds.top + 60, 0.001));
      expect(controller.position.minScrollExtent, closeTo(0, 0.001));
      expect(controller.position.maxScrollExtent, closeTo(0, 0.001));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'short newer messages continue below history at the same center',
    (tester) async {
      await pumpTimeline(tester, history: [row('old', 40), row('anchor', 50)]);
      await pumpTimeline(
        tester,
        history: [row('old', 40), row('anchor', 50)],
        newer: [row('new1', 100), row('new2', 120)],
      );
      final bounds = tester.getRect(find.byKey(viewportKey));
      expect(top(tester, 'old'), closeTo(bounds.top, 0.001));
      expect(top(tester, 'anchor'), closeTo(bounds.top + 40, 0.001));
      expect(top(tester, 'new1'), closeTo(bounds.top + 90, 0.001));
      expect(top(tester, 'new2'), closeTo(bounds.top + 190, 0.001));
      expect(controller.position.minScrollExtent, closeTo(0, 0.001));
      expect(controller.position.maxScrollExtent, closeTo(0, 0.001));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'newer content beyond the default cache is measured before paint',
    (tester) async {
      await pumpTimeline(
        tester,
        height: 600,
        history: [row('anchor', 50)],
        newer: [for (var i = 0; i < 8; i++) row('new$i', i == 7 ? 120 : 50)],
      );
      expect(top(tester, 'anchor'), closeTo(0, 0.001));
      expect(top(tester, 'new7'), closeTo(400, 0.001));
      expect(controller.position.minScrollExtent, closeTo(0, 0.001));
      expect(controller.position.maxScrollExtent, closeTo(0, 0.001));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long content retains reverse scrolling and a stable center', (
    tester,
  ) async {
    await pumpTimeline(
      tester,
      history: [for (var i = 0; i < 10; i++) row('old$i', 80)],
    );
    expect(top(tester, 'old9'), closeTo(320, 0.001));
    expect(controller.position.maxScrollExtent, closeTo(400, 0.001));
    controller.jumpTo(160);
    await tester.pumpAndSettle();
    final before = top(tester, 'old7');
    await pumpTimeline(
      tester,
      history: [
        row('older', 100),
        for (var i = 0; i < 10; i++) row('old$i', 80),
      ],
      newer: [row('new', 130)],
    );
    expect(top(tester, 'old7'), closeTo(before, 0.001));
    expect(controller.position.minScrollExtent, closeTo(-130, 0.001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('viewport and row size changes switch between short and long', (
    tester,
  ) async {
    final messageHeight = ValueNotifier<double>(80);
    addTearDown(messageHeight.dispose);
    final message = ValueListenableBuilder<double>(
      valueListenable: messageHeight,
      builder: (_, height, child) => row('message', height),
    );
    await pumpTimeline(tester, history: [message]);
    expect(top(tester, 'message'), closeTo(0, 0.001));
    messageHeight.value = 500;
    await tester.pumpAndSettle();
    expect(controller.position.maxScrollExtent, closeTo(100, 0.001));
    expect(top(tester, 'message'), closeTo(-100, 0.001));
    await pumpTimeline(tester, history: [message], height: 550);
    expect(top(tester, 'message'), closeTo(0, 0.001));
    expect(controller.position.maxScrollExtent, closeTo(0, 0.001));
    await pumpTimeline(tester, history: [message], height: 300);
    expect(top(tester, 'message'), closeTo(-200, 0.001));
    messageHeight.value = 90;
    await tester.pumpAndSettle();
    expect(top(tester, 'message'), closeTo(0, 0.001));
    expect(controller.position.maxScrollExtent, closeTo(0, 0.001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long conversations keep their rows lazy', (tester) async {
    final built = <int>{};
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: 400,
            width: 320,
            child: ConversationScrollView(
              controller: controller,
              center: center,
              slivers: [
                SliverList.builder(
                  key: center,
                  itemCount: 1000,
                  itemBuilder: (_, index) {
                    built.add(index);
                    return row('$index', 80);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(built.length, lessThan(30));
    expect(controller.position.maxScrollExtent, greaterThan(10000));
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero-height viewport remains valid and recovers', (
    tester,
  ) async {
    await pumpTimeline(tester, height: 0, history: [row('message', 80)]);
    expect(tester.takeException(), isNull);
    await pumpTimeline(tester, history: [row('message', 80)]);
    expect(top(tester, 'message'), closeTo(0, 0.001));
    expect(tester.takeException(), isNull);
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/messages/presentation/widgets/conversation_scroll_view.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  late ScrollController controller;
  late GlobalKey center;
  late Completer<void> refresh;
  late int refreshCount;
  const viewportKey = Key('conversation-refresh-viewport');

  setUp(() {
    controller = ScrollController();
    center = GlobalKey();
    refreshCount = 0;
  });
  tearDown(() {
    if (!refresh.isCompleted) refresh.complete();
    controller.dispose();
  });

  Future<void> pumpConversation(
    WidgetTester tester, {
    int historyCount = 1,
    int newerCount = 0,
    Widget? nested,
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    // Create the future inside the widget test's FakeAsync zone so that pump
    // also drains its completion and the indicator's dismissal animation.
    refresh = Completer<void>();
    await tester.pumpWidget(
      LocalizedTestApp(
        theme: ThemeData(platform: platform),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              key: viewportKey,
              height: 400,
              width: 320,
              child: RefreshIndicator(
                onRefresh: () {
                  refreshCount++;
                  return refresh.future;
                },
                child: ConversationScrollView(
                  controller: controller,
                  center: center,
                  slivers: [
                    SliverList.builder(
                      itemCount: newerCount,
                      itemBuilder: (_, index) =>
                          SizedBox(key: ValueKey('newer-$index'), height: 80),
                    ),
                    SliverList.builder(
                      key: center,
                      itemCount: historyCount,
                      itemBuilder: (_, index) => SizedBox(
                        key: ValueKey('history-$index'),
                        height: nested == null ? 80 : 180,
                        child: nested,
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
    await tester.pumpAndSettle();
  }

  Future<void> pull(WidgetTester tester, Offset delta) async {
    await tester.dragFrom(
      tester.getTopLeft(find.byKey(viewportKey)) + const Offset(160, 100),
      delta,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final count in [0, 1]) {
      testWidgets(
        '${platform.name} ${count == 0 ? 'empty' : 'short'} conversation refreshes by pulling down',
        (tester) async {
          await pumpConversation(
            tester,
            historyCount: count,
            platform: platform,
          );
          final before = count == 0
              ? null
              : tester.getRect(find.byKey(const ValueKey('history-0')));
          expect(controller.position.minScrollExtent, 0);
          expect(controller.position.maxScrollExtent, 0);
          await pull(tester, const Offset(0, 220));
          expect(refreshCount, 1);
          final indicator = tester.getRect(
            find.byType(RefreshProgressIndicator),
          );
          final bounds = tester.getRect(find.byKey(viewportKey));
          expect(indicator.center.dy, lessThan(bounds.center.dy));
          if (before != null) {
            expect(
              tester.getRect(find.byKey(const ValueKey('history-0'))),
              before,
            );
          }
          await pull(tester, const Offset(0, 220));
          expect(refreshCount, 1);
          refresh.complete();
          await tester.pumpAndSettle();
          expect(find.byType(RefreshProgressIndicator), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('short conversation does not refresh when pulling up', (
    tester,
  ) async {
    await pumpConversation(tester);
    await pull(tester, const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(refreshCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long centered timeline refreshes only at the physical top', (
    tester,
  ) async {
    await pumpConversation(tester, historyCount: 20, newerCount: 2);
    controller.jumpTo(controller.position.minScrollExtent);
    await tester.pumpAndSettle();
    await pull(tester, const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(refreshCount, 0);

    controller.jumpTo(controller.position.maxScrollExtent - 300);
    await tester.pumpAndSettle();
    await pull(tester, const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(refreshCount, 0);

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    final oldest = find.byKey(const ValueKey('history-19'));
    final before = tester.getRect(oldest);
    await pull(tester, const Offset(0, 220));
    expect(refreshCount, 1);
    expect(tester.getRect(oldest), before);
    expect(controller.offset, controller.position.maxScrollExtent);
    refresh.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('programmatic timeline movement does not refresh', (
    tester,
  ) async {
    await pumpConversation(tester, historyCount: 20, newerCount: 2);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(refreshCount, 0);

    final toLatest = controller.animateTo(
      controller.position.minScrollExtent,
      duration: const Duration(milliseconds: 100),
      curve: Curves.linear,
    );
    await tester.pumpAndSettle();
    await toLatest;
    final toOldest = controller.animateTo(
      controller.position.maxScrollExtent,
      duration: const Duration(milliseconds: 100),
      curve: Curves.linear,
    );
    await tester.pumpAndSettle();
    await toOldest;
    expect(refreshCount, 0);
    expect(find.byType(RefreshProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final axis in Axis.values) {
    testWidgets(
      'nested ${axis.name} HTML scrolling cannot refresh the timeline',
      (tester) async {
        const nestedKey = Key('nested-html-scroll');
        await pumpConversation(
          tester,
          nested: SingleChildScrollView(
            key: nestedKey,
            scrollDirection: axis,
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            child: SizedBox(
              width: axis == Axis.horizontal ? 800 : 200,
              height: axis == Axis.vertical ? 800 : 120,
            ),
          ),
        );
        await tester.drag(
          find.byKey(nestedKey),
          axis == Axis.vertical ? const Offset(0, 220) : const Offset(220, 0),
        );
        await tester.pumpAndSettle();
        expect(refreshCount, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

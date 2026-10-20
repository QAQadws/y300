import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/profile/presentation/widgets/feed_pagination_scroll_controller.dart';

void main() {
  testWidgets('page changes animate after layout instead of jumping', (
    tester,
  ) async {
    final scroll = await _pumpList(tester);
    var page = 1;
    final navigation = scroll.changePage(
      load: () async => page = 2,
      currentPage: () => page,
      isCurrent: () => true,
      animate: () => true,
    );
    await tester.pump();
    await tester.pump();
    expect(scroll.offset, 600);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 55));
    expect(scroll.offset, allOf(greaterThan(0), lessThan(600)));
    await tester.pumpAndSettle();
    await navigation;
    expect(scroll.offset, 0);
  });

  testWidgets('unchanged pages preserve their position', (tester) async {
    final scroll = await _pumpList(tester);
    final navigation = scroll.changePage(
      load: () async {},
      currentPage: () => 1,
      isCurrent: () => true,
      animate: () => true,
    );
    await tester.pumpAndSettle();
    await navigation;
    expect(scroll.offset, 600);
  });

  testWidgets('dragging while a page loads retires its queued return', (
    tester,
  ) async {
    final scroll = await _pumpList(tester);
    var page = 1;
    final loaded = Completer<void>();
    final navigation = scroll.changePage(
      load: () async {
        await loaded.future;
        page = 2;
      },
      currentPage: () => page,
      isCurrent: () => true,
      animate: () => true,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pumpAndSettle();
    final userOffset = scroll.offset;
    expect(userOffset, greaterThan(600));
    loaded.complete();
    await tester.pumpAndSettle();
    await navigation;
    expect(scroll.offset, closeTo(userOffset, 0.5));
  });

  testWidgets('user drags interrupt the animation and remain in control', (
    tester,
  ) async {
    final scroll = await _pumpList(tester);
    var page = 1;
    final navigation = scroll.changePage(
      load: () async => page = 2,
      currentPage: () => page,
      isCurrent: () => true,
      animate: () => true,
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 55));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump(const Duration(milliseconds: 16));
    final firstDragOffset = scroll.offset;
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump(const Duration(milliseconds: 16));
    expect(scroll.offset, greaterThan(firstDragOffset));
    final userOffset = scroll.offset;
    await tester.pump(const Duration(milliseconds: 300));
    expect(scroll.offset, closeTo(userOffset, 0.5));
    await gesture.up();
    await tester.pumpAndSettle();
    await navigation;
    expect(scroll.offset, greaterThan(0));
  });

  testWidgets('inactive owners cannot start a late return', (tester) async {
    final scroll = await _pumpList(tester);
    var page = 1;
    var active = true;
    final loaded = Completer<void>();
    final navigation = scroll.changePage(
      load: () async {
        await loaded.future;
        page = 2;
      },
      currentPage: () => page,
      isCurrent: () => active,
      animate: () => true,
    );
    active = false;
    loaded.complete();
    await tester.pumpAndSettle();
    await navigation;
    expect(scroll.offset, 600);
  });

  testWidgets('reduced motion returns directly after the layout frame', (
    tester,
  ) async {
    final scroll = await _pumpList(tester);
    var page = 1;
    final navigation = scroll.changePage(
      load: () async => page = 2,
      currentPage: () => page,
      isCurrent: () => true,
      animate: () => false,
    );
    await tester.pump();
    await tester.pump();
    await navigation;
    expect(scroll.offset, 0);
    await tester.pumpAndSettle();
  });
}

Future<FeedPaginationScrollController> _pumpList(WidgetTester tester) async {
  final scroll = FeedPaginationScrollController();
  addTearDown(scroll.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NotificationListener<ScrollNotification>(
          onNotification: scroll.handleScrollNotification,
          child: ListView.builder(
            controller: scroll,
            itemCount: 80,
            itemExtent: 50,
            itemBuilder: (_, _) => const SizedBox(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  scroll.jumpTo(600);
  await tester.pumpAndSettle();
  return scroll;
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/shared/widgets/shelf/fixed_slot_pager_header.dart';

void main() {
  testWidgets('FixedSlotPagerHeader uses fixed quarter width slots', (tester) async {
    final pageController = PageController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: FixedSlotPagerHeader(
              pageController: pageController,
              tabs: const [
                FixedSlotHeaderTab(id: 'a', label: 'A'),
                FixedSlotHeaderTab(id: 'b', label: 'B'),
              ],
              selectedIndex: 0,
              onTap: (_) {},
              indicatorKey: const Key('fixed-header-indicator'),
              tabKeyBuilder: (id) => ValueKey<String>('fixed-header-tab-$id'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final aSize = tester.getSize(find.byKey(const ValueKey<String>('fixed-header-tab-a')));
    final bSize = tester.getSize(find.byKey(const ValueKey<String>('fixed-header-tab-b')));
    expect(aSize.width, closeTo(100, 0.5));
    expect(bSize.width, closeTo(100, 0.5));
  });

  testWidgets('FixedSlotPagerHeader keeps over-four tabs scrollable', (tester) async {
    final pageController = PageController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FixedSlotPagerHeader(
            pageController: pageController,
            tabs: const [
              FixedSlotHeaderTab(id: 'a', label: 'A'),
              FixedSlotHeaderTab(id: 'b', label: 'B'),
              FixedSlotHeaderTab(id: 'c', label: 'C'),
              FixedSlotHeaderTab(id: 'd', label: 'D'),
              FixedSlotHeaderTab(id: 'e', label: 'E'),
            ],
            selectedIndex: 0,
            onTap: (_) {},
            indicatorKey: const Key('fixed-header-indicator'),
            tabKeyBuilder: (id) => ValueKey<String>('fixed-header-tab-$id'),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final headerRect = tester.getRect(find.byType(FixedSlotPagerHeader));
    final tabEFinder = find.byKey(const ValueKey<String>('fixed-header-tab-e'));
    final before = tester.getRect(tabEFinder);
    expect(before.left, greaterThanOrEqualTo(headerRect.right));

    await tester.drag(find.byType(FixedSlotPagerHeader), const Offset(-300, 0));
    await tester.pumpAndSettle();

    final after = tester.getRect(tabEFinder);
    expect(after.right, lessThanOrEqualTo(headerRect.right));
  });
}

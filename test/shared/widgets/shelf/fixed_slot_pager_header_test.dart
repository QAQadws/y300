import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/shared/widgets/shelf/fixed_slot_pager_header.dart';
import 'package:y300/shared/widgets/shelf/shelf_theme_palette.dart';

void main() {
  testWidgets('FixedSlotPagerHeader paints an opaque surface background', (tester) async {
    final pageController = PageController();
    addTearDown(pageController.dispose);
    const surface = Color(0xFF102030);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue).copyWith(surface: surface)),
        home: Scaffold(
          body: FixedSlotPagerHeader(
            pageController: pageController,
            tabs: const [
              FixedSlotHeaderTab(id: 'a', label: 'A'),
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

    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(FixedSlotPagerHeader),
        matching: find.byType(Material),
      ),
    );
    expect(material.color, surface);
  });

  testWidgets('FixedSlotPagerHeader uses shelf palette from app theme', (tester) async {
    final pageController = PageController();
    addTearDown(pageController.dispose);
    final theme = AppTheme.dark();
    final palette = const ShelfThemePaletteResolver().resolve(theme);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: FixedSlotPagerHeader(
            pageController: pageController,
            tabs: const [
              FixedSlotHeaderTab(id: 'a', label: 'A'),
              FixedSlotHeaderTab(id: 'b', label: 'B'),
            ],
            selectedIndex: 1,
            onTap: (_) {},
            indicatorKey: const Key('fixed-header-indicator'),
            tabKeyBuilder: (id) => ValueKey<String>('fixed-header-tab-$id'),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(FixedSlotPagerHeader),
        matching: find.byType(Material),
      ),
    );
    final indicator = tester.widget<Container>(
      find.descendant(
        of: find.byKey(const Key('fixed-header-indicator')),
        matching: find.byType(Container),
      ),
    );
    final decoration = indicator.decoration as BoxDecoration;

    expect(material.color, palette.categoryBarBackground);
    expect(decoration.color, palette.categorySelectedBackground);
  });

  testWidgets('FixedSlotPagerHeader uses fixed quarter width slots', (tester) async {
    final pageController = PageController();
    addTearDown(pageController.dispose);

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
    addTearDown(pageController.dispose);

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

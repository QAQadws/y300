import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/presentation/services/thread_detail_quick_scroll_coordinator.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_quick_scroll_button.dart';

void main() {
  testWidgets(
    'animates between the current scroll extents and reverses arrow',
    (tester) async {
      final scrollController = ScrollController();
      final coordinator = ThreadDetailQuickScrollCoordinator(
        scrollController: scrollController,
      );

      await tester.pumpWidget(
        _testShell(
          scrollController: scrollController,
          coordinator: coordinator,
          contentHeight: 2400,
        ),
      );
      coordinator.updateMetrics(scrollController.position);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('thread-detail-quick-scroll-button')),
        findsOneWidget,
      );
      expect(find.byTooltip('滚动到底部'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.keyboard_arrow_down)).color,
        Colors.black.withValues(alpha: 0.72),
      );
      expect(_arrow(tester).turns, 0);

      await tester.tap(
        find.byKey(const Key('thread-detail-quick-scroll-button')),
      );
      await tester.pumpAndSettle();

      expect(
        scrollController.position.pixels,
        closeTo(scrollController.position.maxScrollExtent, 0.01),
      );
      expect(find.byTooltip('滚动到顶部'), findsOneWidget);
      expect(_arrow(tester).turns, 0.5);

      await tester.tap(
        find.byKey(const Key('thread-detail-quick-scroll-button')),
      );
      await tester.pumpAndSettle();

      expect(
        scrollController.position.pixels,
        closeTo(scrollController.position.minScrollExtent, 0.01),
      );
      expect(find.byTooltip('滚动到底部'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      coordinator.dispose();
      scrollController.dispose();
    },
  );

  testWidgets('hides when the content has no scroll range', (tester) async {
    final scrollController = ScrollController();
    final coordinator = ThreadDetailQuickScrollCoordinator(
      scrollController: scrollController,
    );

    await tester.pumpWidget(
      _testShell(
        scrollController: scrollController,
        coordinator: coordinator,
        contentHeight: 120,
      ),
    );
    coordinator.updateMetrics(scrollController.position);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('thread-detail-quick-scroll-button')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    coordinator.dispose();
    scrollController.dispose();
  });

  testWidgets('jumps immediately when animations are disabled', (tester) async {
    final scrollController = ScrollController();
    final coordinator = ThreadDetailQuickScrollCoordinator(
      scrollController: scrollController,
    );

    await tester.pumpWidget(
      _testShell(
        scrollController: scrollController,
        coordinator: coordinator,
        contentHeight: 2400,
        disableAnimations: true,
      ),
    );
    coordinator.updateMetrics(scrollController.position);
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('thread-detail-quick-scroll-button')),
    );
    await tester.pump();

    expect(
      scrollController.position.pixels,
      closeTo(scrollController.position.maxScrollExtent, 0.01),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    coordinator.dispose();
    scrollController.dispose();
  });
}

Widget _testShell({
  required ScrollController scrollController,
  required ThreadDetailQuickScrollCoordinator coordinator,
  required double contentHeight,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: SingleChildScrollView(
          controller: scrollController,
          child: SizedBox(height: contentHeight),
        ),
        floatingActionButton: ThreadDetailQuickScrollButton(
          coordinator: coordinator,
          hasContent: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
      ),
    ),
  );
}

AnimatedRotation _arrow(WidgetTester tester) {
  return tester.widget<AnimatedRotation>(
    find.byKey(const Key('thread-detail-quick-scroll-arrow')),
  );
}

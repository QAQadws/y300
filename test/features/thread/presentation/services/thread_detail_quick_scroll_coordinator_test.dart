import 'package:flutter/material.dart';
import '../../../../test_support/localized_test_app.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/presentation/services/thread_detail_quick_scroll_coordinator.dart';

void main() {
  group('ThreadDetailQuickScrollCoordinator', () {
    test('tracks user direction and keeps idle direction stable', () {
      final scrollController = ScrollController();
      final coordinator = ThreadDetailQuickScrollCoordinator(
        scrollController: scrollController,
      );
      addTearDown(() {
        coordinator.dispose();
        scrollController.dispose();
      });

      expect(coordinator.target, ThreadDetailQuickScrollTarget.bottom);

      coordinator.updateMetrics(_metrics(pixels: 400));
      coordinator.updateUserDirection(ScrollDirection.forward);
      expect(coordinator.target, ThreadDetailQuickScrollTarget.top);

      coordinator.updateUserDirection(ScrollDirection.idle);
      expect(coordinator.target, ThreadDetailQuickScrollTarget.top);

      coordinator.updateUserDirection(ScrollDirection.reverse);
      expect(coordinator.target, ThreadDetailQuickScrollTarget.bottom);
    });

    test('uses endpoint state and supports a negative minimum extent', () {
      final scrollController = ScrollController();
      final coordinator = ThreadDetailQuickScrollCoordinator(
        scrollController: scrollController,
      );
      addTearDown(() {
        coordinator.dispose();
        scrollController.dispose();
      });

      coordinator.updateMetrics(_metrics(min: -600, max: 900, pixels: -600));
      expect(coordinator.isScrollable, isTrue);
      expect(coordinator.target, ThreadDetailQuickScrollTarget.bottom);

      coordinator.updateMetrics(_metrics(min: -600, max: 900, pixels: 900));
      expect(coordinator.target, ThreadDetailQuickScrollTarget.top);

      coordinator.updateMetrics(_metrics(min: -600, max: -599.5, pixels: -600));
      expect(coordinator.isScrollable, isFalse);
    });

    testWidgets('navigates between both extents of a centered scroll view', (
      tester,
    ) async {
      final scrollController = ScrollController();
      final coordinator = ThreadDetailQuickScrollCoordinator(
        scrollController: scrollController,
      );
      final centerKey = GlobalKey();

      await tester.pumpWidget(
        LocalizedTestApp(
          home: Scaffold(
            body: CustomScrollView(
              controller: scrollController,
              center: centerKey,
              slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 1200)),
                SliverToBoxAdapter(
                  key: centerKey,
                  child: const SizedBox(height: 1200),
                ),
              ],
            ),
          ),
        ),
      );
      coordinator.updateMetrics(scrollController.position);
      expect(scrollController.position.minScrollExtent, lessThan(0));
      expect(scrollController.position.maxScrollExtent, greaterThan(0));

      coordinator.updateUserDirection(ScrollDirection.forward);
      final topNavigation = coordinator.navigate(animate: false);
      await tester.pump();
      await topNavigation;
      expect(
        scrollController.position.pixels,
        closeTo(scrollController.position.minScrollExtent, 0.01),
      );

      final bottomNavigation = coordinator.navigate(animate: false);
      await tester.pump();
      await bottomNavigation;
      expect(
        scrollController.position.pixels,
        closeTo(scrollController.position.maxScrollExtent, 0.01),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      coordinator.dispose();
      scrollController.dispose();
    });

    testWidgets('does not force the endpoint after a user interruption', (
      tester,
    ) async {
      final scrollController = ScrollController();
      final coordinator = ThreadDetailQuickScrollCoordinator(
        scrollController: scrollController,
      );

      await tester.pumpWidget(
        LocalizedTestApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scrollController,
              child: const SizedBox(height: 2400),
            ),
          ),
        ),
      );
      coordinator.updateMetrics(scrollController.position);

      final navigation = coordinator.navigate(animate: true);
      await tester.pump(const Duration(milliseconds: 80));
      coordinator.updateUserDirection(ScrollDirection.forward);
      scrollController.jumpTo(300);
      await tester.pumpAndSettle();
      await navigation;

      expect(scrollController.position.pixels, closeTo(300, 0.01));
      expect(coordinator.target, ThreadDetailQuickScrollTarget.top);

      await tester.pumpWidget(const SizedBox.shrink());
      coordinator.dispose();
      scrollController.dispose();
    });
  });
}

FixedScrollMetrics _metrics({
  double min = 0,
  double max = 1000,
  required double pixels,
}) {
  return FixedScrollMetrics(
    minScrollExtent: min,
    maxScrollExtent: max,
    pixels: pixels,
    viewportDimension: 600,
    axisDirection: AxisDirection.down,
    devicePixelRatio: 1,
  );
}

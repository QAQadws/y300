import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reading_body_geometry.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reading_body_sliver.dart';

void main() {
  group('chapter body geometry', () {
    test('progress excludes title and controls outside the body', () {
      const geometry = NovelReadingBodyGeometry(
        bodyTop: 100,
        bodyHeight: 1000,
        viewportTop: 350,
        effectiveViewportHeight: 500,
        visibleBodyExtent: 500,
        finalBoundaryKnown: true,
      );
      expect(geometry.bodyRange, 500);
      expect(geometry.progressPercent, 0.5);
      expect(geometry.atBodyEnd, isFalse);
      expect(geometry.wholeBodyVisible, isFalse);
    });

    test('known short chapter has valid zero independent of completion', () {
      const geometry = NovelReadingBodyGeometry(
        bodyTop: 100,
        bodyHeight: 200,
        viewportTop: 100,
        effectiveViewportHeight: 500,
        visibleBodyExtent: 150,
        finalBoundaryKnown: true,
      );
      expect(geometry.progressPercent, 0);
      expect(geometry.atBodyEnd, isFalse);
      expect(geometry.wholeBodyVisible, isFalse);
    });

    test('known geometry estimates position without proving completion', () {
      const geometry = NovelReadingBodyGeometry(
        bodyTop: 100,
        bodyHeight: 200,
        viewportTop: 100,
        effectiveViewportHeight: 500,
        visibleBodyExtent: 200,
        finalBoundaryKnown: false,
      );
      expect(geometry.progressPercent, 0);
      expect(geometry.atBodyEnd, isFalse);
    });

    test('invalid and nonfinite dimensions are not readable geometry', () {
      for (final height in <double>[double.nan, double.infinity, -1]) {
        final geometry = NovelReadingBodyGeometry(
          bodyTop: 100,
          bodyHeight: height,
          viewportTop: 100,
          effectiveViewportHeight: 500,
          visibleBodyExtent: 200,
          finalBoundaryKnown: true,
        );
        expect(geometry.progressPercent, isNull);
        expect(geometry.atBodyEnd, isFalse);
      }
    });

    test('layout identity excludes scrolling but includes body dimensions', () {
      const first = NovelReadingBodyGeometry(
        bodyTop: 100,
        bodyHeight: 1000,
        viewportTop: 100,
        effectiveViewportHeight: 500,
        visibleBodyExtent: 500,
        finalBoundaryKnown: true,
      );
      const moved = NovelReadingBodyGeometry(
        bodyTop: 100,
        bodyHeight: 1000,
        viewportTop: 600,
        effectiveViewportHeight: 500,
        visibleBodyExtent: 500,
        finalBoundaryKnown: true,
      );
      expect(first.layoutIdentity, moved.layoutIdentity);
      expect(first.progressPercent, 0);
      expect(moved.progressPercent, 1);
      expect(moved.atBodyEnd, isTrue);
      expect(moved.wholeBodyVisible, isFalse);
    });
  });

  testWidgets(
    'measures body independently from title and next chapter control',
    (tester) async {
      final controller = ScrollController();
      final reports = <NovelReadingBodyGeometry>[];
      await tester.pumpWidget(
        _viewport(
          controller: controller,
          reports: reports,
          sliver: const SliverToBoxAdapter(child: SizedBox(height: 800)),
          titleHeight: 100,
          transitionHeight: 600,
        ),
      );
      expect(reports.last.bodyTop, 100);
      expect(reports.last.bodyHeight, 800);
      expect(reports.last.visibleBodyExtent, 300);
      expect(reports.last.finalBoundaryKnown, isTrue);
      expect(reports.last.progressPercent, 0);
      expect(reports.last.atBodyEnd, isFalse);
      controller.jumpTo(350);
      await tester.pump();
      expect(reports.last.viewportTop, 350);
      expect(reports.last.progressPercent, 0.625);
      controller.jumpTo(500);
      await tester.pump();
      expect(reports.last.progressPercent, 1);
      expect(reports.last.atBodyEnd, isTrue);
      controller.jumpTo(1000);
      await tester.pump();
      expect(reports.last.visibleBodyExtent, 0);
      expect(reports.last.atBodyEnd, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets(
    'title and bottom overlay prevent false short chapter completion',
    (tester) async {
      final controller = ScrollController();
      final reports = <NovelReadingBodyGeometry>[];
      await tester.pumpWidget(
        _viewport(
          controller: controller,
          reports: reports,
          effectiveViewportHeight: 330,
          sliver: const SliverToBoxAdapter(child: SizedBox(height: 300)),
          titleHeight: 180,
          transitionHeight: 200,
        ),
      );
      expect(reports.last.bodyHeight, 300);
      expect(reports.last.visibleBodyExtent, 150);
      expect(reports.last.progressPercent, 0);
      expect(reports.last.wholeBodyVisible, isFalse);
      controller.jumpTo(150);
      await tester.pump();
      expect(reports.last.visibleBodyExtent, 300);
      expect(reports.last.wholeBodyVisible, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets(
    'lazy estimated extent is unknown until the final child is laid out',
    (tester) async {
      final controller = ScrollController();
      final reports = <NovelReadingBodyGeometry>[];
      final built = <int>{};
      await tester.pumpWidget(
        _viewport(
          controller: controller,
          reports: reports,
          sliver: SliverList.builder(
            itemCount: 20,
            itemBuilder: (_, index) {
              built.add(index);
              return SizedBox(height: index == 19 ? 120 : 60);
            },
          ),
        ),
      );
      expect(built.length, lessThan(10));
      expect(reports.last.finalBoundaryKnown, isFalse);
      expect(reports.last.progressPercent, 0);
      controller.jumpTo(300);
      await tester.pump();
      expect(
        reports.last.progressPercent,
        closeTo(300 / (reports.last.bodyHeight - 400), 0.0001),
      );
      expect(reports.last.finalBoundaryKnown, isFalse);
      expect(reports.last.atBodyEnd, isFalse);
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(built, contains(19));
      expect(reports.last.finalBoundaryKnown, isTrue);
      expect(reports.last.bodyHeight, 1260);
      expect(reports.last.atBodyEnd, isFalse);
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      expect(reports.last.atBodyEnd, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('unknown builder count stays conservative and is not scanned', (
    tester,
  ) async {
    final controller = ScrollController();
    final reports = <NovelReadingBodyGeometry>[];
    final built = <int>{};
    await tester.pumpWidget(
      _viewport(
        controller: controller,
        reports: reports,
        sliver: SliverList.builder(
          itemBuilder: (_, index) {
            built.add(index);
            return index < 20 ? const SizedBox(height: 60) : null;
          },
        ),
      ),
    );
    expect(built.length, lessThan(10));
    expect(reports.last.finalBoundaryKnown, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('padding and proxy wrappers preserve final-child proof', (
    tester,
  ) async {
    final controller = ScrollController();
    final reports = <NovelReadingBodyGeometry>[];
    await tester.pumpWidget(
      _viewport(
        controller: controller,
        reports: reports,
        sliver: const SliverOpacity(
          opacity: 1,
          sliver: SliverPadding(
            padding: EdgeInsets.symmetric(vertical: 10),
            sliver: SliverToBoxAdapter(child: SizedBox(height: 200)),
          ),
        ),
      ),
    );
    expect(reports.last.bodyHeight, 220);
    expect(reports.last.finalBoundaryKnown, isTrue);
    expect(reports.last.wholeBodyVisible, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('rebound layout rejects the old frame callback', (tester) async {
    await tester.pumpWidget(
      const Directionality(textDirection: TextDirection.ltr, child: SizedBox()),
    );
    final context = tester.element(find.byType(SizedBox));
    final oldReports = <NovelReadingBodyGeometry>[];
    final nextReports = <NovelReadingBodyGeometry>[];
    final widget = NovelReadingBodySliver(
      effectiveViewportHeight: 400,
      onGeometry: oldReports.add,
      layoutIdentity: 'old',
      sliver: const SliverToBoxAdapter(),
    );
    final render = widget.createRenderObject(context) as RenderProxySliver;
    final body = RenderSliverToBoxAdapter(
      child: RenderConstrainedBox(
        additionalConstraints: BoxConstraints.tight(const Size(300, 200)),
      ),
    );
    render.child = body;
    render.attach(PipelineOwner());
    render.layout(_constraints);
    NovelReadingBodySliver(
      effectiveViewportHeight: 400,
      onGeometry: nextReports.add,
      layoutIdentity: 'next',
      sliver: const SliverToBoxAdapter(),
    ).updateRenderObject(context, render);
    render.layout(_constraints);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(oldReports, isEmpty);
    expect(nextReports, hasLength(1));
    render.detach();
    render.dispose();
    body.child?.dispose();
    body.dispose();
  });

  testWidgets('detached render callback cannot publish an old body', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(textDirection: TextDirection.ltr, child: SizedBox()),
    );
    final reports = <NovelReadingBodyGeometry>[];
    final widget = NovelReadingBodySliver(
      effectiveViewportHeight: 400,
      onGeometry: reports.add,
      sliver: const SliverToBoxAdapter(),
    );
    final render =
        widget.createRenderObject(tester.element(find.byType(SizedBox)))
            as RenderProxySliver;
    final body = RenderSliverToBoxAdapter(
      child: RenderConstrainedBox(
        additionalConstraints: BoxConstraints.tight(const Size(300, 200)),
      ),
    );
    render.child = body;
    render.attach(PipelineOwner());
    render.layout(_constraints);
    render.detach();
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(reports, isEmpty);
    render.dispose();
    body.child?.dispose();
    body.dispose();
  });
}

Widget _viewport({
  required ScrollController controller,
  required List<NovelReadingBodyGeometry> reports,
  required Widget sliver,
  double effectiveViewportHeight = 400,
  double titleHeight = 0,
  double transitionHeight = 0,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 300,
      height: 400,
      child: CustomScrollView(
        controller: controller,
        scrollCacheExtent: const ScrollCacheExtent.pixels(0),
        slivers: [
          if (titleHeight > 0)
            SliverToBoxAdapter(child: SizedBox(height: titleHeight)),
          NovelReadingBodySliver(
            effectiveViewportHeight: effectiveViewportHeight,
            onGeometry: reports.add,
            sliver: sliver,
          ),
          if (transitionHeight > 0)
            SliverToBoxAdapter(child: SizedBox(height: transitionHeight)),
        ],
      ),
    ),
  ),
);

const _constraints = SliverConstraints(
  axisDirection: AxisDirection.down,
  growthDirection: GrowthDirection.forward,
  userScrollDirection: ScrollDirection.idle,
  scrollOffset: 0,
  precedingScrollExtent: 0,
  overlap: 0,
  remainingPaintExtent: 400,
  crossAxisExtent: 300,
  crossAxisDirection: AxisDirection.right,
  viewportMainAxisExtent: 400,
  remainingCacheExtent: 400,
  cacheOrigin: 0,
);

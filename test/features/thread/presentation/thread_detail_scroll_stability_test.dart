import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_callbacks.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_widgets.dart';

void main() {
  testWidgets('compensates one above-viewport image height change', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester, initialOffset: 300);

    harness.stabilizer.handleLayoutShift(
      _shift(oldTop: harness.viewportTop - 510, oldHeight: 500, newHeight: 300),
    );
    expect(harness.stabilizer.debugPendingDelta, -200);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    expect(harness.stabilizer.debugPendingDelta, 0);
    expect(harness.controller.offset, closeTo(100, 0.1));
  });

  testWidgets('merges multiple above-viewport image shifts in one frame', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester, initialOffset: 400);

    harness.stabilizer
      ..handleLayoutShift(
        _shift(
          oldTop: harness.viewportTop - 510,
          oldHeight: 500,
          newHeight: 300,
        ),
      )
      ..handleLayoutShift(
        _shift(
          oldTop: harness.viewportTop - 260,
          oldHeight: 240,
          newHeight: 300,
        ),
      );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    expect(harness.controller.offset, closeTo(260, 0.1));
  });

  testWidgets('does not compensate images intersecting the viewport', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester, initialOffset: 300);

    harness.stabilizer.handleLayoutShift(
      _shift(oldTop: harness.viewportTop + 80, oldHeight: 500, newHeight: 300),
    );
    await tester.pump();
    await tester.pump();

    expect(harness.controller.offset, closeTo(300, 0.1));
  });

  testWidgets('clamps shrink compensation at the top of the scroll extent', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester, initialOffset: 30);

    harness.stabilizer.handleLayoutShift(
      _shift(oldTop: harness.viewportTop - 510, oldHeight: 500, newHeight: 300),
    );
    await tester.pump();
    await tester.pump();

    expect(harness.controller.offset, 0);
  });

  testWidgets('reports queued and applied stabilizer events', (tester) async {
    final events = <ThreadDetailScrollStabilizerEvent>[];
    final harness = await _pumpHarness(
      tester,
      initialOffset: 300,
      onEvent: events.add,
    );

    harness.stabilizer.handleLayoutShift(
      _shift(oldTop: harness.viewportTop - 510, oldHeight: 500, newHeight: 300),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      events.map((event) => event.type),
      contains(ThreadDetailScrollStabilizerEventType.queued),
    );
    expect(
      events.map((event) => event.type),
      contains(ThreadDetailScrollStabilizerEventType.applied),
    );
    final applied = events.lastWhere(
      (event) => event.type == ThreadDetailScrollStabilizerEventType.applied,
    );
    expect(applied.reason, 'jump-to-compensate-above-viewport');
    expect(applied.pendingDelta, -200);
    expect(applied.targetPixels, closeTo(100, 0.1));
  });
}

Future<_Harness> _pumpHarness(
  WidgetTester tester, {
  required double initialOffset,
  ValueChanged<ThreadDetailScrollStabilizerEvent>? onEvent,
}) async {
  final controller = ScrollController(initialScrollOffset: initialOffset);
  final viewportKey = GlobalKey(debugLabel: 'test-thread-detail-viewport');
  final stabilizer = ThreadDetailScrollStabilizer(
    scrollController: controller,
    viewportKey: viewportKey,
    onEvent: onEvent,
  );
  addTearDown(() {
    stabilizer.dispose();
    controller.dispose();
  });

  await tester.pumpWidget(
    LocalizedTestApp(
      home: Scaffold(
        body: SizedBox(
          key: viewportKey,
          width: 300,
          height: 400,
          child: SingleChildScrollView(
            controller: controller,
            child: const SizedBox(height: 1400),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return _Harness(
    controller: controller,
    stabilizer: stabilizer,
    viewportTop: tester.getTopLeft(find.byKey(viewportKey)).dy,
  );
}

ForumHtmlImageLayoutShift _shift({
  required double oldTop,
  required double oldHeight,
  required double newHeight,
}) {
  return ForumHtmlImageLayoutShift(
    sourceUrl: 'https://example.com/image.jpg',
    cacheKey: 'thread-inline-image',
    oldGlobalRect: Rect.fromLTWH(0, oldTop, 300, oldHeight),
    oldSize: Size(300, oldHeight),
    newSize: Size(300, newHeight),
    oldAspectRatio: 300 / oldHeight,
    newAspectRatio: 300 / newHeight,
  );
}

class _Harness {
  const _Harness({
    required this.controller,
    required this.stabilizer,
    required this.viewportTop,
  });

  final ScrollController controller;
  final ThreadDetailScrollStabilizer stabilizer;
  final double viewportTop;
}

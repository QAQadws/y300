import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

void main() {
  testWidgets('a displayed admitted frame survives either side of the edge', (
    tester,
  ) async {
    final fixture = await _Fixture.mount(tester);
    // No optional decode ever ran for this visible image.
    fixture.handles[0].reportFirstFrameRendered(canRetain: true);
    await tester.pump();
    for (final pixels in [350.5, 349.5, 350.5, 349.5]) {
      fixture.controller.jumpTo(pixels);
      await tester.pump();
      expect(
        fixture.mode(0),
        pixels > 350
            ? ForumHtmlImageViewportMode.retained
            : ForumHtmlImageViewportMode.display,
      );
    }
    fixture.coordinator.setActive(false);
    expect(fixture.mode(0), ForumHtmlImageViewportMode.dormant);
  });

  testWidgets('late size admission preserves an already settled frame', (
    tester,
  ) async {
    final fixture = await _Fixture.mount(tester);
    fixture.handles[0].reportFirstFrameRendered();
    await tester.pump();
    fixture.handles[0].reportFirstFrameRendered(canRetain: true);
    await tester.pump();
    fixture.controller.jumpTo(350.5);
    await tester.pump();
    expect(fixture.mode(0), ForumHtmlImageViewportMode.retained);
  });

  testWidgets('a later frame failure immediately releases a retained image', (
    tester,
  ) async {
    final fixture = await _Fixture.mount(tester);
    fixture.handles[0].reportFirstFrameRendered(canRetain: true);
    await tester.pump();
    fixture.controller.jumpTo(350.5);
    await tester.pump();
    expect(fixture.mode(0), ForumHtmlImageViewportMode.retained);
    fixture.handles[0].reportImageFailed();
    await tester.pump();
    expect(fixture.mode(0), ForumHtmlImageViewportMode.dormant);
  });

  for (final rejected in ['over budget', 'failed']) {
    testWidgets('$rejected display does not retain or become decode success', (
      tester,
    ) async {
      final fixture = await _Fixture.mount(tester);
      if (rejected == 'failed') {
        fixture.handles[0].reportImageFailed();
      } else {
        fixture.handles[0].reportFirstFrameRendered(canRetain: false);
      }
      await tester.pump();
      fixture.controller.jumpTo(350.5);
      await tester.pump();
      fixture.settleVisible();
      await tester.pump();
      expect(fixture.mode(0).keepsImageMounted, isFalse);
      if (rejected == 'failed') {
        expect(fixture.mode(0), ForumHtmlImageViewportMode.dormant);
      }
    });
  }

  testWidgets('a displayed frame is released beyond the bounded neighbors', (
    tester,
  ) async {
    final fixture = await _Fixture.mount(
      tester,
      heights: [350, ...List.filled(7, 250.0)],
    );
    fixture.handles[0].reportFirstFrameRendered(canRetain: true);
    await tester.pump();
    fixture.controller.jumpTo(700);
    await tester.pump();
    expect(fixture.mode(0), ForumHtmlImageViewportMode.dormant);
  });

  testWidgets(
    'completed look-ahead progresses without repeating prepared images',
    (tester) async {
      final fixture = await _Fixture.mount(tester);
      fixture.settleVisible();
      await tester.pump();
      expect(fixture.mode(1), ForumHtmlImageViewportMode.predecode);
      final first = fixture.handles[1].beginWork();
      first.complete(ForumHtmlImagePreparationOutcome.decoded);
      await tester.pump();
      expect(fixture.mode(1), ForumHtmlImageViewportMode.retained);
      expect(fixture.mode(2), ForumHtmlImageViewportMode.predecode);
      fixture.handles[2].beginWork().complete(
        ForumHtmlImagePreparationOutcome.diskOnly,
      );
      await tester.pump();
      expect(fixture.mode(2), ForumHtmlImageViewportMode.dormant);
      expect(fixture.mode(3), ForumHtmlImageViewportMode.prefetch);
      fixture.handles[3].beginWork().complete(
        ForumHtmlImagePreparationOutcome.failed,
      );
      await tester.pump();
      expect(
        fixture.handles.where(
          (h) => h.value == ForumHtmlImageViewportMode.predecode,
        ),
        isEmpty,
      );
      fixture.controller.jumpTo(1);
      await tester.pump();
      expect(fixture.mode(1), ForumHtmlImageViewportMode.retained);
    },
  );

  testWidgets('direction chooses the nearest edge even for very tall images', (
    tester,
  ) async {
    final fixture = await _Fixture.mount(tester, heights: [400, 400, 4000]);
    fixture.controller.jumpTo(200);
    await tester.pump();
    fixture.settleVisible();
    await tester.pump();
    expect(fixture.mode(2), ForumHtmlImageViewportMode.predecode);
    fixture.handles[2].beginWork().complete(
      ForumHtmlImagePreparationOutcome.decoded,
    );
    fixture.controller.jumpTo(600);
    await tester.pump();
    fixture.controller.jumpTo(500);
    await tester.pump();
    fixture.settleVisible();
    await tester.pump();
    expect(fixture.mode(0), ForumHtmlImageViewportMode.predecode);
  });

  testWidgets(
    'cancelled work retains capacity until completion and rejects late results',
    (tester) async {
      final fixture = await _Fixture.mount(tester);
      fixture.settleVisible();
      await tester.pump();
      final old = fixture.handles[1].beginWork();
      fixture.coordinator.reset();
      expect(old.isActive, isFalse);
      await tester.pump();
      fixture.settleVisible();
      await tester.pump();
      expect(
        fixture.handles.where(
          (h) => h.value == ForumHtmlImageViewportMode.predecode,
        ),
        isEmpty,
      );
      old.complete(ForumHtmlImagePreparationOutcome.decoded);
      await tester.pump();
      expect(fixture.mode(1), ForumHtmlImageViewportMode.predecode);
      final current = fixture.handles[1].beginWork();
      old.complete(ForumHtmlImagePreparationOutcome.decoded);
      expect(current.isActive, isTrue);
      current.complete(ForumHtmlImagePreparationOutcome.decoded);
    },
  );

  testWidgets(
    'reentering a window and changing target identity prepare again',
    (tester) async {
      final fixture = await _Fixture.mount(
        tester,
        heights: [350, ...List.filled(7, 250.0)],
      );
      fixture.settleVisible();
      await tester.pump();
      fixture.handles[1].beginWork().complete(
        ForumHtmlImagePreparationOutcome.decoded,
      );
      await tester.pump();
      fixture.controller.jumpTo(1700);
      await tester.pump();
      expect(fixture.mode(1), ForumHtmlImageViewportMode.dormant);
      fixture.controller.jumpTo(0);
      await tester.pump();
      fixture.settleVisible();
      await tester.pump();
      expect(fixture.mode(1), ForumHtmlImageViewportMode.predecode);
      final old = fixture.handles[1].beginWork();
      fixture.handles[1].configureWork(
        identity: 'new-width',
        canPredecode: true,
      );
      expect(old.isActive, isFalse);
      old.complete(ForumHtmlImagePreparationOutcome.decoded);
      await tester.pump();
      expect(fixture.mode(1), ForumHtmlImageViewportMode.predecode);
    },
  );

  testWidgets('two visible first frames pause optional work', (tester) async {
    final fixture = await _Fixture.mount(tester, heights: List.filled(5, 200));
    expect(fixture.mode(2), ForumHtmlImageViewportMode.dormant);
    fixture.handles[0].reportFirstFrameSettled();
    await tester.pump();
    expect(fixture.mode(2), ForumHtmlImageViewportMode.predecode);
  });

  testWidgets('a post-frame first frame wakes the waiting look-ahead', (
    tester,
  ) async {
    final fixture = await _Fixture.mount(tester, heights: List.filled(5, 200));
    await tester.pumpAndSettle();
    expect(fixture.mode(2), ForumHtmlImageViewportMode.dormant);
    expect(tester.binding.hasScheduledFrame, isFalse);

    var firstFrameReported = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      firstFrameReported = true;
      fixture.handles[0].reportFirstFrameSettled();
    });
    // Simulate the current image frame; only the subsequent frame must be
    // requested by the coordinator itself.
    tester.binding.scheduleFrame();
    await tester.pump();

    // Pumping again unconditionally would hide a missing frame request and
    // allow look-ahead to remain stalled until the user next scrolls.
    expect(firstFrameReported, isTrue);
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(fixture.mode(2), ForumHtmlImageViewportMode.dormant);
    await tester.pump();
    expect(fixture.mode(2), ForumHtmlImageViewportMode.predecode);
  });

  testWidgets('two optional leases progress independently on distinct images', (
    tester,
  ) async {
    final fixture = await _Fixture.mount(
      tester,
      maxConcurrentOptionalWork: 2,
      heights: const [350, 100, 100, 100, 300],
    );
    fixture.settleVisible();
    await tester.pump();
    expect(fixture.mode(1), ForumHtmlImageViewportMode.predecode);
    expect(fixture.mode(2), ForumHtmlImageViewportMode.predecode);
    expect(fixture.mode(3), ForumHtmlImageViewportMode.dormant);
    final first = fixture.handles[1].beginWork();
    final second = fixture.handles[2].beginWork();
    expect(fixture.handles[1].tryBeginWork(), isNull);
    final changes = <ForumHtmlImageViewportMode>[];
    fixture.handles[2].addListener(() => changes.add(fixture.mode(2)));
    fixture.controller.jumpTo(1);
    await tester.pump();
    expect(changes, isEmpty);
    expect(first.isActive, isTrue);
    expect(second.isActive, isTrue);

    first.complete(ForumHtmlImagePreparationOutcome.decoded);
    await tester.pump();
    expect(fixture.mode(1), ForumHtmlImageViewportMode.retained);
    expect(fixture.mode(2), ForumHtmlImageViewportMode.predecode);
    expect(fixture.mode(3), ForumHtmlImageViewportMode.prefetch);
    final third = fixture.handles[3].beginWork();
    first.complete(ForumHtmlImagePreparationOutcome.failed);
    expect(second.isActive, isTrue);
    expect(third.isActive, isTrue);
    second.complete(ForumHtmlImagePreparationOutcome.diskOnly);
    third.complete(ForumHtmlImagePreparationOutcome.diskOnly);
    await tester.pump();
    expect(fixture.mode(1), ForumHtmlImageViewportMode.retained);
    expect(fixture.mode(2), ForumHtmlImageViewportMode.dormant);
    expect(fixture.mode(3), ForumHtmlImageViewportMode.dormant);
  });

  testWidgets('cancelled leases release two slots only at actual completion', (
    tester,
  ) async {
    final fixture = await _Fixture.mount(tester, maxConcurrentOptionalWork: 2);
    fixture.settleVisible();
    await tester.pump();
    final first = fixture.handles[1].beginWork();
    final second = fixture.handles[2].beginWork();
    fixture.coordinator.setActive(false);
    expect(first.isActive, isFalse);
    expect(second.isActive, isFalse);
    fixture.coordinator.setActive(true);
    await tester.pump();
    fixture.settleVisible();
    await tester.pump();
    expect(fixture.mode(1), ForumHtmlImageViewportMode.dormant);
    expect(fixture.mode(2), ForumHtmlImageViewportMode.dormant);

    first.complete(ForumHtmlImagePreparationOutcome.decoded);
    await tester.pump();
    expect(fixture.mode(1), ForumHtmlImageViewportMode.predecode);
    expect(fixture.mode(2), ForumHtmlImageViewportMode.dormant);
    final current = fixture.handles[1].beginWork();
    second.complete(ForumHtmlImagePreparationOutcome.decoded);
    await tester.pump();
    expect(current.isActive, isTrue);
    expect(fixture.mode(2), ForumHtmlImageViewportMode.predecode);
    expect(fixture.mode(2).keepsImageMounted, isFalse);
    fixture.handles[2].beginWork().complete(
      ForumHtmlImagePreparationOutcome.diskOnly,
    );
    current.complete(ForumHtmlImagePreparationOutcome.diskOnly);
  });

  testWidgets('a retired handle cannot restart using another available slot', (
    tester,
  ) async {
    final fixture = await _Fixture.mount(tester, maxConcurrentOptionalWork: 2);
    fixture.settleVisible();
    await tester.pump();
    final old = fixture.handles[1].beginWork();
    old.cancel();
    // The old mode is still observable before the next evaluation.
    expect(fixture.handles[1].tryBeginWork(), isNull);
    fixture.handles[1].configureWork(identity: 'new-width', canPredecode: true);
    await tester.pump();
    expect(fixture.mode(1), ForumHtmlImageViewportMode.dormant);
    expect(fixture.mode(2), ForumHtmlImageViewportMode.predecode);
    final other = fixture.handles[2].beginWork();
    old.complete(ForumHtmlImagePreparationOutcome.decoded);
    await tester.pump();
    expect(fixture.mode(1), ForumHtmlImageViewportMode.predecode);
    final current = fixture.handles[1].beginWork();
    expect(current.isActive, isTrue);
    expect(other.isActive, isTrue);
    current.complete(ForumHtmlImagePreparationOutcome.diskOnly);
    other.complete(ForumHtmlImagePreparationOutcome.diskOnly);
  });

  testWidgets(
    'four visible first frames take priority over two optional slots',
    (tester) async {
      final fixture = await _Fixture.mount(
        tester,
        heights: List.filled(8, 70),
        maxVisibleFirstFrames: 4,
        maxConcurrentOptionalWork: 2,
      );
      expect(
        fixture.handles.where(
          (h) => h.value == ForumHtmlImageViewportMode.display,
        ),
        hasLength(4),
      );
      expect(fixture.mode(4), ForumHtmlImageViewportMode.dormant);
      fixture.handles[2].reportFirstFrameSettled();
      await tester.pump();
      expect(fixture.mode(4), ForumHtmlImageViewportMode.display);
      expect(fixture.mode(5), ForumHtmlImageViewportMode.dormant);
      fixture.settleVisible();
      await tester.pump();
      expect(fixture.mode(5), ForumHtmlImageViewportMode.predecode);
      expect(fixture.mode(6), ForumHtmlImageViewportMode.predecode);
      expect(fixture.mode(7), ForumHtmlImageViewportMode.dormant);
    },
  );

  testWidgets(
    'prepared frame survives leaving and reentering the visible edge',
    (tester) async {
      final fixture = await _Fixture.mount(tester);
      fixture.settleVisible();
      await tester.pump();
      fixture.handles[1].beginWork().complete(
        ForumHtmlImagePreparationOutcome.decoded,
      );
      await tester.pump();
      expect(fixture.mode(1), ForumHtmlImageViewportMode.retained);
      fixture.handles[1].reportFirstFrameSettled();
      for (final pixels in [51.0, 49.0, 51.0, 49.0]) {
        fixture.controller.jumpTo(pixels);
        await tester.pump();
        expect(
          fixture.mode(1),
          pixels > 50
              ? ForumHtmlImageViewportMode.display
              : ForumHtmlImageViewportMode.retained,
        );
      }
      fixture.coordinator.setActive(false);
      expect(fixture.mode(1), ForumHtmlImageViewportMode.dormant);
    },
  );

  testWidgets('fling defers decode and the scrolling notifier resumes it', (
    tester,
  ) async {
    final fixture = await _Fixture.mount(
      tester,
      physics: const _DeferredPhysics(),
    );
    fixture.settleVisible();
    fixture.controller.position.isScrollingNotifier.value = true;
    await tester.pump();
    expect(
      fixture.handles.where(
        (h) => h.value == ForumHtmlImageViewportMode.predecode,
      ),
      isEmpty,
    );
    fixture.controller.position.isScrollingNotifier.value = false;
    await tester.pump();
    expect(fixture.mode(1), ForumHtmlImageViewportMode.predecode);
  });
}

class _DeferredPhysics extends ClampingScrollPhysics {
  const _DeferredPhysics();
  @override
  bool recommendDeferredLoading(
    double velocity,
    ScrollMetrics metrics,
    BuildContext context,
  ) => Scrollable.of(context).position.isScrollingNotifier.value;
  @override
  _DeferredPhysics applyTo(ScrollPhysics? ancestor) => this;
}

class _Fixture {
  _Fixture(this.coordinator, this.controller, this.handles);
  final ForumHtmlImageViewportCoordinator coordinator;
  final ScrollController controller;
  final List<ForumHtmlImageViewportHandle> handles;
  ForumHtmlImageViewportMode mode(int index) => handles[index].value;
  void settleVisible() {
    for (final handle in handles) {
      if (handle.value == ForumHtmlImageViewportMode.display) {
        handle.reportFirstFrameSettled();
      }
    }
  }

  static Future<_Fixture> mount(
    WidgetTester tester, {
    List<double> heights = const [350, 120, 120, 250],
    ScrollPhysics? physics,
    int maxVisibleFirstFrames = 2,
    int maxConcurrentOptionalWork = 1,
  }) async {
    final coordinator = ForumHtmlImageViewportCoordinator(
      maxVisibleFirstFrames: maxVisibleFirstFrames,
      maxConcurrentOptionalWork: maxConcurrentOptionalWork,
      predecodePolicy: const ForumHtmlImagePredecodePolicy(
        maxDecodedBytesPerImage: 100000,
      ),
    );
    final controller = ScrollController();
    addTearDown(coordinator.dispose);
    addTearDown(controller.dispose);
    final handles = [
      for (var i = 0; i < heights.length; i++) coordinator.register(),
    ];
    for (var i = 0; i < handles.length; i++) {
      handles[i].configureWork(identity: i, canPredecode: true);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 300,
            child: SingleChildScrollView(
              controller: controller,
              physics: physics,
              child: Column(
                children: [
                  for (var i = 0; i < handles.length; i++)
                    Builder(
                      builder: (context) {
                        handles[i].bind(context);
                        return SizedBox(width: 300, height: heights[i]);
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return _Fixture(coordinator, controller, handles);
  }
}

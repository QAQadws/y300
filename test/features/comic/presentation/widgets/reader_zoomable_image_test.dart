import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_zoomable_image.dart';

Widget _hostZoomableImage({
  ReaderZoomBehavior behavior = ReaderZoomBehavior.bounded,
  ValueChanged<bool>? onZoomStateChanged,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 240,
          height: 240,
          child: ReaderZoomableImage(
            behavior: behavior,
            onZoomStateChanged: onZoomStateChanged,
            child: Container(color: Colors.blue),
          ),
        ),
      ),
    ),
  );
}

Widget _hostScrollableZoomableImage(
  ScrollController controller, {
  ReaderZoomBehavior behavior = ReaderZoomBehavior.bounded,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ListView(
        controller: controller,
        children: [
          SizedBox(
            height: 720,
            child: ReaderZoomableImage(
              behavior: behavior,
              child: Container(color: Colors.blue),
            ),
          ),
          const SizedBox(height: 720),
        ],
      ),
    ),
  );
}

InteractiveViewer _readInteractiveViewer(WidgetTester tester) {
  return tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
}

void main() {
  testWidgets('double tap toggles zoom state callback', (tester) async {
    final states = <bool>[];

    await tester.pumpWidget(_hostZoomableImage(onZoomStateChanged: states.add));

    final target = find.byType(ReaderZoomableImage);
    expect(target, findsOneWidget);

    await tester.tapAt(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(tester.getCenter(target));
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(tester.getCenter(target));
    await tester.pumpAndSettle();

    expect(states, containsAllInOrder(<bool>[true, false]));
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('InteractiveViewer stays out of the gesture arena at rest', (
    tester,
  ) async {
    // 关键契约：静止 1× 时既不启用 InteractiveViewer 手势，也不为双击
    // 额外挂 GestureDetector，外层 ListView/PageView 独享单指滚动。
    await tester.pumpWidget(_hostZoomableImage());
    await tester.pump();

    expect(find.byType(InteractiveViewer), findsNothing);
    expect(
      find.descendant(
        of: find.byType(ReaderZoomableImage),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
    );
  });

  testWidgets('single-finger drag on an image scrolls the parent list', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_hostScrollableZoomableImage(controller));

    final target = find.byType(ReaderZoomableImage);
    final start = tester.getCenter(target);
    for (var attempt = 0; attempt < 3; attempt += 1) {
      final previousOffset = controller.offset;
      await tester.dragFrom(start, const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(previousOffset));
    }
  });

  testWidgets('InteractiveViewer claims gestures after double-tap zoom-in', (
    tester,
  ) async {
    await tester.pumpWidget(_hostZoomableImage());
    final target = find.byType(ReaderZoomableImage);

    await tester.tapAt(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(tester.getCenter(target));
    await tester.pumpAndSettle();

    // 双击缩放动画走完后应处于 zoomed 状态，pan/scale 都必须已挂上，否则
    // 缩放态下的移动手势会没人接管。
    final viewer = _readInteractiveViewer(tester);
    expect(viewer.panEnabled, isTrue);
    expect(viewer.scaleEnabled, isTrue);
  });

  testWidgets('direct two-finger pinch activates the zoom surface', (
    tester,
  ) async {
    final states = <bool>[];
    await tester.pumpWidget(_hostZoomableImage(onZoomStateChanged: states.add));
    final target = find.byType(ReaderZoomableImage);
    final center = tester.getCenter(target);
    final first = await tester.createGesture(pointer: 1);
    final second = await tester.createGesture(pointer: 2);

    await first.down(center - const Offset(24, 0));
    await second.down(center + const Offset(24, 0));
    await tester.pump();
    await first.moveTo(center - const Offset(72, 0));
    await second.moveTo(center + const Offset(72, 0));
    await tester.pump();

    final viewer = _readInteractiveViewer(tester);
    expect(
      viewer.transformationController!.value.getMaxScaleOnAxis(),
      greaterThan(1),
    );
    expect(states, <bool>[true]);

    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('continuous vertical pinch scales the whole transform', (
    tester,
  ) async {
    await tester.pumpWidget(
      _hostZoomableImage(behavior: ReaderZoomBehavior.continuousVertical),
    );
    final target = find.byType(ReaderZoomableImage);
    final center = tester.getCenter(target);
    final first = await tester.createGesture(pointer: 1);
    final second = await tester.createGesture(pointer: 2);

    await first.down(center - const Offset(24, 0));
    await second.down(center + const Offset(24, 0));
    await tester.pump();
    await first.moveTo(center - const Offset(72, 0));
    await second.moveTo(center + const Offset(72, 0));
    await tester.pump();

    expect(find.byType(InteractiveViewer), findsNothing);
    final transform = tester.widget<Transform>(
      find.byKey(const Key('reader-continuous-zoom-transform')),
    );
    expect(transform.transform.getMaxScaleOnAxis(), greaterThan(1));

    await first.up();
    await second.up();
    await tester.pumpAndSettle();
  });

  testWidgets('continuous vertical zoom leaves parent scrolling available', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _hostScrollableZoomableImage(
        controller,
        behavior: ReaderZoomBehavior.continuousVertical,
      ),
    );
    final target = find.byType(ReaderZoomableImage);
    final center = tester.getCenter(target);

    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(center);
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsNothing);
    final transform = tester.widget<Transform>(
      find.byKey(const Key('reader-continuous-zoom-transform')),
    );
    expect(transform.transform.getMaxScaleOnAxis(), greaterThan(1));

    await tester.dragFrom(center, const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
  });
}

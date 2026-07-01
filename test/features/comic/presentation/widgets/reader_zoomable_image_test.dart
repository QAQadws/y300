import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_zoomable_image.dart';

Widget _hostZoomableImage({
  ValueChanged<bool>? onZoomStateChanged,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 240,
          height: 240,
          child: ReaderZoomableImage(
            onZoomStateChanged: onZoomStateChanged,
            child: Container(color: Colors.blue),
          ),
        ),
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
  });

  testWidgets(
    'InteractiveViewer stays out of the gesture arena at rest',
    (tester) async {
      // 关键契约：静止 1× 且无触点时，两个开关都关闭 → Flutter 框架不挂载
      // 内部 GestureDetector → 外层 ListView/PageView 独享单指滚动。
      await tester.pumpWidget(_hostZoomableImage());
      await tester.pump();

      final viewer = _readInteractiveViewer(tester);
      expect(viewer.panEnabled, isFalse);
      expect(viewer.scaleEnabled, isFalse);
    },
  );

  testWidgets(
    'InteractiveViewer claims gestures after double-tap zoom-in',
    (tester) async {
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
    },
  );

  testWidgets(
    'InteractiveViewer claims gestures when a second pointer touches down (pinch entry)',
    (tester) async {
      await tester.pumpWidget(_hostZoomableImage());
      final center = tester.getCenter(find.byType(ReaderZoomableImage));

      // 模拟 pinch 入场：第一根手指落下 → 第二根手指落下（此时框架尚未越过
      // slop，arena 还未决议）。sync 一帧后 InteractiveViewer 应已开启手势。
      final finger1 = await tester.startGesture(center - const Offset(10, 0));
      final finger2 = await tester.startGesture(center + const Offset(10, 0));
      await tester.pump();

      final viewer = _readInteractiveViewer(tester);
      expect(viewer.panEnabled, isTrue);
      expect(viewer.scaleEnabled, isTrue);

      // 抬起手指后回到 1×，再验一次恢复静默。
      await finger1.up();
      await finger2.up();
      await tester.pumpAndSettle();
      final restViewer = _readInteractiveViewer(tester);
      expect(restViewer.panEnabled, isFalse);
      expect(restViewer.scaleEnabled, isFalse);
    },
  );
}

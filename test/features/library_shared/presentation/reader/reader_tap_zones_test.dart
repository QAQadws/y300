import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../../test_support/localized_test_app.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_gesture_coordinator.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_paged_turn_motion.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_tap_zones.dart';

void main() {
  testWidgets('an owned region keeps its tap without activating the reader', (
    tester,
  ) async {
    var controlTaps = 0;
    var readerTaps = 0;
    await tester.pumpWidget(
      _buildTapZones(
        onCenterTap: () => readerTaps++,
        onRightTap: () => readerTaps++,
        child: Align(
          alignment: Alignment.centerRight,
          child: ReaderOwnedTapRegion(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => controlTaps++,
              child: const SizedBox(width: 140, height: 100),
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(500, 300));
    await tester.pump(const Duration(milliseconds: 330));
    expect(controlTaps, 1);
    expect(readerTaps, 0);
    await tester.tapAt(const Offset(300, 300));
    await tester.pump(const Duration(milliseconds: 330));
    expect(readerTaps, 1);
  });

  testWidgets('stationary long presses never commit a reader tap', (
    tester,
  ) async {
    var turns = 0;
    await tester.pumpWidget(
      _buildTapZones(
        onCenterTap: () => turns++,
        onLeftTap: () => turns++,
        onRightTap: () => turns++,
      ),
    );
    final press = await tester.startGesture(const Offset(100, 300));
    await tester.pump(const Duration(milliseconds: 600));
    await press.up(timeStamp: const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 330));
    expect(turns, 0);
    await tester.tapAt(const Offset(100, 300));
    await tester.pump(const Duration(milliseconds: 330));
    expect(turns, 1);
  });

  testWidgets('ReaderTapZones center tap triggers callback', (tester) async {
    var centerTaps = 0;
    await tester.pumpWidget(_buildTapZones(onCenterTap: () => centerTaps += 1));

    await tester.tapAt(const Offset(300, 300));
    await tester.pump(const Duration(milliseconds: 330));

    expect(centerTaps, 1);
  });

  testWidgets('ReaderTapZones left and right taps trigger optional callbacks', (
    tester,
  ) async {
    var leftTaps = 0;
    var rightTaps = 0;
    await tester.pumpWidget(
      _buildTapZones(
        onCenterTap: () {},
        onLeftTap: () => leftTaps += 1,
        onRightTap: () => rightTaps += 1,
      ),
    );

    await tester.tapAt(const Offset(100, 300));
    await tester.pump(const Duration(milliseconds: 330));
    await tester.tapAt(const Offset(500, 300));
    await tester.pump(const Duration(milliseconds: 330));

    expect(leftTaps, 1);
    expect(rightTaps, 1);
  });

  testWidgets('ReaderTapZones honors a shorter confirmation window', (
    tester,
  ) async {
    var rightTaps = 0;
    final coordinator = ReaderGestureCoordinator(
      doubleTapTimeout: ReaderPagedTurnMotion.tapConfirmationDelay,
    );
    addTearDown(coordinator.dispose);
    await tester.pumpWidget(
      _buildTapZones(
        gestureCoordinator: coordinator,
        onCenterTap: () {},
        onRightTap: () => rightTaps += 1,
      ),
    );

    await tester.tapAt(const Offset(500, 300));
    await tester.pump(const Duration(milliseconds: 219));
    expect(rightTaps, 0);

    await tester.pump(const Duration(milliseconds: 2));
    expect(rightTaps, 1);
  });

  testWidgets('consumed content interaction cancels a pending zone tap', (
    tester,
  ) async {
    var rightTaps = 0;
    final coordinator = ReaderGestureCoordinator(
      doubleTapTimeout: ReaderPagedTurnMotion.tapConfirmationDelay,
    );
    addTearDown(coordinator.dispose);
    await tester.pumpWidget(
      _buildTapZones(
        gestureCoordinator: coordinator,
        onCenterTap: () {},
        onRightTap: () => rightTaps += 1,
      ),
    );

    await tester.tapAt(const Offset(500, 300));
    coordinator.cancelPendingTap();
    await tester.pump(ReaderPagedTurnMotion.tapConfirmationDelay);

    expect(rightTaps, 0);
  });

  testWidgets('ReaderTapZones disabled does not trigger callbacks', (
    tester,
  ) async {
    var centerTaps = 0;
    await tester.pumpWidget(
      _buildTapZones(enabled: false, onCenterTap: () => centerTaps += 1),
    );

    await tester.tapAt(const Offset(300, 300));
    await tester.pump(const Duration(milliseconds: 330));

    expect(centerTaps, 0);
  });

  testWidgets('ReaderTapZones drag does not trigger tap', (tester) async {
    var centerTaps = 0;
    await tester.pumpWidget(_buildTapZones(onCenterTap: () => centerTaps += 1));

    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 330));

    expect(centerTaps, 0);
  });

  testWidgets('ReaderTapZones bottom safe area does not trigger tap', (
    tester,
  ) async {
    var centerTaps = 0;
    await tester.pumpWidget(
      _buildTapZones(
        bottomSafeFraction: 0.25,
        onCenterTap: () => centerTaps += 1,
      ),
    );

    await tester.tapAt(const Offset(400, 560));
    await tester.pump(const Duration(milliseconds: 330));

    expect(centerTaps, 0);
  });

  testWidgets('ReaderTapZones double tap cancels pending single tap', (
    tester,
  ) async {
    var centerTaps = 0;
    var doubleTaps = 0;
    final coordinator = ReaderGestureCoordinator();
    addTearDown(coordinator.dispose);
    coordinator.addDoubleTapListener((_) => doubleTaps += 1);
    await tester.pumpWidget(
      _buildTapZones(
        gestureCoordinator: coordinator,
        onCenterTap: () => centerTaps += 1,
      ),
    );

    await tester.tapAt(const Offset(300, 300));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(const Offset(300, 300));
    await tester.pump(const Duration(milliseconds: 330));

    expect(centerTaps, 0);
    expect(doubleTaps, 1);
  });

  testWidgets('ReaderTapZones slow taps commit as two single taps', (
    tester,
  ) async {
    var centerTaps = 0;
    await tester.pumpWidget(_buildTapZones(onCenterTap: () => centerTaps += 1));

    await tester.tapAt(const Offset(300, 300));
    await tester.pump(const Duration(milliseconds: 330));
    await tester.tapAt(const Offset(300, 300));
    await tester.pump(const Duration(milliseconds: 330));

    expect(centerTaps, 2);
  });

  testWidgets('blocked tap zones still route double taps to zoom', (
    tester,
  ) async {
    var centerTaps = 0;
    var doubleTaps = 0;
    final coordinator = ReaderGestureCoordinator();
    final blocked = ValueNotifier<bool>(true);
    addTearDown(coordinator.dispose);
    addTearDown(blocked.dispose);
    coordinator.addDoubleTapListener((_) => doubleTaps += 1);
    await tester.pumpWidget(
      _buildTapZones(
        gestureCoordinator: coordinator,
        blockedListenable: blocked,
        onCenterTap: () => centerTaps += 1,
      ),
    );

    await tester.tapAt(const Offset(300, 300));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(const Offset(300, 300));
    await tester.pump(const Duration(milliseconds: 330));

    expect(centerTaps, 0);
    expect(doubleTaps, 1);
  });
}

Widget _buildTapZones({
  required VoidCallback onCenterTap,
  VoidCallback? onLeftTap,
  VoidCallback? onRightTap,
  bool enabled = true,
  double bottomSafeFraction = 0,
  ValueListenable<bool>? blockedListenable,
  ReaderGestureCoordinator? gestureCoordinator,
  Widget child = const ColoredBox(color: Colors.white),
}) {
  return LocalizedTestApp(
    home: Scaffold(
      body: SizedBox(
        width: 600,
        height: 600,
        child: Stack(
          children: [
            ReaderTapZones(
              enabled: enabled,
              blockedListenable: blockedListenable,
              gestureCoordinator: gestureCoordinator,
              bottomSafeFraction: bottomSafeFraction,
              onCenterTap: onCenterTap,
              onLeftTap: onLeftTap,
              onRightTap: onRightTap,
              child: child,
            ),
          ],
        ),
      ),
    ),
  );
}

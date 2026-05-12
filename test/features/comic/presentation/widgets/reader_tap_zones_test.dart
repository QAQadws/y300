import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/presentation/widgets/reader_tap_zones.dart';

void main() {
  testWidgets('center tap triggers menu callback only', (tester) async {
    var centerTapped = 0;
    var leftTapped = 0;
    var rightTapped = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ReaderTapZones(
                onCenterTap: () => centerTapped++,
                onLeftTap: () => leftTapped++,
                onRightTap: () => rightTapped++,
              ),
            ],
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byKey(const Key('comic-reader-center-tap-zone')));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 360));

    expect(centerTapped, 1);
    expect(leftTapped, 0);
    expect(rightTapped, 0);
  });

  testWidgets('drag gestures can pass through to reader content', (tester) async {
    var centerTapped = 0;
    var dragUpdates = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ReaderTapZones(
                onCenterTap: () => centerTapped++,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (_) => dragUpdates++,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byKey(const Key('comic-reader-center-tap-zone')));
    await tester.dragFrom(center, const Offset(0, -120));
    await tester.pump();

    expect(centerTapped, 0);
    expect(dragUpdates, greaterThan(0));
  });

  testWidgets('double tap is reserved for image zoom gesture', (tester) async {
    var centerTapped = 0;
    var doubleTapped = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ReaderTapZones(
                onCenterTap: () => centerTapped++,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: () => doubleTapped++,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byKey(const Key('comic-reader-center-tap-zone')));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 360));

    expect(centerTapped, 0);
    expect(doubleTapped, 1);
  });

  testWidgets('tap zones ignore all taps when disabled', (tester) async {
    var centerTapped = 0;
    var leftTapped = 0;
    var rightTapped = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ReaderTapZones(
                enabled: false,
                onCenterTap: () => centerTapped++,
                onLeftTap: () => leftTapped++,
                onRightTap: () => rightTapped++,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tapAt(tester.getCenter(find.byKey(const Key('comic-reader-left-tap-zone'))));
    await tester.tapAt(tester.getCenter(find.byKey(const Key('comic-reader-center-tap-zone'))));
    await tester.tapAt(tester.getCenter(find.byKey(const Key('comic-reader-right-tap-zone'))));
    await tester.pump(const Duration(milliseconds: 360));

    expect(centerTapped, 0);
    expect(leftTapped, 0);
    expect(rightTapped, 0);
  });

  testWidgets('bottom safe fraction leaves lower area for content controls', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var centerTapped = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ReaderTapZones(
                bottomSafeFraction: 0.25,
                onCenterTap: () => centerTapped++,
              ),
            ],
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byKey(const Key('comic-reader-center-tap-zone')));
    await tester.tapAt(center);
    await tester.tapAt(Offset(center.dx, 792));
    await tester.pump(const Duration(milliseconds: 360));

    expect(centerTapped, 1);
  });
}

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

    await tester.tap(find.byKey(const Key('comic-reader-center-tap-zone')));
    await tester.pump();

    expect(centerTapped, 1);
    expect(leftTapped, 0);
    expect(rightTapped, 0);
  });
}

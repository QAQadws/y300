import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_zoomable_image.dart';

void main() {
  testWidgets('double tap toggles zoom state callback', (tester) async {
    final states = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              height: 240,
              child: ReaderZoomableImage(
                onZoomStateChanged: states.add,
                child: Container(color: Colors.blue),
              ),
            ),
          ),
        ),
      ),
    );

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
}

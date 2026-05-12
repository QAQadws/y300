import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/presentation/widgets/reader_page_indicator_overlay.dart';

void main() {
  testWidgets('page indicator renders current page and total pages', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ReaderPageIndicatorOverlay(
            visible: true,
            currentPage: 3,
            totalPages: 12,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('comic-reader-page-indicator-overlay')), findsOneWidget);
    expect(find.text('3 / 12'), findsOneWidget);
  });
}

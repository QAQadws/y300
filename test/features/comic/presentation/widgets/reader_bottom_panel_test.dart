import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/presentation/models/reader_preferences.dart';
import 'package:y300/features/comic/presentation/widgets/reader_bottom_panel.dart';

void main() {
  testWidgets('mode switch triggers callback with selected mode', (tester) async {
    ReaderModePreference? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderBottomPanel(
            currentMode: ReaderModePreference.vertical,
            onModeChanged: (mode) => selected = mode,
            currentPage: 1,
            totalPages: 12,
            hasPreviousEpisode: true,
            hasNextEpisode: true,
            onPreviousEpisode: () {},
            onNextEpisode: () {},
            onProgressChangeStart: (_) {},
            onProgressChanged: (_) {},
            onProgressChangeEnd: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('右到左'));
    await tester.pumpAndSettle();

    expect(selected, ReaderModePreference.rtl);
  });
}

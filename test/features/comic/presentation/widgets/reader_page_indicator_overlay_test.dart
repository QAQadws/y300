import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/comic/presentation/widgets/reader_page_indicator_overlay.dart';
import 'package:y300/features/library_shared/presentation/reader/reader.dart';

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

  testWidgets('page indicator uses reader overlay scrim with white text', (
    tester,
  ) async {
    final theme = AppTheme.dark();
    final palette = const ReaderChromePaletteResolver().resolve(theme);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: ReaderPageIndicatorOverlay(
            visible: true,
            currentPage: 1,
            totalPages: 2,
          ),
        ),
      ),
    );

    final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
    final decoration = box.decoration as BoxDecoration;
    final text = tester.widget<Text>(
      find.byKey(const Key('comic-reader-page-indicator-text')),
    );

    expect(decoration.color, palette.overlayScrim);
    expect(text.style?.color, Colors.white);
  });
}

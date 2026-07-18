import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/reader_preferences/reader_preferences.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_display_settings_sheet.dart';

void main() {
  testWidgets('renders display choices as independent outlined buttons', (
    tester,
  ) async {
    ReaderModePreference? selectedMode;
    ReaderPageFitPreference? selectedFit;
    ReaderBackgroundPreference? selectedBackground;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderDisplaySettingsSheet(
            preferences: ReaderPreferences.defaults(),
            onModeChanged: (value) => selectedMode = value,
            onPageFitChanged: (value) => selectedFit = value,
            onBackgroundChanged: (value) => selectedBackground = value,
            onPageSpacingChanged: (_) {},
            onShowPageIndicatorChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(OutlinedButton), findsNWidgets(11));
    expect(find.text('垂直'), findsOneWidget);
    expect(find.text('LTR'), findsOneWidget);
    expect(find.text('宽度'), findsOneWidget);
    expect(find.text('主题'), findsOneWidget);

    final selectedButtonFinder = find.ancestor(
      of: find.text('LTR'),
      matching: find.byType(OutlinedButton),
    );
    final unselectedButtonFinder = find.ancestor(
      of: find.text('垂直'),
      matching: find.byType(OutlinedButton),
    );
    final selectedButton = tester.widget<OutlinedButton>(selectedButtonFinder);
    final unselectedButton = tester.widget<OutlinedButton>(
      unselectedButtonFinder,
    );
    expect(tester.getSize(selectedButtonFinder).height, lessThanOrEqualTo(40));
    expect(
      selectedButton.style?.side?.resolve(const <WidgetState>{})?.color,
      Colors.transparent,
    );
    expect(
      unselectedButton.style?.side?.resolve(const <WidgetState>{})?.color,
      isNot(Colors.transparent),
    );

    await tester.tap(find.text('LTR'));
    await tester.tap(find.text('高度'));
    await tester.tap(find.text('黑'));
    await tester.pump();

    expect(selectedMode, ReaderModePreference.ltr);
    expect(selectedFit, ReaderPageFitPreference.fitHeight);
    expect(selectedBackground, ReaderBackgroundPreference.black);
  });
}

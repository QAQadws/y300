import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/presentation/models/reader_preferences.dart';

void main() {
  test('ReaderPreferences.defaults uses stable phase-0 defaults', () {
    final value = ReaderPreferences.defaults();

    expect(value.readerMode, ReaderModePreference.vertical);
    expect(value.pageFit, ReaderPageFitPreference.fitWidth);
    expect(value.background, ReaderBackgroundPreference.followTheme);
    expect(value.pageSpacing, 8);
    expect(value.showPageIndicator, isTrue);
  });

  test('ReaderPreferences.copyWith updates supported reader preferences', () {
    final value = ReaderPreferences.defaults().copyWith(
      pageFit: ReaderPageFitPreference.contain,
      background: ReaderBackgroundPreference.black,
      pageSpacing: 16,
      showPageIndicator: false,
    );

    expect(value.pageFit, ReaderPageFitPreference.contain);
    expect(value.background, ReaderBackgroundPreference.black);
    expect(value.pageSpacing, 16);
    expect(value.showPageIndicator, isFalse);
  });
}

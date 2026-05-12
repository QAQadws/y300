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
    expect(value.cropBorders, isFalse);
    expect(value.fullscreenOnOpen, isFalse);
    expect(value.cacheDirectoryPath, isNull);
  });

  test('ReaderPreferences.copyWith supports clearCacheDirectoryPath', () {
    final value = ReaderPreferences.defaults().copyWith(
      cacheDirectoryPath: 'C:/tmp/comic',
    );
    expect(value.cacheDirectoryPath, 'C:/tmp/comic');

    final cleared = value.copyWith(clearCacheDirectoryPath: true);
    expect(cleared.cacheDirectoryPath, isNull);
  });
}

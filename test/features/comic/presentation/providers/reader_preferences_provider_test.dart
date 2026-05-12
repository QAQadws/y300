import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/comic/presentation/models/reader_preferences.dart';
import 'package:y300/features/comic/presentation/providers/reader_preferences_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('controller loads default preferences when storage is empty', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final value = await container.read(readerPreferencesControllerProvider.future);
    expect(value.readerMode, ReaderModePreference.vertical);
    expect(value.showPageIndicator, isTrue);
  });

  test('controller persists and reloads updated reader mode', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(readerPreferencesControllerProvider.future);

    await container.read(readerPreferencesControllerProvider.notifier).setReaderMode(
          ReaderModePreference.rtl,
        );
    await container.read(readerPreferencesControllerProvider.notifier).setPageFit(
          ReaderPageFitPreference.contain,
        );
    await container.read(readerPreferencesControllerProvider.notifier).setShowPageIndicator(false);

    final freshContainer = ProviderContainer();
    addTearDown(freshContainer.dispose);
    final value = await freshContainer.read(readerPreferencesControllerProvider.future);
    expect(value.readerMode, ReaderModePreference.rtl);
    expect(value.pageFit, ReaderPageFitPreference.contain);
    expect(value.showPageIndicator, isFalse);
  });
}

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/reader_shared/domain/reader_preferences/reader_preferences.dart';
import 'package:y300/features/reader_shared/presentation/reader_preferences/reader_preferences_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('controller loads default preferences when storage is empty', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final value = await container.read(
      readerPreferencesControllerProvider.future,
    );
    expect(value.readerMode, ReaderModePreference.ltr);
    expect(value.pageFit, ReaderPageFitPreference.fitWidth);
    expect(value.background, ReaderBackgroundPreference.followTheme);
    expect(value.pageSpacing, 0);
    expect(value.showPageIndicator, isTrue);
  });

  test('repository reads legacy keys when the v1 snapshot is absent', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'reader_pref_mode': 'rtl',
      'reader_pref_page_fit': 'original',
      'reader_pref_background': 'gray',
      'reader_pref_page_spacing': 12.5,
      'reader_pref_show_page_indicator': false,
    });
    final repository = SharedPrefsReaderPreferencesRepository();

    final value = await repository.load();

    expect(value.readerMode, ReaderModePreference.rtl);
    expect(value.pageFit, ReaderPageFitPreference.original);
    expect(value.background, ReaderBackgroundPreference.gray);
    expect(value.pageSpacing, 12.5);
    expect(value.showPageIndicator, isFalse);
  });

  test('legacy fallback normalizes unknown values', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'reader_pref_mode': 'future-mode',
      'reader_pref_page_fit': 'future-fit',
      'reader_pref_background': 'future-background',
      'reader_pref_page_spacing': 99.0,
    });
    final repository = SharedPrefsReaderPreferencesRepository();

    final value = await repository.load();

    expect(value.readerMode, ReaderModePreference.ltr);
    expect(value.pageFit, ReaderPageFitPreference.fitWidth);
    expect(value.background, ReaderBackgroundPreference.followTheme);
    expect(value.pageSpacing, 48);
    expect(value.showPageIndicator, isTrue);
  });

  test('v1 snapshot wins over stale legacy keys', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'reader.image.v1': jsonEncode(<String, Object>{
        'schemaVersion': 1,
        'readerMode': 'ltr',
        'pageFit': 'contain',
        'background': 'white',
        'pageSpacing': 3,
        'showPageIndicator': false,
      }),
      'reader_pref_mode': 'rtl',
      'reader_pref_page_spacing': 20.0,
    });
    final repository = SharedPrefsReaderPreferencesRepository();

    final value = await repository.load();

    expect(value.readerMode, ReaderModePreference.ltr);
    expect(value.pageFit, ReaderPageFitPreference.contain);
    expect(value.background, ReaderBackgroundPreference.white);
    expect(value.pageSpacing, 3);
    expect(value.showPageIndicator, isFalse);
  });

  test('invalid v1 snapshots do not revive stale legacy values', () async {
    for (final snapshot in <Object>['{broken', true]) {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'reader.image.v1': snapshot,
        'reader_pref_mode': 'rtl',
        'reader_pref_page_spacing': 20.0,
      });
      final repository = SharedPrefsReaderPreferencesRepository();

      final value = await repository.load();

      expect(value.readerMode, ReaderModePreference.ltr);
      expect(value.pageSpacing, 0);
    }
  });

  test('repository writes one normalized v1 snapshot', () async {
    final repository = SharedPrefsReaderPreferencesRepository();
    const value = ReaderPreferences(
      readerMode: ReaderModePreference.rtl,
      pageFit: ReaderPageFitPreference.contain,
      background: ReaderBackgroundPreference.black,
      pageSpacing: 7.5,
      showPageIndicator: false,
    );

    await repository.save(value);
    final prefs = await SharedPreferences.getInstance();
    final snapshot =
        jsonDecode(prefs.getString('reader.image.v1')!) as Map<String, dynamic>;

    expect(snapshot['schemaVersion'], 1);
    expect(snapshot['readerMode'], 'rtl');
    expect(snapshot['pageFit'], 'contain');
    expect(snapshot['background'], 'black');
    expect(snapshot['pageSpacing'], 7.5);
    expect(snapshot['showPageIndicator'], isFalse);
    expect(prefs.containsKey('reader_pref_mode'), isFalse);
    expect(prefs.containsKey('reader_pref_page_spacing'), isFalse);
  });

  test('controller persists and reloads updated reader mode', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(readerPreferencesControllerProvider.future);

    await container
        .read(readerPreferencesControllerProvider.notifier)
        .setReaderMode(ReaderModePreference.rtl);
    await container
        .read(readerPreferencesControllerProvider.notifier)
        .setPageFit(ReaderPageFitPreference.contain);
    await container
        .read(readerPreferencesControllerProvider.notifier)
        .setShowPageIndicator(false);

    final freshContainer = ProviderContainer();
    addTearDown(freshContainer.dispose);
    final value = await freshContainer.read(
      readerPreferencesControllerProvider.future,
    );
    expect(value.readerMode, ReaderModePreference.rtl);
    expect(value.pageFit, ReaderPageFitPreference.contain);
    expect(value.showPageIndicator, isFalse);
  });
}

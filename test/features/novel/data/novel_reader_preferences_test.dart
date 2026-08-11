import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/preferences/novel_reader_preferences_snapshot_codec.dart';
import 'package:y300/features/novel/domain/models/novel_reader_spacing.dart';

void main() {
  test('NovelReaderPreferences.defaults uses the current reader baseline', () {
    final defaults = NovelReaderPreferences.defaults();

    expect(NovelReaderSpacing.verticalPagePadding, 8);
    expect(NovelReaderSpacing.pagedPagePadding, 8);
    expect(defaults.fontSize, 18.5);
    expect(defaults.lineHeight, 1.6);
    expect(defaults.paragraphSpacing, 10);
    expect(defaults.pagePadding, NovelReaderSpacing.pagedPagePadding);
    expect(defaults.fontFamily, 'system');
    expect(defaults.flowMode, NovelReaderFlowMode.pagedLtr);
    expect(defaults.themePreset, NovelReaderThemePreset.sepia);
    expect(defaults.contentMaxWidth, 720);
    expect(defaults.firstLineIndent, 0);
    expect(defaults.fontWeight, 400);
    expect(defaults.textAlign, NovelReaderTextAlignMode.start);
    expect(defaults.showProgressIndicator, isTrue);
    expect(defaults.conversionMode, NovelReaderConversionMode.none);
    expect(defaults.safeAreaEnabled, isTrue);
  });

  test('constructor uses the same default theme as the default snapshot', () {
    final preferences = NovelReaderPreferences(
      fontSize: 20,
      lineHeight: 1.7,
      paragraphSpacing: 8,
      pagePadding: 18,
      fontFamily: 'system',
    );

    expect(preferences.themePreset, NovelReaderThemePreset.sepia);
    expect(preferences.flowMode, NovelReaderFlowMode.pagedLtr);
  });

  group('NovelReaderThemePresetCodec', () {
    test('round-trips all supported values', () {
      for (final value in NovelReaderThemePreset.values) {
        expect(
          NovelReaderThemePresetCodec.fromStorage(value.storageValue),
          value,
        );
      }
    });

    test('keeps legacy system aliases and falls back to sepia', () {
      expect(
        NovelReaderThemePresetCodec.fromStorage('follow_system'),
        NovelReaderThemePreset.followSystem,
      );
      expect(
        NovelReaderThemePresetCodec.fromStorage('system'),
        NovelReaderThemePreset.followSystem,
      );
      expect(
        NovelReaderThemePresetCodec.fromStorage('future-theme'),
        NovelReaderThemePreset.sepia,
      );
      expect(
        NovelReaderThemePresetCodec.fromStorage(null),
        NovelReaderThemePreset.sepia,
      );
    });
  });

  group('NovelReaderFlowModeCodec', () {
    test('round-trips all supported values', () {
      for (final value in NovelReaderFlowMode.values) {
        expect(NovelReaderFlowModeCodec.fromStorage(value.storageValue), value);
      }
    });

    test('keeps legacy aliases and falls back to vertical', () {
      expect(
        NovelReaderFlowModeCodec.fromStorage('paged_ltr'),
        NovelReaderFlowMode.pagedLtr,
      );
      expect(
        NovelReaderFlowModeCodec.fromStorage('paged_rtl'),
        NovelReaderFlowMode.pagedRtl,
      );
      expect(
        NovelReaderFlowModeCodec.fromStorage('future-flow'),
        NovelReaderFlowMode.vertical,
      );
    });
  });

  test('text alignment codec round-trips and rejects unknown values', () {
    for (final value in NovelReaderTextAlignMode.values) {
      expect(
        NovelReaderTextAlignModeCodec.fromStorage(value.storageValue),
        value,
      );
    }
    expect(
      NovelReaderTextAlignModeCodec.fromStorage('future-alignment'),
      NovelReaderTextAlignMode.start,
    );
  });

  test('conversion codec round-trips and rejects unknown values', () {
    for (final value in NovelReaderConversionMode.values) {
      expect(
        NovelReaderConversionModeCodec.fromStorage(value.storageValue),
        value,
      );
    }
    expect(
      NovelReaderConversionModeCodec.fromStorage('future-conversion'),
      NovelReaderConversionMode.none,
    );
  });

  test(
    'safe area preference round-trips and defaults old snapshots to enabled',
    () {
      const codec = NovelReaderPreferencesSnapshotCodec();
      final preferences = NovelReaderPreferences.defaults().copyWith(
        safeAreaEnabled: false,
      );

      expect(codec.decode(codec.encode(preferences)).safeAreaEnabled, isFalse);
      expect(
        codec
            .decode('{"schemaVersion":1,"fontSize":18.5,"lineHeight":1.6}')
            .safeAreaEnabled,
        isTrue,
      );
      expect(
        codec
            .decode('{"schemaVersion":1,"safeAreaEnabled":"false"}')
            .safeAreaEnabled,
        isTrue,
      );
    },
  );
}

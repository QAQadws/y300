import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/novel/data/preferences/novel_reader_preferences_legacy_source.dart';
import 'package:y300/features/novel/data/preferences/novel_reader_preferences_snapshot_codec.dart';
import 'package:y300/features/novel/data/preferences/shared_preferences_novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/repositories/novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_preference_impact_analyzer.dart';

const _codec = NovelReaderPreferencesSnapshotCodec();
const _selected = NovelReaderColorOverrides(
  foreground: 0x123456,
  background: 0xf4ead7,
);
NovelReaderPreferences _prefs() => NovelReaderPreferences.defaults().copyWith(
  colors: _selected,
  viewport: const NovelReaderViewportOverrides(left: 0),
  typography: const NovelReaderTypographyOverrides(
    wordSpacing: NovelReaderWordSpacing(logicalPixels: 4),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('opaque RGB extremes, inheritance and independent reset survive reconstruction', () async {
    expect(const NovelReaderColorOverrides().over(_selected), _selected);
    expect(_selected.withForeground(null).background, _selected.background);
    expect(_selected.withBackground(null).foreground, _selected.foreground);
    for (final rgb in [0, 0xffffff, 0x123456]) {
      final prefs = _prefs().copyWith(
        colors: NovelReaderColorOverrides(foreground: rgb, background: rgb),
      );
      await _repository().save(prefs);
      expect(await _repository().load(), prefs);
    }
    await _repository().save(_prefs());
    final reset = _prefs().copyWith(colors: _selected.withForeground(null));
    await _repository().save(reset);
    expect(await _repository().load(), reset);
    expect(reset.copyWith(fontFamily: 'system').colors, reset.colors);
    final raw = jsonDecode(_codec.encode(reset)) as Map;
    expect((raw['colors'] as Map)['foreground'], isNull);
    expect((raw['colors'] as Map)['background'], {
      'space': 'srgb',
      'value': 0xf4ead7,
      'enabled': true,
    });
    expect(
      jsonDecode(_codec.encode(NovelReaderPreferences.defaults())),
      isNot(contains('colors')),
    );
    const impact = DefaultNovelReaderPreferenceImpactAnalyzer();
    expect(impact.compare(_prefs(), reset).impacts, {
      NovelReaderPreferenceImpact.repaintOnly,
    });
  });
  test('bad RGB numbers normalize without rounding or inventing alpha', () {
    for (final value in [-1, 0x1000000]) {
      expect(
        _codec
            .normalize(
              _prefs().copyWith(
                colors: NovelReaderColorOverrides(foreground: value),
              ),
            )
            .colors
            .isEmpty,
        true,
      );
    }
    for (final value in [-1, 0x1000000, 1.5, '000000', true, null]) {
      final raw = jsonDecode(_codec.encode(_prefs())) as Map;
      ((raw['colors'] as Map)['foreground'] as Map)['value'] = value;
      final loaded = _codec.decode(jsonEncode(raw));
      expect(loaded.colors.foreground, isNull);
      expect(loaded.colors.background, _selected.background);
      expect(loaded.typography, _prefs().typography);
    }
  });
  for (final (field, unknown) in <(String?, Object)>[
    (null, {'schemaVersion': 2}),
    (null, []),
    ('foreground', {'space': 'displayP3', 'value': 0}),
    ('foreground', {'space': 'srgb', 'value': 0, 'enabled': 'yes'}),
    ('background', 0),
    ('background', {'value': 0}),
  ]) {
    test(
      'unknown color format rejects writes and preserves exact raw source ($field,$unknown)',
      () async {
        final raw = jsonDecode(_codec.encode(_prefs())) as Map;
        if (field == null) {
          raw['colors'] = unknown;
        } else {
          (raw['colors'] as Map)[field] = unknown;
        }
        final source = ' ${jsonEncode(raw)} ';
        final storage = await SharedPreferences.getInstance();
        await storage.setString(
          PreferenceKeys.novelReaderSnapshotV1.name,
          source,
        );
        final repo = _repository();
        final loaded = await repo.load();
        for (final next in [
          loaded.copyWith(fontSize: 24),
          loaded.copyWith(colors: const NovelReaderColorOverrides()),
        ]) {
          await expectLater(
            repo.save(next),
            throwsA(isA<NovelReaderPreferencesUnsupportedSnapshot>()),
          );
          expect(
            storage.getString(PreferenceKeys.novelReaderSnapshotV1.name),
            source,
          );
        }
      },
    );
  }
  test('known extensions survive reset inactive and later reactivation', () {
    final raw = jsonDecode(_codec.encode(_prefs())) as Map;
    final colors = raw['colors'] as Map;
    colors['extension'] = {'keep': true};
    (colors['foreground'] as Map)['futureNote'] = [1, 2];
    final reset = _prefs().copyWith(colors: const NovelReaderColorOverrides());
    final saved = _codec.encode(reset, previousSource: jsonEncode(raw));
    final inactive = (jsonDecode(saved) as Map)['colors'] as Map;
    expect((inactive['foreground'] as Map)['enabled'], false);
    expect((inactive['foreground'] as Map)['futureNote'], [1, 2]);
    expect(inactive['background'], isNull);
    expect(inactive['extension'], {'keep': true});
    expect(_codec.decode(saved).colors.isEmpty, true);
    final active =
        (jsonDecode(_codec.encode(_prefs(), previousSource: saved))
                as Map)['colors']
            as Map;
    expect((active['foreground'] as Map)['enabled'], true);
    expect((active['foreground'] as Map)['futureNote'], [1, 2]);
  });
  test('writer rechecks late future color namespace before saving', () async {
    final repo = _repository();
    await repo.save(_prefs());
    final loaded = await repo.load();
    final raw = jsonDecode(_codec.encode(loaded)) as Map;
    (raw['colors'] as Map)['schemaVersion'] = 2;
    final source = jsonEncode(raw);
    final storage = await SharedPreferences.getInstance();
    await storage.setString(PreferenceKeys.novelReaderSnapshotV1.name, source);
    await expectLater(
      repo.save(loaded),
      throwsA(isA<NovelReaderPreferencesUnsupportedSnapshot>()),
    );
    expect(
      storage.getString(PreferenceKeys.novelReaderSnapshotV1.name),
      source,
    );
  });
}

SharedPreferencesNovelReaderPreferencesRepository _repository() =>
    SharedPreferencesNovelReaderPreferencesRepository(
      preferencesStore: SharedPreferencesStore(),
      legacySource: const _NoLegacy(),
    );

class _NoLegacy implements NovelReaderPreferencesLegacySource {
  const _NoLegacy();
  @override
  Future<NovelReaderPreferences?> load() async => null;
}

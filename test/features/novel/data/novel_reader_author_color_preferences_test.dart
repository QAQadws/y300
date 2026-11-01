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
const _colors = NovelReaderColorOverrides(
  foreground: 0x203040,
  background: 0xe8f0d8,
  foregroundScope: NovelReaderStyleScope.forceBody,
  backgroundScope: NovelReaderStyleScope.forceAll,
);
NovelReaderPreferences _prefs([NovelReaderColorOverrides colors = _colors]) =>
    NovelReaderPreferences.defaults().copyWith(
      colors: colors,
      viewport: const NovelReaderViewportOverrides(left: 0),
      typography: const NovelReaderTypographyOverrides(
        wordSpacing: NovelReaderWordSpacing(logicalPixels: 4),
      ),
    );
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('every independent scope pair saves without changing RGB, typography or viewport', () async {
    for (final foreground in [null, ...NovelReaderStyleScope.values]) {
      for (final background in [null, ...NovelReaderStyleScope.values]) {
        final prefs = _prefs(
          _colors
              .withForegroundScope(foreground)
              .withBackgroundScope(background),
        );
        await _repository().save(prefs);
        expect(await _repository().load(), prefs);
        expect(prefs.copyWith(fontFamily: 'system').colors, prefs.colors);
      }
    }
    final reset = _colors.withForegroundScope(null);
    expect(reset.backgroundScope, NovelReaderStyleScope.forceAll);
    expect(reset.foreground, _colors.foreground);
    expect(reset.withBackground(null).foregroundScope, isNull);
    expect(
      reset.withForeground(0).backgroundScope,
      NovelReaderStyleScope.forceAll,
    );
    expect(const NovelReaderColorOverrides().over(_colors), _colors);
    const analyzer = DefaultNovelReaderPreferenceImpactAnalyzer();
    expect(analyzer.compare(_prefs(), _prefs(reset)).impacts, {
      NovelReaderPreferenceImpact.repaintOnly,
    });
  });
  test(
    'scope-only requests remain sparse without inventing custom color values',
    () {
      const colors = NovelReaderColorOverrides(
        foregroundScope: NovelReaderStyleScope.asDefault,
      );
      expect(colors.hasCustomColors, false);
      expect(colors.isEmpty, false);
      final raw =
          (jsonDecode(_codec.encode(_prefs(colors))) as Map)['colors'] as Map;
      expect(raw, {
        'schemaVersion': 1,
        'foregroundScope': {'scope': 'asDefault', 'enabled': true},
      });
      expect(_codec.decode(_codec.encode(_prefs(colors))).colors, colors);
      expect(colors.withForegroundScope(null).isEmpty, true);
    },
  );
  for (final field in ['foregroundScope', 'backgroundScope']) {
    for (final unknown in <Object>[
      1,
      [],
      {'scope': 'future'},
      {'scope': 'forceBody', 'enabled': 'yes'},
    ]) {
      test(
        'future policy shape/enum is read-only at write boundary ($field,$unknown)',
        () async {
          final raw = jsonDecode(_codec.encode(_prefs())) as Map;
          (raw['colors'] as Map)[field] = unknown;
          final source = ' ${jsonEncode(raw)} ';
          final storage = await SharedPreferences.getInstance();
          await storage.setString(
            PreferenceKeys.novelReaderSnapshotV1.name,
            source,
          );
          final repo = _repository();
          final loaded = await repo.load();
          expect(loaded.colors.foreground, _colors.foreground);
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
  }
  test('scope reset preserves future extensions inactive and RGB metadata', () {
    final raw = jsonDecode(_codec.encode(_prefs())) as Map;
    ((raw['colors'] as Map)['foregroundScope'] as Map)['extension'] = {
      'keep': true,
    };
    final reset = _prefs(_colors.withForegroundScope(null));
    final saved = _codec.encode(reset, previousSource: jsonEncode(raw));
    final decoded = _codec.decode(saved);
    expect(decoded.colors, reset.colors);
    final colors = (jsonDecode(saved) as Map)['colors'] as Map;
    expect((colors['foregroundScope'] as Map)['enabled'], false);
    expect((colors['foregroundScope'] as Map)['extension'], {'keep': true});
    expect((colors['backgroundScope'] as Map)['scope'], 'forceAll');
    expect((colors['foreground'] as Map)['value'], _colors.foreground);
    final reenabled =
        (jsonDecode(_codec.encode(_prefs(), previousSource: saved))
                as Map)['colors']
            as Map;
    expect((reenabled['foregroundScope'] as Map)['enabled'], true);
    expect((reenabled['foregroundScope'] as Map)['extension'], {'keep': true});
  });
  test('late future author scope is rechecked by the same writer', () async {
    final repo = _repository();
    await repo.save(_prefs());
    final loaded = await repo.load();
    final raw = jsonDecode(_codec.encode(loaded)) as Map;
    (raw['colors'] as Map)['foregroundScope'] = {'scope': 'future'};
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

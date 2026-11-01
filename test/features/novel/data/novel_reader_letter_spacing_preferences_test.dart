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
const _other = NovelReaderTypographyOverrides(
  firstLineIndent: NovelReaderFirstLineIndent(em: 1.5),
  paragraphSpacing: NovelReaderParagraphSpacing(before: 12, after: 31),
);
NovelReaderPreferences _prefs(NovelReaderLetterSpacing? request) =>
    NovelReaderPreferences.defaults().copyWith(
      typography: _other.withLetterSpacing(request),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'absence retains contextual defaults while explicit zero remains a request',
    () {
      const zero = NovelReaderLetterSpacing(
        logicalPixels: 0,
        scope: NovelReaderStyleScope.asDefault,
      );
      final explicit = _prefs(zero).typography;
      expect(const NovelReaderTypographyOverrides().over(explicit), explicit);
      expect(_other.withLetterSpacing(zero).withLetterSpacing(null), _other);
      expect(explicit.withFirstLineIndent(null).letterSpacing, zero);
      expect(explicit.withParagraphSpacing(null).letterSpacing, zero);
      expect(_prefs(null), isNot(_prefs(zero)));
      const analyzer = DefaultNovelReaderPreferenceImpactAnalyzer();
      expect(analyzer.compare(_prefs(null), _prefs(zero)).impacts, {
        NovelReaderPreferenceImpact.relayout,
      });
      expect(analyzer.compare(_prefs(zero), _prefs(zero)).impacts, {
        NovelReaderPreferenceImpact.none,
      });
      expect(
        (jsonDecode(_codec.encode(_prefs(null))) as Map)['typography'] as Map,
        isNot(contains('letterSpacing')),
      );
    },
  );
  test(
    'negative, zero and maximum spacing survive a reconstructed repository',
    () async {
      for (final scope in NovelReaderStyleScope.values) {
        for (final number in [-2.0, -1.25, 0.0, 8.0]) {
          final requested =
              _prefs(
                NovelReaderLetterSpacing(logicalPixels: number, scope: scope),
              ).copyWith(
                fontSize: 23,
                safeAreaEnabled: false,
                themePreset: NovelReaderThemePreset.sepia,
              );
          await _repository().save(requested);
          expect(await _repository().load(), requested);
        }
      }
    },
  );
  test('invalid letter spacing is isolated from existing requests', () {
    for (final bad in [-2.25, 8.25, double.nan, double.infinity]) {
      final normalized = _codec.normalize(
        _prefs(NovelReaderLetterSpacing(logicalPixels: bad)),
      );
      expect(normalized.typography, _other);
    }
    final valid = _prefs(const NovelReaderLetterSpacing(logicalPixels: -1.25));
    final invalidIndent = _codec.normalize(
      valid.copyWith(
        typography: valid.typography.withFirstLineIndent(
          const NovelReaderFirstLineIndent(em: -1),
        ),
      ),
    );
    expect(
      invalidIndent.typography.letterSpacing,
      valid.typography.letterSpacing,
    );
  });
  test(
    'reset preserves extensions, other requests and inactive data idempotently',
    () {
      final raw = jsonDecode(
        _codec.encode(
          _prefs(const NovelReaderLetterSpacing(logicalPixels: -1.25)),
        ),
      ) as Map;
      final typography = raw['typography'] as Map;
      typography['futureSetting'] = {'opaque': true};
      (typography['letterSpacing'] as Map)['extension'] = [1, null, 'preserve'];
      final source = jsonEncode(raw);
      final loaded = _codec.decode(source);
      final fontEdit = _codec.encode(
        loaded.copyWith(fontSize: 24),
        previousSource: source,
      );
      final reset = _codec.encode(
        loaded.copyWith(typography: loaded.typography.withLetterSpacing(null)),
        previousSource: fontEdit,
      );
      final after = (jsonDecode(reset) as Map)['typography'] as Map;
      expect((after['letterSpacing'] as Map)['enabled'], isFalse);
      expect((after['letterSpacing'] as Map)['extension'], [
        1,
        null,
        'preserve',
      ]);
      expect(after['futureSetting'], {'opaque': true});
      expect(_codec.decode(reset).typography, _other);
      expect(
        jsonDecode(_codec.encode(_codec.decode(reset), previousSource: reset)),
        jsonDecode(reset),
      );
    },
  );
  for (final future in [
    {'unit': 'em', 'value': 1, 'scope': 'forceBody'},
    {'unit': 'logicalPixels', 'value': 1, 'scope': 'future'},
    {
      'unit': 'logicalPixels',
      'value': 1,
      'scope': 'forceBody',
      'enabled': 'future',
    },
    'futureFormat',
  ]) {
    test(
      'unknown letter spacing survives load and rejected reset/edit: $future',
      () async {
        final raw = jsonDecode(_codec.encode(_prefs(null))) as Map;
        (raw['typography'] as Map)['letterSpacing'] = future;
        final source = ' ${jsonEncode(raw)} ';
        final storage = await SharedPreferences.getInstance();
        await storage.setString(
          PreferenceKeys.novelReaderSnapshotV1.name,
          source,
        );
        final loaded = await _repository().load();
        expect(loaded.typography, _other);
        for (final next in [loaded.copyWith(fontSize: 24), _prefs(null)]) {
          await expectLater(
            _repository().save(next),
            throwsA(isA<NovelReaderPreferencesUnsupportedSnapshot>()),
          );
          expect(
            storage.getString(PreferenceKeys.novelReaderSnapshotV1.name),
            source,
          );
        }
        expect(
          storage.containsKey(PreferenceKeys.novelReaderMigrationVersion.name),
          isFalse,
        );
      },
    );
  }
  test('new field format is rechecked at the write boundary', () async {
    final repo = _repository();
    await repo.save(
      _prefs(const NovelReaderLetterSpacing(logicalPixels: -1.25)),
    );
    final loaded = await repo.load();
    final raw = jsonDecode(_codec.encode(loaded)) as Map;
    ((raw['typography'] as Map)['letterSpacing'] as Map)['unit'] = 'future';
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
      legacySource: _NoLegacy(),
    );

final class _NoLegacy implements NovelReaderPreferencesLegacySource {
  @override
  Future<NovelReaderPreferences?> load() async => null;
}

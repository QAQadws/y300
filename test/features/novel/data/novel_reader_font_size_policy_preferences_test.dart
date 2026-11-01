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
  letterSpacing: NovelReaderLetterSpacing(logicalPixels: -1.25),
  wordSpacing: NovelReaderWordSpacing(logicalPixels: 7.5),
);
NovelReaderPreferences _prefs(NovelReaderStyleScope? scope) =>
    NovelReaderPreferences.defaults().copyWith(
      fontSize: 23,
      typography: _other.withFontSizeScope(scope),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('explicit author policy overrides inheritance while reset retains all values', () {
    final author = _other.withFontSizeScope(NovelReaderStyleScope.asDefault);
    final body = _other.withFontSizeScope(NovelReaderStyleScope.forceBody);
    expect(const NovelReaderTypographyOverrides().over(body), body);
    expect(author.over(body), author);
    expect(author, isNot(_other));
    expect(author.withFontSizeScope(null), _other);
    for (final edit in [
      author.withFirstLineIndent(null),
      author.withParagraphSpacing(null),
      author.withLetterSpacing(null),
      author.withWordSpacing(null),
    ]) {
      expect(edit.fontSizeScope, NovelReaderStyleScope.asDefault);
    }
    const analyzer = DefaultNovelReaderPreferenceImpactAnalyzer();
    expect(
      analyzer
          .compare(_prefs(null), _prefs(NovelReaderStyleScope.forceBody))
          .impacts,
      {NovelReaderPreferenceImpact.relayout},
    );
    expect(
      analyzer
          .compare(
            _prefs(NovelReaderStyleScope.forceBody),
            _prefs(NovelReaderStyleScope.forceBody),
          )
          .impacts,
      {NovelReaderPreferenceImpact.none},
    );
  });
  test(
    'all scopes roundtrip against the single persisted root font-size value',
    () async {
      for (final scope in NovelReaderStyleScope.values) {
        for (final size in [14.0, 18.5, 30.0]) {
          final requested = _prefs(
            scope,
          ).copyWith(fontSize: size, themePreset: NovelReaderThemePreset.sepia);
          await _repository().save(requested);
          expect(await _repository().load(), requested);
          final raw = jsonDecode(_codec.encode(requested)) as Map;
          expect(raw['fontSize'], size);
          expect((raw['typography'] as Map)['fontSizePolicy'], {
            'scope': scope.name,
            'enabled': true,
          });
        }
      }
    },
  );
  test(
    'old snapshots stay byte-exact without an implicit policy migration',
    () async {
      const source = ' {"schemaVersion":1,"fontSize":23} ';
      final storage = await SharedPreferences.getInstance();
      await storage.setString(
        PreferenceKeys.novelReaderSnapshotV1.name,
        source,
      );
      final loaded = await _repository().load();
      expect(loaded.fontSize, 23);
      expect(loaded.typography.fontSizeScope, isNull);
      expect(
        storage.getString(PreferenceKeys.novelReaderSnapshotV1.name),
        source,
      );
    },
  );
  test(
    'reset only retires the known policy and keeps extensions idempotently',
    () {
      final raw = jsonDecode(
        _codec.encode(_prefs(NovelReaderStyleScope.forceBody)),
      ) as Map;
      final typography = raw['typography'] as Map;
      typography['futureSetting'] = {'opaque': true};
      (typography['fontSizePolicy'] as Map)['extension'] = [1, null, 'keep'];
      final source = jsonEncode(raw);
      final loaded = _codec.decode(source);
      final reset = _codec.encode(
        loaded.copyWith(typography: loaded.typography.withFontSizeScope(null)),
        previousSource: source,
      );
      final after = (jsonDecode(reset) as Map)['typography'] as Map;
      expect(after['fontSizePolicy'], {
        'scope': 'forceBody',
        'enabled': false,
        'extension': [1, null, 'keep'],
      });
      expect(after['futureSetting'], {'opaque': true});
      expect(_codec.decode(reset).fontSize, 23);
      expect(_codec.decode(reset).typography, _other);
      expect(
        jsonDecode(_codec.encode(_codec.decode(reset), previousSource: reset)),
        jsonDecode(reset),
      );
      final clean = _codec.encode(
        _prefs(null),
        previousSource: _codec.encode(_prefs(NovelReaderStyleScope.forceAll)),
      );
      expect(
        (jsonDecode(clean) as Map)['typography'] as Map,
        isNot(contains('fontSizePolicy')),
      );
    },
  );
  for (final future in [
    {'scope': 'future'},
    {'scope': 'forceBody', 'enabled': 'future'},
    {'futureShape': true},
    'futureFormat',
  ]) {
    test(
      'unknown policy is read-only through unrelated edit and reset: $future',
      () async {
        final raw = jsonDecode(_codec.encode(_prefs(null))) as Map;
        (raw['typography'] as Map)['fontSizePolicy'] = future;
        final source = ' ${jsonEncode(raw)} ';
        final storage = await SharedPreferences.getInstance();
        await storage.setString(
          PreferenceKeys.novelReaderSnapshotV1.name,
          source,
        );
        final loaded = await _repository().load();
        expect(loaded.typography, _other);
        for (final next in [
          loaded.copyWith(fontSize: 24),
          _prefs(NovelReaderStyleScope.asDefault),
        ]) {
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
  test('same-version policy upgrade after load is rechecked on save', () async {
    final repo = _repository();
    await repo.save(_prefs(NovelReaderStyleScope.forceBody));
    final loaded = await repo.load();
    final raw = jsonDecode(_codec.encode(loaded)) as Map;
    ((raw['typography'] as Map)['fontSizePolicy'] as Map)['scope'] = 'future';
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

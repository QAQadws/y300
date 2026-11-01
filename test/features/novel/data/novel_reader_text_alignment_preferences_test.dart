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
  fontWeight: NovelReaderFontWeight(value: 700),
  fontSizeScope: NovelReaderStyleScope.forceBody,
  lineHeightScope: NovelReaderStyleScope.asDefault,
);
NovelReaderPreferences _prefs(NovelReaderTextAlignment? alignment) =>
    NovelReaderPreferences.defaults().copyWith(
      typography: _other.withTextAlignment(alignment),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'explicit default differs from absence; every field edit retains alignment',
    () {
      const request = NovelReaderTextAlignment(
        mode: NovelReaderTextAlignMode.start,
        scope: NovelReaderStyleScope.asDefault,
      );
      final value = _other.withTextAlignment(request);
      expect(const NovelReaderTypographyOverrides().over(value), value);
      expect(value.withTextAlignment(null), _other);
      expect(value, isNot(_other));
      expect(
        const NovelReaderTypographyOverrides(textAlignment: request).isEmpty,
        false,
      );
      for (final edited in [
        value.withFirstLineIndent(null),
        value.withParagraphSpacing(null),
        value.withLetterSpacing(null),
        value.withWordSpacing(null),
        value.withFontWeight(null),
        value.withFontSizeScope(null),
        value.withLineHeightScope(null),
      ]) {
        expect(edited.textAlignment, request);
      }
      const analyzer = DefaultNovelReaderPreferenceImpactAnalyzer();
      expect(analyzer.compare(_prefs(null), _prefs(request)).impacts, {
        NovelReaderPreferenceImpact.relayout,
      });
      expect(analyzer.compare(_prefs(request), _prefs(request)).impacts, {
        NovelReaderPreferenceImpact.none,
      });
    },
  );
  test('all modes and scopes survive a reconstructed repository', () async {
    for (final scope in NovelReaderStyleScope.values) {
      for (final mode in NovelReaderTextAlignMode.values) {
        final requested = _prefs(
          NovelReaderTextAlignment(mode: mode, scope: scope),
        );
        await _repository().save(requested);
        expect(await _repository().load(), requested);
      }
    }
  });
  test('old transient root alignment is not migrated into a new request', () {
    final raw = jsonDecode(_codec.encode(_prefs(null))) as Map;
    raw['textAlign'] = 'end';
    final loaded = _codec.decode(jsonEncode(raw));
    expect(loaded.textAlign, NovelReaderTextAlignMode.start);
    expect(loaded.typography, _other);
    final encoded = jsonDecode(_codec.encode(loaded)) as Map;
    expect(encoded, isNot(contains('textAlign')));
    expect(encoded['typography'] as Map, isNot(contains('textAlignment')));
  });
  test(
    'reset preserves extensions idempotently and leaves other requests active',
    () {
      final raw = jsonDecode(
        _codec.encode(
          _prefs(
            const NovelReaderTextAlignment(mode: NovelReaderTextAlignMode.end),
          ),
        ),
      ) as Map;
      final typography = raw['typography'] as Map;
      (typography['textAlignment'] as Map)['extension'] = [1, null, 'keep'];
      typography['futureSetting'] = {'opaque': true};
      final source = jsonEncode(raw);
      final loaded = _codec.decode(source);
      final edited = _codec.encode(
        loaded.copyWith(fontSize: 24),
        previousSource: source,
      );
      final reset = _codec.encode(
        loaded.copyWith(typography: _other),
        previousSource: edited,
      );
      final result = (jsonDecode(reset) as Map)['typography'] as Map;
      expect(result['textAlignment'], {
        'value': 'end',
        'scope': 'forceBody',
        'enabled': false,
        'extension': [1, null, 'keep'],
      });
      expect(result['futureSetting'], {'opaque': true});
      expect(_codec.decode(reset).typography, _other);
      expect(
        jsonDecode(_codec.encode(_codec.decode(reset), previousSource: reset)),
        jsonDecode(reset),
      );
      final clean = _codec.encode(_prefs(null));
      expect(
        (jsonDecode(clean) as Map)['typography'] as Map,
        isNot(contains('textAlignment')),
      );
    },
  );
  for (final unknown in [
    {'value': 'future', 'scope': 'forceBody'},
    {'value': 'end', 'scope': 'future'},
    {'value': 'end', 'scope': 'forceBody', 'enabled': 'future'},
    {'value': 3, 'scope': 'forceBody'},
    {'scope': 'forceBody'},
    'futureFormat',
  ]) {
    test(
      'unknown format refuses unrelated save and reset without altering bytes: $unknown',
      () async {
        final storage = await SharedPreferences.getInstance();
        final raw = jsonDecode(_codec.encode(_prefs(null))) as Map;
        (raw['typography'] as Map)['textAlignment'] = unknown;
        final source = ' ${jsonEncode(raw)} ';
        await storage.setString(
          PreferenceKeys.novelReaderSnapshotV1.name,
          source,
        );
        final loaded = await _repository().load();
        expect(loaded.typography, _other);
        for (final next in [
          loaded.copyWith(fontSize: 24),
          _prefs(null),
          _prefs(
            const NovelReaderTextAlignment(
              mode: NovelReaderTextAlignMode.start,
            ),
          ),
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
      },
    );
  }
  test('the write boundary rechecks a late format change', () async {
    final repo = _repository();
    await repo.save(
      _prefs(
        const NovelReaderTextAlignment(mode: NovelReaderTextAlignMode.end),
      ),
    );
    final loaded = await repo.load();
    final raw = jsonDecode(_codec.encode(loaded)) as Map;
    ((raw['typography'] as Map)['textAlignment'] as Map)['value'] = 'future';
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

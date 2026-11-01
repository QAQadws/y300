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
  fontSizeScope: NovelReaderStyleScope.forceBody,
  lineHeightScope: NovelReaderStyleScope.asDefault,
);
NovelReaderPreferences _prefs(NovelReaderFontWeight? weight) =>
    NovelReaderPreferences.defaults().copyWith(
      typography: _other.withFontWeight(weight),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'sparse inheritance and field-local edits retain independent requests',
    () {
      const request = NovelReaderFontWeight(
        value: 400,
        scope: NovelReaderStyleScope.asDefault,
      );
      final value = _other.withFontWeight(request);
      expect(const NovelReaderTypographyOverrides().over(value), value);
      expect(value.withFontWeight(null), _other);
      for (final edited in [
        value.withFirstLineIndent(null),
        value.withParagraphSpacing(null),
        value.withLetterSpacing(null),
        value.withWordSpacing(null),
        value.withFontSizeScope(null),
        value.withLineHeightScope(null),
      ]) {
        expect(edited.fontWeight, request);
      }
      expect(
        const NovelReaderTypographyOverrides(fontWeight: request).isEmpty,
        false,
      );
      const analyzer = DefaultNovelReaderPreferenceImpactAnalyzer();
      expect(analyzer.compare(_prefs(null), _prefs(request)).impacts, {
        NovelReaderPreferenceImpact.relayout,
      });
      expect(analyzer.compare(_prefs(request), _prefs(request)).impacts, {
        NovelReaderPreferenceImpact.none,
      });
      final raw = jsonDecode(_codec.encode(_prefs(null))) as Map;
      expect(raw['typography'] as Map, isNot(contains('fontWeight')));
      expect(raw, isNot(contains('fontWeight')));
    },
  );
  test(
    'all supported weights/scopes survive repository reconstruction',
    () async {
      for (final scope in NovelReaderStyleScope.values) {
        for (var weight = 100; weight <= 800; weight += 100) {
          final requested = _prefs(
            NovelReaderFontWeight(value: weight, scope: scope),
          );
          await _repository().save(requested);
          expect(await _repository().load(), requested);
        }
      }
    },
  );
  test('invalid and fractional weights never become accepted requests', () {
    for (final number in [0, 99, 550, 900, 1000]) {
      expect(
        _codec
            .normalize(_prefs(NovelReaderFontWeight(value: number)))
            .typography,
        _other,
      );
    }
    for (final number in [0, 550, 400.5, 900, '700', null]) {
      final raw = jsonDecode(
        _codec.encode(_prefs(const NovelReaderFontWeight(value: 700))),
      ) as Map;
      ((raw['typography'] as Map)['fontWeight'] as Map)['value'] = number;
      expect(_codec.decode(jsonEncode(raw)).typography, _other);
    }
  });
  test('reset retains extensions and becomes idempotently inactive', () {
    final raw = jsonDecode(
      _codec.encode(_prefs(const NovelReaderFontWeight(value: 700))),
    ) as Map;
    final typography = raw['typography'] as Map;
    (typography['fontWeight'] as Map)['extension'] = [1, null, 'keep'];
    typography['futureSetting'] = {'opaque': true};
    final source = jsonEncode(raw);
    final edited = _codec.encode(
      _codec.decode(source).copyWith(fontSize: 24),
      previousSource: source,
    );
    final reset = _codec.encode(
      _codec.decode(edited).copyWith(typography: _other),
      previousSource: edited,
    );
    final result = (jsonDecode(reset) as Map)['typography'] as Map;
    expect(result['fontWeight'], {
      'unit': 'cssWeight',
      'value': 700,
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
    expect((_codec.decode(edited)).typography.fontWeight!.value, 700);
  });
  for (final unknown in [
    {'unit': 'axis', 'value': 700, 'scope': 'forceBody'},
    {'unit': 'cssWeight', 'value': 700, 'scope': 'future'},
    {
      'unit': 'cssWeight',
      'value': 700,
      'scope': 'forceBody',
      'enabled': 'future',
    },
    'futureFormat',
  ]) {
    test(
      'unknown request rejects writes without changing raw bytes: $unknown',
      () async {
        final storage = await SharedPreferences.getInstance();
        final raw = jsonDecode(_codec.encode(_prefs(null))) as Map;
        (raw['typography'] as Map)['fontWeight'] = unknown;
        final source = ' ${jsonEncode(raw)} ';
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
      },
    );
  }
  test(
    'a late format change is rechecked by the same repository writer',
    () async {
      final repo = _repository();
      await repo.save(_prefs(const NovelReaderFontWeight(value: 700)));
      final loaded = await repo.load();
      final raw = jsonDecode(_codec.encode(loaded)) as Map;
      ((raw['typography'] as Map)['fontWeight'] as Map)['unit'] = 'future';
      final source = jsonEncode(raw);
      final storage = await SharedPreferences.getInstance();
      await storage.setString(
        PreferenceKeys.novelReaderSnapshotV1.name,
        source,
      );
      await expectLater(
        repo.save(loaded),
        throwsA(isA<NovelReaderPreferencesUnsupportedSnapshot>()),
      );
      expect(
        storage.getString(PreferenceKeys.novelReaderSnapshotV1.name),
        source,
      );
    },
  );
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

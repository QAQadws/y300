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
const _indent = NovelReaderFirstLineIndent(em: 1.5);
NovelReaderPreferences _prefs(NovelReaderParagraphSpacing? request) =>
    NovelReaderPreferences.defaults().copyWith(
      typography: NovelReaderTypographyOverrides(
        firstLineIndent: _indent,
        paragraphSpacing: request,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('absence retains old after-only semantics; explicit zero is sparse', () {
    final legacy = NovelReaderPreferences.defaults().copyWith(
      paragraphSpacing: 17,
    );
    expect(legacy.effectiveParagraphSpacing, (
      before: 0.0,
      after: 17.0,
      scope: NovelReaderStyleScope.asDefault,
    ));
    expect(_codec.decode(_codec.encode(legacy)).paragraphSpacing, 10);
    const zero = NovelReaderParagraphSpacing(before: 0, after: 0);
    final base = _prefs(zero).typography;
    expect(const NovelReaderTypographyOverrides().over(base), base);
    expect(base.withParagraphSpacing(null).firstLineIndent, _indent);
    expect(base.withFirstLineIndent(null).paragraphSpacing, zero);
    expect(_prefs(null).typography, isNot(_prefs(zero).typography));
    const analyzer = DefaultNovelReaderPreferenceImpactAnalyzer();
    expect(
      analyzer
          .compare(
            _prefs(null),
            _prefs(
              const NovelReaderParagraphSpacing(
                before: 0,
                after: 10,
                scope: NovelReaderStyleScope.asDefault,
              ),
            ),
          )
          .impacts,
      {NovelReaderPreferenceImpact.none},
    );
    expect(analyzer.compare(_prefs(null), _prefs(zero)).impacts, {
      NovelReaderPreferenceImpact.relayout,
    });
  });
  test(
    'each scope and boundary roundtrips without losing indent or old fields',
    () async {
      for (final scope in NovelReaderStyleScope.values) {
        for (final pair in [(0.0, 0.0), (12.5, 31.0), (64.0, 64.0)]) {
          final requested =
              _prefs(
                NovelReaderParagraphSpacing(
                  before: pair.$1,
                  after: pair.$2,
                  scope: scope,
                ),
              ).copyWith(
                fontSize: 23,
                themePreset: NovelReaderThemePreset.sepia,
                safeAreaEnabled: false,
              );
          await _repository().save(requested);
          expect(await _repository().load(), requested);
        }
      }
    },
  );
  test('invalid spacing only drops its own request', () {
    for (final bad in [-1.0, 64.1, double.nan, double.infinity]) {
      for (final pair in [(bad, 10.0), (0.0, bad)]) {
        final normalized = _codec.normalize(
          _prefs(NovelReaderParagraphSpacing(before: pair.$1, after: pair.$2)),
        );
        expect(normalized.typography.firstLineIndent, _indent);
        expect(normalized.typography.paragraphSpacing, isNull);
      }
    }
    final normalized = _codec.normalize(
      _prefs(const NovelReaderParagraphSpacing(before: 8, after: 14)).copyWith(
        typography:
            _prefs(const NovelReaderParagraphSpacing(before: 8, after: 14))
                .typography
                .withFirstLineIndent(const NovelReaderFirstLineIndent(em: -1)),
      ),
    );
    expect(normalized.typography.firstLineIndent, isNull);
    expect(normalized.typography.paragraphSpacing!.before, 8);
  });
  test(
    'nested extensions survive font edit and a field-local idempotent reset',
    () {
      final input = _codec.encode(
        _prefs(const NovelReaderParagraphSpacing(before: 12, after: 31)),
      );
      final raw = jsonDecode(input) as Map<String, dynamic>;
      final namespace = raw['typography'] as Map<String, dynamic>;
      (namespace['paragraphSpacing'] as Map)['extension'] = {
        'opaque': [1, null],
      };
      namespace['futureSetting'] = 'keep';
      final source = jsonEncode(raw);
      final loaded = _codec.decode(source);
      final edited = _codec.encode(
        loaded.copyWith(fontSize: 24),
        previousSource: source,
      );
      final reset = _codec.encode(
        loaded.copyWith(
          typography: loaded.typography.withParagraphSpacing(null),
        ),
        previousSource: edited,
      );
      final after = (jsonDecode(reset) as Map)['typography'] as Map;
      expect(after['futureSetting'], 'keep');
      expect((after['paragraphSpacing'] as Map)['enabled'], isFalse);
      expect((after['paragraphSpacing'] as Map)['extension'], {
        'opaque': [1, null],
      });
      expect(_codec.decode(reset).typography.firstLineIndent, _indent);
      expect(_codec.decode(reset).typography.paragraphSpacing, isNull);
      expect(
        jsonDecode(_codec.encode(_codec.decode(reset), previousSource: reset)),
        jsonDecode(reset),
      );
    },
  );
  for (final unknown in [
    {'unit': 'em', 'before': 1, 'after': 2, 'scope': 'forceBody'},
    {'unit': 'logicalPixels', 'before': 1, 'after': 2, 'scope': 'future'},
    {
      'unit': 'logicalPixels',
      'before': 1,
      'after': 2,
      'scope': 'forceBody',
      'enabled': 'future',
    },
    'futureFormat',
  ]) {
    test(
      'future spacing is read-only even when saving another valid field: $unknown',
      () async {
        final source =
            ' ${jsonEncode({
              'schemaVersion': 1,
              'typography': {
                'schemaVersion': 1,
                'paragraphSpacing': unknown,
                'firstLineIndent': {'unit': 'em', 'value': 1.5, 'scope': 'forceBody'},
              },
            })} ';
        final storage = await SharedPreferences.getInstance();
        await storage.setString(
          PreferenceKeys.novelReaderSnapshotV1.name,
          source,
        );
        final loaded = await _repository().load();
        expect(loaded.typography.firstLineIndent, _indent);
        expect(loaded.typography.paragraphSpacing, isNull);
        await expectLater(
          _repository().save(loaded.copyWith(fontSize: 24)),
          throwsA(isA<NovelReaderPreferencesUnsupportedSnapshot>()),
        );
        expect(
          storage.getString(PreferenceKeys.novelReaderSnapshotV1.name),
          source,
        );
        expect(
          storage.containsKey(PreferenceKeys.novelReaderMigrationVersion.name),
          isFalse,
        );
      },
    );
  }
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

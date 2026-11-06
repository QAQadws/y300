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

const codec = NovelReaderPreferencesSnapshotCodec();
NovelReaderPreferences prefs(NovelReaderFirstLineIndent? indent) =>
    NovelReaderPreferences.defaults().copyWith(
      typography: NovelReaderTypographyOverrides(firstLineIndent: indent),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('role sizes merge independently, validate and retain unknown keys', () async {
    const global = NovelReaderTypographyOverrides(
      roleFontSizes: NovelReaderRoleFontSizes(
        heading: 150,
        quote: 75,
        code: 115,
      ),
    );
    const work = NovelReaderTypographyOverrides(
      roleFontSizes: NovelReaderRoleFontSizes(quote: 100),
    );
    expect(
      work.over(global).roleFontSizes,
      const NovelReaderRoleFontSizes(heading: 150, quote: 100, code: 115),
    );
    final value = prefs(null).copyWith(typography: work.over(global));
    await _repository().save(value);
    expect(await _repository().load(), value);
    const source =
        '{"schemaVersion":1,"typography":{"schemaVersion":1,'
        '"roleFontSizes":{"heading":145,"quote":70,"code":103,"future":"keep"}}}';
    final decoded = codec.decode(source);
    expect(
      decoded.typography.roleFontSizes,
      const NovelReaderRoleFontSizes(heading: 145),
    );
    final reset = decoded.copyWith(
      typography: decoded.typography.withRoleFontSizes(
        const NovelReaderRoleFontSizes(),
      ),
    );
    final saved =
        jsonDecode(codec.encode(reset, previousSource: source)) as Map;
    expect((saved['typography'] as Map)['roleFontSizes'], {'future': 'keep'});
    expect(
      jsonDecode(codec.encode(prefs(null))) as Map,
      isNot(contains('typography')),
    );
  });

  test('empty scope, explicit zero and author reset remain distinct', () {
    const global = NovelReaderTypographyOverrides(
      firstLineIndent: NovelReaderFirstLineIndent(em: 2),
    );
    const empty = NovelReaderTypographyOverrides();
    const author = NovelReaderTypographyOverrides(
      firstLineIndent: NovelReaderFirstLineIndent.followAuthor(),
    );
    expect(empty.over(global), global);
    expect(author.over(global), author);
    expect(author, isNot(empty));
    expect(
      prefs(null).effectiveFirstLineIndent,
      prefs(const NovelReaderFirstLineIndent.followAuthor())
          .effectiveFirstLineIndent,
    );
    const analyzer = DefaultNovelReaderPreferenceImpactAnalyzer();
    expect(
      analyzer
          .compare(
            prefs(null),
            prefs(const NovelReaderFirstLineIndent.followAuthor()),
          )
          .impacts,
      {NovelReaderPreferenceImpact.none},
    );
    expect(
      analyzer
          .compare(prefs(null), prefs(const NovelReaderFirstLineIndent(em: 0)))
          .impacts,
      {NovelReaderPreferenceImpact.relayout},
    );
    expect(
      analyzer
          .compare(prefs(null), prefs(const NovelReaderFirstLineIndent(em: 2)))
          .impacts,
      {NovelReaderPreferenceImpact.relayout},
    );
  });

  test(
    'all legal scopes and zero em survive a fresh codec and repository',
    () async {
      for (final scope in NovelReaderStyleScope.values) {
        for (final amount in [0.0, 1.25, 4.0]) {
          final value = prefs(
            NovelReaderFirstLineIndent(em: amount, scope: scope),
          );
          final repo = _repository();
          await repo.save(value);
          expect(await _repository().load(), value);
          final storage = await SharedPreferences.getInstance();
          final raw = jsonDecode(
            storage.getString(PreferenceKeys.novelReaderSnapshotV1.name)!,
          ) as Map;
          final indent = (raw['typography'] as Map)['firstLineIndent'] as Map;
          expect(indent['unit'], 'em');
          expect(indent['value'], amount);
          expect(indent['enabled'], isTrue);
        }
      }
    },
  );

  test('legacy pixels never become em or silently create a namespace', () {
    final legacy = NovelReaderPreferences.defaults().copyWith(
      firstLineIndent: 32,
    );
    expect(
      legacy.effectiveFirstLineIndent.unit,
      NovelReaderIndentUnit.logicalPixels,
    );
    final encoded = codec.encode(legacy);
    expect((jsonDecode(encoded) as Map).containsKey('typography'), isFalse);
    expect(codec.decode(encoded).firstLineIndent, 0);
    for (final invalid in [-1.0, 4.25, double.nan, double.infinity]) {
      expect(
        codec
            .normalize(prefs(NovelReaderFirstLineIndent(em: invalid)))
            .typography
            .isEmpty,
        isTrue,
      );
    }
  });

  test('namespace and setting extensions survive unrelated edits and reset idempotently', () {
    final source = jsonEncode({
      'schemaVersion': 1,
      'fontSize': 21,
      'unknownRoot': {
        'v': [1, null],
      },
      'typography': {
        'schemaVersion': 1,
        'futureParagraph': {'x': true},
        'firstLineIndent': {
          'enabled': true,
          'unit': 'em',
          'value': 1.25,
          'scope': 'forceBody',
          'extension': {
            'preserve': [1, 'opaque'],
          },
        },
      },
    });
    final loaded = codec.decode(source);
    final fontEdit = codec.encode(
      loaded.copyWith(fontSize: 22),
      previousSource: source,
    );
    final reset = codec.encode(
      loaded.copyWith(typography: const NovelReaderTypographyOverrides()),
      previousSource: fontEdit,
    );
    final raw = jsonDecode(reset) as Map;
    final typography = raw['typography'] as Map;
    expect(raw['unknownRoot'], {
      'v': [1, null],
    });
    expect(typography['futureParagraph'], {'x': true});
    final indent = typography['firstLineIndent'] as Map;
    expect(indent['extension'], {
      'preserve': [1, 'opaque'],
    });
    expect(indent['enabled'], isFalse);
    expect(codec.decode(reset).typography.isEmpty, isTrue);
    final again = codec.encode(codec.decode(reset), previousSource: reset);
    expect(jsonDecode(again), raw);
    final plain = codec.encode(
      prefs(null),
      previousSource: codec.encode(
        prefs(const NovelReaderFirstLineIndent(em: 2)),
      ),
    );
    expect((jsonDecode(plain) as Map).containsKey('typography'), isFalse);
  });

  for (final typography in [
    {'schemaVersion': 9, 'opaque': 'preserve'},
    {
      'schemaVersion': 1,
      'firstLineIndent': {
        'unit': 'characters',
        'value': 2,
        'scope': 'forceBody',
      },
    },
    {
      'schemaVersion': 1,
      'firstLineIndent': {'unit': 'em', 'value': 2, 'scope': 'futureScope'},
    },
    {'schemaVersion': 1, 'firstLineIndent': 'futureFormat'},
  ]) {
    test(
      'future typography stays byte-exact through load and rejected write: $typography',
      () async {
        final source =
            ' ${jsonEncode({'schemaVersion': 1, 'fontSize': 24, 'typography': typography})} ';
        final storage = await SharedPreferences.getInstance();
        await storage.setString(
          PreferenceKeys.novelReaderSnapshotV1.name,
          source,
        );
        final repo = _repository();
        final loaded = await repo.load();
        expect(loaded.fontSize, 24);
        expect(loaded.typography.isEmpty, isTrue);
        await expectLater(
          repo.save(loaded.copyWith(fontSize: 22)),
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

  test('a schema upgrade after load is rechecked before any write', () async {
    final repo = _repository();
    final loaded = await repo.load();
    final storage = await SharedPreferences.getInstance();
    const upgraded =
        '{"schemaVersion":1,"typography":{"schemaVersion":2,"opaque":null}}';
    await storage.setString(
      PreferenceKeys.novelReaderSnapshotV1.name,
      upgraded,
    );
    await expectLater(
      repo.save(loaded),
      throwsA(isA<NovelReaderPreferencesUnsupportedSnapshot>()),
    );
    expect(
      storage.getString(PreferenceKeys.novelReaderSnapshotV1.name),
      upgraded,
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

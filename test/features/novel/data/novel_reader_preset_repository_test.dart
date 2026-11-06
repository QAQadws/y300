import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/novel/data/preferences/novel_reader_preferences_snapshot_codec.dart';
import 'package:y300/features/novel/data/preferences/shared_preferences_novel_reader_preset_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/repositories/novel_reader_preferences_repository.dart';

const _key = PreferenceKeys.novelReaderPresetsV1;
final _defaults = NovelReaderPreferences.defaults();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'save, rename and reset keep identity and use the normalized snapshot',
    () async {
      final repo = SharedPreferencesNovelReaderPresetRepository(
        SharedPreferencesStore(),
      );
      final font = 'a' * 64;
      final draft = _defaults.copyWith(
        fontSize: 25,
        fontFamily: font,
        showRubyAnnotations: false,
        viewport: const NovelReaderViewportOverrides(left: 0, right: 22),
        typography: const NovelReaderTypographyOverrides(
          roleFontSizes: NovelReaderRoleFontSizes(ruby: 135),
        ),
      );
      final saved = (await repo.save('  Study  ', draft)).single;
      expect(saved.name, 'Study');
      expect(saved.preferences, draft);
      final renamed = (await repo.rename(saved.id, 'Evening')).single;
      expect(renamed.id, saved.id);
      expect(renamed.name, 'Evening');
      expect(renamed.preferences!.fontFamily, font);
      final reset = (await repo.reset(saved.id)).single;
      expect(reset.id, saved.id);
      expect(reset.name, 'Evening');
      expect(reset.preferences, _defaults);

      final portable = (await repo.save(
        'Portable',
        draft.copyWith(fontFamily: r'E:\fonts\reading.ttf'),
      )).first;
      expect(portable.preferences!.fontFamily, 'system');
      final raw = (await SharedPreferences.getInstance()).getString(_key.name)!;
      expect(raw, isNot(contains('reading.ttf')));
    },
  );

  test(
    'future entries and known extensions survive unrelated edits and reset',
    () async {
      final settings = jsonDecode(
        const NovelReaderPreferencesSnapshotCodec().encode(
          _defaults.copyWith(fontSize: 22),
        ),
      ) as Map;
      settings['futureSetting'] = {
        'payload': [1, 2],
      };
      final store = SharedPreferencesStore();
      await store.write(
        _key,
        jsonEncode({
          'schemaVersion': 1,
          'libraryExtension': 'keep',
          'presets': {
            'known': {
              'name': 'Known',
              'settings': settings,
              'rowExtension': true,
            },
            'future': {
              'name': 'Future',
              'settings': {
                'schemaVersion': 2,
                'opaque': ['keep'],
              },
            },
            'opaque': ['unreadable'],
          },
        }),
      );
      final repo = SharedPreferencesNovelReaderPresetRepository(store);
      final values = await repo.load();
      expect(
        values
            .singleWhere((value) => value.id == 'known')
            .preferences!
            .fontSize,
        22,
      );
      expect(
        values.singleWhere((value) => value.id == 'future').preferences,
        isNull,
      );
      await expectLater(
        repo.reset('future'),
        throwsA(isA<NovelReaderPreferencesUnsupportedSnapshot>()),
      );
      await Future.wait([
        repo.rename('future', 'Future renamed'),
        repo.reset('known'),
        repo.save('New', _defaults),
      ]);
      final raw = jsonDecode((await store.read(_key))!) as Map;
      final entries = raw['presets'] as Map;
      expect(raw['libraryExtension'], 'keep');
      expect(entries['opaque'], ['unreadable']);
      expect(entries['future'], {
        'name': 'Future renamed',
        'settings': {
          'schemaVersion': 2,
          'opaque': ['keep'],
        },
      });
      expect(entries['known']['rowExtension'], isTrue);
      expect(entries['known']['settings']['fontSize'], _defaults.fontSize);
      expect(entries['known']['settings']['futureSetting'], {
        'payload': [1, 2],
      });
      expect(await repo.load(), hasLength(3));
    },
  );

  test('future library stays byte-for-byte read-only', () async {
    const raw = '{"schemaVersion":2,"presets":{"new":"opaque"}}';
    final store = SharedPreferencesStore();
    await store.write(_key, raw);
    final repo = SharedPreferencesNovelReaderPresetRepository(store);
    await expectLater(
      repo.load(),
      throwsA(isA<NovelReaderPreferencesUnsupportedSnapshot>()),
    );
    await expectLater(
      repo.save('Name', _defaults),
      throwsA(isA<NovelReaderPreferencesUnsupportedSnapshot>()),
    );
    expect(await store.read(_key), raw);
  });
}

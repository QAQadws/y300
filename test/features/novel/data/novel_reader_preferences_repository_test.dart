import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/novel/data/preferences/novel_reader_preferences_legacy_source.dart';
import 'package:y300/features/novel/data/preferences/novel_reader_preferences_snapshot_codec.dart';
import 'package:y300/features/novel/data/preferences/shared_preferences_novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeLegacySource legacySource;
  late SharedPreferencesNovelReaderPreferencesRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    legacySource = _FakeLegacySource();
    repository = SharedPreferencesNovelReaderPreferencesRepository(
      preferencesStore: SharedPreferencesStore(),
      legacySource: legacySource,
    );
  });

  test('uses the novel baseline when neither storage has a value', () async {
    final loaded = await repository.load();

    expect(loaded, NovelReaderPreferences.defaults());
    expect(loaded.fontSize, 18.5);
    expect(loaded.lineHeight, 1.6);
    expect(loaded.themePreset, NovelReaderThemePreset.sepia);
    expect(legacySource.callCount, 1);
  });

  test('first load migrates only supported valid SQLite fields', () async {
    legacySource.value = NovelReaderPreferences.defaults().copyWith(
      fontSize: 21,
      lineHeight: 1.85,
      themePreset: NovelReaderThemePreset.dark,
      conversionMode: NovelReaderConversionMode.toTraditional,
      flowMode: NovelReaderFlowMode.pagedRtl,
      paragraphSpacing: 42,
    );

    final loaded = await repository.load();
    final preferences = await SharedPreferences.getInstance();
    final snapshot =
        jsonDecode(
              preferences.getString(PreferenceKeys.novelReaderSnapshotV1.name)!,
            )
            as Map<String, dynamic>;

    expect(loaded.fontSize, 21);
    expect(loaded.lineHeight, 1.85);
    expect(loaded.themePreset, NovelReaderThemePreset.dark);
    expect(loaded.conversionMode, NovelReaderConversionMode.toTraditional);
    expect(loaded.flowMode, NovelReaderFlowMode.vertical);
    expect(loaded.paragraphSpacing, 10);
    expect(snapshot.keys, <String>{
      'schemaVersion',
      'fontSize',
      'lineHeight',
      'themePreset',
      'conversionMode',
    });
    expect(
      preferences.getInt(PreferenceKeys.novelReaderMigrationVersion.name),
      1,
    );
  });

  test('new snapshot wins without reading stale SQLite', () async {
    await repository.save(
      NovelReaderPreferences.defaults().copyWith(
        fontSize: 22,
        themePreset: NovelReaderThemePreset.light,
      ),
    );
    legacySource.value = NovelReaderPreferences.defaults().copyWith(
      fontSize: 16,
      themePreset: NovelReaderThemePreset.dark,
    );

    final loaded = await repository.load();

    expect(loaded.fontSize, 22);
    expect(loaded.themePreset, NovelReaderThemePreset.light);
    expect(legacySource.callCount, 0);
  });

  test('malformed snapshot falls back without reviving SQLite', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreferenceKeys.novelReaderSnapshotV1.name: '{broken',
    });
    repository = SharedPreferencesNovelReaderPreferencesRepository(
      preferencesStore: SharedPreferencesStore(),
      legacySource: legacySource,
    );
    legacySource.value = NovelReaderPreferences.defaults().copyWith(
      fontSize: 27,
    );

    expect(await repository.load(), NovelReaderPreferences.defaults());
    expect(legacySource.callCount, 0);
  });

  test('legacy source errors fall back to the novel defaults', () async {
    legacySource.error = StateError('database factory is unavailable');

    final loaded = await repository.load();
    final preferences = await SharedPreferences.getInstance();

    expect(loaded, NovelReaderPreferences.defaults());
    expect(legacySource.callCount, 1);
    expect(
      preferences.getInt(PreferenceKeys.novelReaderMigrationVersion.name),
      1,
    );
  });

  test('codec rejects invalid values field by field', () {
    const codec = NovelReaderPreferencesSnapshotCodec();

    final decoded = codec.decode(
      jsonEncode(<String, Object>{
        'schemaVersion': 1,
        'fontSize': 99,
        'lineHeight': 1.9,
        'themePreset': 'future-theme',
        'conversionMode': 'future-conversion',
      }),
    );

    expect(decoded.fontSize, 18.5);
    expect(decoded.lineHeight, 1.9);
    expect(decoded.themePreset, NovelReaderThemePreset.sepia);
    expect(decoded.conversionMode, NovelReaderConversionMode.none);
  });
}

final class _FakeLegacySource implements NovelReaderPreferencesLegacySource {
  NovelReaderPreferences? value;
  Object? error;
  int callCount = 0;

  @override
  Future<NovelReaderPreferences?> load() async {
    callCount += 1;
    if (error != null) {
      throw error!;
    }
    return value;
  }
}

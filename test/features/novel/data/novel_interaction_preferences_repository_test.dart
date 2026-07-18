import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/novel/data/preferences/novel_interaction_preferences_legacy_source.dart';
import 'package:y300/features/novel/data/preferences/shared_preferences_novel_interaction_preferences_repository.dart';
import 'package:y300/features/novel/domain/models/novel_interaction_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory temp;
  late String dbPath;
  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    temp = await Directory.systemTemp.createTemp('y300-novel-interaction-');
    dbPath = p.join(temp.path, 'interaction.db');
    db = await ComicLocalDb.open(databaseName: dbPath);
  });

  tearDown(() async {
    await db.close();
    await deleteDatabase(dbPath);
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  SharedPreferencesNovelInteractionPreferencesRepository createRepository() {
    return SharedPreferencesNovelInteractionPreferencesRepository(
      preferencesStore: SharedPreferencesStore(),
      legacySource: SqliteNovelInteractionPreferencesLegacySource(
        Future<Database>.value(db),
      ),
    );
  }

  test('migrates a valid global SQLite chapter mode once', () async {
    await db.insert(ComicLocalDb.settingsTable, <String, Object?>{
      'key': SqliteNovelInteractionPreferencesLegacySource.chapterOpenModeKey,
      'value': NovelChapterOpenMode.sourcePost.storageValue,
    });

    final repository = createRepository();
    expect(
      await repository.loadChapterOpenMode(),
      NovelChapterOpenMode.sourcePost,
    );

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(PreferenceKeys.novelChapterOpenModeV1.name),
      'sourcePost',
    );
    expect(
      preferences.getInt(
        PreferenceKeys.novelChapterOpenModeMigrationVersion.name,
      ),
      1,
    );
  });

  test('new SharedPreferences value wins over stale SQLite', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreferenceKeys.novelChapterOpenModeV1.name: 'reader',
    });
    await db.insert(ComicLocalDb.settingsTable, <String, Object?>{
      'key': SqliteNovelInteractionPreferencesLegacySource.chapterOpenModeKey,
      'value': 'sourcePost',
    });

    expect(
      await createRepository().loadChapterOpenMode(),
      NovelChapterOpenMode.reader,
    );
  });

  test('save persists only the new device preference', () async {
    final repository = createRepository();

    await repository.saveChapterOpenMode(NovelChapterOpenMode.sourcePost);

    expect(
      await createRepository().loadChapterOpenMode(),
      NovelChapterOpenMode.sourcePost,
    );
    final rows = await db.query(
      ComicLocalDb.settingsTable,
      where: 'key = ?',
      whereArgs: const <Object?>[
        SqliteNovelInteractionPreferencesLegacySource.chapterOpenModeKey,
      ],
    );
    expect(rows, isEmpty);
  });

  test('completed migration does not resurrect a later SQLite value', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreferenceKeys.novelChapterOpenModeMigrationVersion.name: 1,
    });
    await db.insert(ComicLocalDb.settingsTable, <String, Object?>{
      'key': SqliteNovelInteractionPreferencesLegacySource.chapterOpenModeKey,
      'value': 'sourcePost',
    });

    expect(
      await createRepository().loadChapterOpenMode(),
      NovelChapterOpenMode.reader,
    );
  });
}

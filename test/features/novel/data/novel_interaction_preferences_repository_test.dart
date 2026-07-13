import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/novel/data/repositories/sqflite_novel_interaction_preferences_repository.dart';
import 'package:y300/features/novel/domain/models/novel_interaction_models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory temp;
  late String dbPath;
  late Database db;
  late SqfliteNovelInteractionPreferencesRepository repository;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('y300-novel-interaction-');
    dbPath = p.join(temp.path, 'interaction.db');
    db = await ComicLocalDb.open(databaseName: dbPath);
    repository = SqfliteNovelInteractionPreferencesRepository(
      Future<Database>.value(db),
    );
  });

  tearDown(() async {
    await db.close();
    await deleteDatabase(dbPath);
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('defaults to reader and persists one global source-post mode', () async {
    expect(await repository.loadChapterOpenMode(), NovelChapterOpenMode.reader);

    await repository.saveChapterOpenMode(NovelChapterOpenMode.sourcePost);

    final anotherNovelRepository = SqfliteNovelInteractionPreferencesRepository(
      Future<Database>.value(db),
    );
    expect(
      await anotherNovelRepository.loadChapterOpenMode(),
      NovelChapterOpenMode.sourcePost,
    );
    final rows = await db.query(
      ComicLocalDb.settingsTable,
      where: 'key = ?',
      whereArgs: const <Object?>[
        SqfliteNovelInteractionPreferencesRepository.chapterOpenModeKey,
      ],
    );
    expect(rows, hasLength(1));
  });

  test('falls back to reader for an unknown stored value', () async {
    await db.insert(ComicLocalDb.settingsTable, <String, Object?>{
      'key': SqfliteNovelInteractionPreferencesRepository.chapterOpenModeKey,
      'value': 'future-mode',
    });

    expect(await repository.loadChapterOpenMode(), NovelChapterOpenMode.reader);
  });
}

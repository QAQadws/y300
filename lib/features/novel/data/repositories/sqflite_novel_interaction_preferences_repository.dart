import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/novel/domain/models/novel_interaction_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_interaction_preferences_repository.dart';

class SqfliteNovelInteractionPreferencesRepository
    implements NovelInteractionPreferencesRepository {
  const SqfliteNovelInteractionPreferencesRepository(this._dbFuture);

  static const String chapterOpenModeKey = 'novel_chapter_open_mode';

  final Future<Database> _dbFuture;

  @override
  Future<NovelChapterOpenMode> loadChapterOpenMode() async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.settingsTable,
      columns: const <String>['value'],
      where: 'key = ?',
      whereArgs: const <Object?>[chapterOpenModeKey],
      limit: 1,
    );
    final value = rows.isEmpty ? null : rows.single['value'] as String?;
    return NovelChapterOpenModeCodec.fromStorage(value);
  }

  @override
  Future<void> saveChapterOpenMode(NovelChapterOpenMode mode) async {
    final db = await _dbFuture;
    await db.rawInsert(
      '''
      INSERT INTO ${ComicLocalDb.settingsTable} (key, value)
      VALUES (?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
      ''',
      <Object?>[chapterOpenModeKey, mode.storageValue],
    );
  }
}

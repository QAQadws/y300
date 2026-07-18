import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/novel/domain/models/novel_interaction_models.dart';

abstract interface class NovelInteractionPreferencesLegacySource {
  Future<NovelChapterOpenMode?> loadChapterOpenMode();
}

final class SqliteNovelInteractionPreferencesLegacySource
    implements NovelInteractionPreferencesLegacySource {
  SqliteNovelInteractionPreferencesLegacySource(this._dbFuture);

  static const String chapterOpenModeKey = 'novel_chapter_open_mode';

  final Future<Database> _dbFuture;

  @override
  Future<NovelChapterOpenMode?> loadChapterOpenMode() async {
    try {
      final db = await _dbFuture;
      final rows = await db.query(
        ComicLocalDb.settingsTable,
        columns: const <String>['value'],
        where: 'key = ?',
        whereArgs: const <Object?>[chapterOpenModeKey],
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      final raw = rows.single['value'];
      if (raw == NovelChapterOpenMode.reader.storageValue) {
        return NovelChapterOpenMode.reader;
      }
      if (raw == NovelChapterOpenMode.sourcePost.storageValue) {
        return NovelChapterOpenMode.sourcePost;
      }
      return NovelChapterOpenMode.reader;
    } on DatabaseException {
      return null;
    }
  }
}

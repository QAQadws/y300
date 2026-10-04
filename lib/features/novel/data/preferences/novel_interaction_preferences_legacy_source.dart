import 'package:sqflite/sqflite.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/novel/domain/models/novel_interaction_models.dart';

abstract interface class NovelInteractionPreferencesLegacySource {
  Future<NovelChapterOpenMode?> loadChapterOpenMode();
}

final class SqliteNovelInteractionPreferencesLegacySource
    implements NovelInteractionPreferencesLegacySource {
  SqliteNovelInteractionPreferencesLegacySource(this._dbFutureFactory);

  static const String chapterOpenModeKey = 'novel_chapter_open_mode';

  final Future<Database> Function() _dbFutureFactory;

  @override
  Future<NovelChapterOpenMode?> loadChapterOpenMode() async {
    try {
      final db = await _dbFutureFactory();
      final rows = await db.query(
        AppDatabase.settingsTable,
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
    } catch (_) {
      return null;
    }
  }
}

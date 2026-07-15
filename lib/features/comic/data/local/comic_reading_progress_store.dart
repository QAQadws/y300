import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';

class ComicReadingProgressStore {
  ComicReadingProgressStore(this._dbFuture);

  final Future<Database> _dbFuture;

  Future<void> updateLastReadProgress({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
  }) async {
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.insert(
        ComicLocalDb.readingProgressTable,
        <String, Object?>{
          'comic_id': comicId,
          'episode_id': episodeId,
          'image_index': imageIndex,
          'scroll_offset': scrollOffset,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.update(
        ComicLocalDb.comicsTable,
        <String, Object?>{'last_read_episode_id': episodeId, 'updated_at': now},
        where: 'comic_id = ?',
        whereArgs: <Object>[comicId],
      );
    });
  }

  Future<ComicReadingProgress?> getLastReadProgress({
    required String comicId,
  }) async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.readingProgressTable,
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
      orderBy: 'updated_at DESC, rowid DESC',
      limit: 1,
    );

    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<ComicReadingProgress?> getReadingProgressForEpisode({
    required String comicId,
    required String episodeId,
  }) async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.readingProgressTable,
      where: 'comic_id = ? AND episode_id = ?',
      whereArgs: <Object>[comicId, episodeId],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<List<ComicReadingProgress>> getReadingProgresses({
    required String comicId,
  }) async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.readingProgressTable,
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
      orderBy: 'updated_at DESC, rowid DESC',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  ComicReadingProgress _fromRow(Map<String, Object?> row) {
    return ComicReadingProgress(
      comicId: row['comic_id'] as String,
      episodeId: row['episode_id'] as String,
      imageIndex: row['image_index'] as int,
      scrollOffset: (row['scroll_offset'] as num).toDouble(),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }
}

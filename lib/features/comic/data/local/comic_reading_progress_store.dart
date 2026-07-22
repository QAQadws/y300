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

  Future<void> clearReadingProgress({
    required String comicId,
    required String episodeId,
  }) async {
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final comicRows = await txn.query(
        ComicLocalDb.comicsTable,
        columns: <String>['last_read_episode_id'],
        where: 'comic_id = ?',
        whereArgs: <Object>[comicId],
        limit: 1,
      );
      final shouldReplaceLastReadEpisode =
          comicRows.isNotEmpty &&
          comicRows.first['last_read_episode_id'] == episodeId;

      await txn.delete(
        ComicLocalDb.readingProgressTable,
        where: 'comic_id = ? AND episode_id = ?',
        whereArgs: <Object>[comicId, episodeId],
      );

      if (!shouldReplaceLastReadEpisode) {
        return;
      }

      final latestProgressRows = await txn.query(
        ComicLocalDb.readingProgressTable,
        columns: <String>['episode_id'],
        where: 'comic_id = ?',
        whereArgs: <Object>[comicId],
        orderBy: 'updated_at DESC, rowid DESC',
        limit: 1,
      );
      final replacementEpisodeId = latestProgressRows.isEmpty
          ? null
          : latestProgressRows.first['episode_id'] as String?;
      await txn.update(
        ComicLocalDb.comicsTable,
        <String, Object?>{
          'last_read_episode_id': replacementEpisodeId,
          'updated_at': now,
        },
        where: 'comic_id = ?',
        whereArgs: <Object>[comicId],
      );
    });
  }

  Future<void> resetComicReadingState({required String comicId}) async {
    final db = await _dbFuture;
    await db.transaction((txn) async {
      await txn.update(
        ComicLocalDb.libraryEpisodeStateTable,
        <String, Object?>{'is_read': 0, 'read_at': null},
        where: 'content_type = ? AND work_id = ?',
        whereArgs: <Object>['comic', comicId],
      );
      await txn.rawInsert(
        '''
        INSERT OR REPLACE INTO ${ComicLocalDb.libraryEpisodeStateTable} (
          content_type,
          episode_id,
          work_id,
          is_read,
          is_downloaded,
          is_bookmarked,
          read_at,
          downloaded_at
        )
        SELECT
          'comic',
          episode.episode_id,
          episode.comic_id,
          0,
          COALESCE(state.is_downloaded, 0),
          COALESCE(state.is_bookmarked, 0),
          NULL,
          state.downloaded_at
        FROM ${ComicLocalDb.episodesTable} episode
        LEFT JOIN ${ComicLocalDb.libraryEpisodeStateTable} state
          ON state.content_type = 'comic'
         AND state.episode_id = episode.episode_id
        WHERE episode.comic_id = ?
        ''',
        <Object>[comicId],
      );
      await txn.delete(
        ComicLocalDb.readingProgressTable,
        where: 'comic_id = ?',
        whereArgs: <Object>[comicId],
      );
      await txn.update(
        ComicLocalDb.comicsTable,
        <String, Object?>{'last_read_episode_id': null},
        where: 'comic_id = ?',
        whereArgs: <Object>[comicId],
      );
      await txn.update(
        ComicLocalDb.libraryWorkStateTable,
        <String, Object?>{'last_read_episode_id': null, 'last_read_at': null},
        where: 'content_type = ? AND work_id = ?',
        whereArgs: <Object>['comic', comicId],
      );
    });
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

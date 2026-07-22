import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/repositories/comic_download_queue_repository.dart';
import 'package:y300/features/comic/domain/models/comic_download_queue_models.dart';

final class LocalComicDownloadQueueRepository
    implements ComicDownloadQueueRepository {
  LocalComicDownloadQueueRepository.lazy(this._openDb);

  final Future<Database> Function() _openDb;
  Future<Database>? _dbFuture;

  Future<Database> get _db async => _dbFuture ??= _openDb();

  @override
  Future<ComicDownloadRepositoryEnqueueResult> enqueueTargets(
    List<ComicDownloadTarget> targets, {
    required DateTime now,
  }) async {
    final db = await _db;
    return db.transaction((txn) async {
      var enqueued = 0;
      var deduplicated = 0;
      for (final target in targets) {
        final existing = await txn.query(
          ComicLocalDb.comicDownloadQueueTable,
          where: 'comic_id = ? AND episode_id = ?',
          whereArgs: <Object>[target.comicId, target.episodeId],
          orderBy: 'created_at ASC, id ASC',
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final current = _entryFromRow(existing.first);
          if (current.status == ComicDownloadQueueStatus.failed) {
            await txn.update(
              ComicLocalDb.comicDownloadQueueTable,
              <String, Object?>{
                'comic_title': target.comicTitle,
                'episode_title': target.episodeTitle,
                'status': ComicDownloadQueueStatus.pending.dbValue,
                'completed_images': 0,
                'total_images': null,
                'last_error': null,
                'updated_at': _ms(now),
              },
              where: 'id = ?',
              whereArgs: <Object>[current.id],
            );
            enqueued += 1;
          } else {
            deduplicated += 1;
          }
          continue;
        }
        await txn
            .insert(ComicLocalDb.comicDownloadQueueTable, <String, Object?>{
              'comic_id': target.comicId,
              'episode_id': target.episodeId,
              'comic_title': target.comicTitle,
              'episode_title': target.episodeTitle,
              'status': ComicDownloadQueueStatus.pending.dbValue,
              'completed_images': 0,
              'created_at': _ms(now),
              'updated_at': _ms(now),
            });
        enqueued += 1;
      }
      return ComicDownloadRepositoryEnqueueResult(
        enqueuedCount: enqueued,
        deduplicatedCount: deduplicated,
      );
    });
  }

  @override
  Future<void> recoverInterrupted({required DateTime now}) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        ComicLocalDb.comicDownloadQueueTable,
        where: 'status = ?',
        whereArgs: <Object>[ComicDownloadQueueStatus.cancelRequested.dbValue],
      );
      await txn.update(
        ComicLocalDb.comicDownloadQueueTable,
        <String, Object?>{
          'status': ComicDownloadQueueStatus.pending.dbValue,
          'updated_at': _ms(now),
        },
        where: 'status = ?',
        whereArgs: <Object>[ComicDownloadQueueStatus.running.dbValue],
      );
    });
  }

  @override
  Future<ComicDownloadQueueEntry?> claimNext({required DateTime now}) async {
    final db = await _db;
    return db.transaction((txn) async {
      final rows = await txn.query(
        ComicLocalDb.comicDownloadQueueTable,
        where: 'status = ?',
        whereArgs: <Object>[ComicDownloadQueueStatus.pending.dbValue],
        orderBy: 'created_at ASC, id ASC',
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      final id = rows.first['id'] as int;
      await txn.update(
        ComicLocalDb.comicDownloadQueueTable,
        <String, Object?>{
          'status': ComicDownloadQueueStatus.running.dbValue,
          'updated_at': _ms(now),
        },
        where: 'id = ?',
        whereArgs: <Object>[id],
      );
      final claimed = await txn.query(
        ComicLocalDb.comicDownloadQueueTable,
        where: 'id = ?',
        whereArgs: <Object>[id],
        limit: 1,
      );
      return _entryFromRow(claimed.single);
    });
  }

  @override
  Future<List<ComicDownloadQueueEntry>> loadVisibleEntries() async {
    final db = await _db;
    final rows = await db.query(
      ComicLocalDb.comicDownloadQueueTable,
      orderBy:
          "CASE status WHEN 'running' THEN 0 WHEN 'cancel_requested' THEN 0 "
          "WHEN 'pending' THEN 1 ELSE 2 END, created_at ASC, id ASC",
    );
    return rows.map(_entryFromRow).toList(growable: false);
  }

  @override
  Future<ComicDownloadQueueEntry?> getById(int id) async {
    final db = await _db;
    final rows = await db.query(
      ComicLocalDb.comicDownloadQueueTable,
      where: 'id = ?',
      whereArgs: <Object>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : _entryFromRow(rows.single);
  }

  @override
  Future<void> updateProgress({
    required int id,
    required int completedImages,
    required int totalImages,
    required DateTime now,
  }) async {
    final db = await _db;
    await db.update(
      ComicLocalDb.comicDownloadQueueTable,
      <String, Object?>{
        'completed_images': completedImages,
        'total_images': totalImages,
        'updated_at': _ms(now),
      },
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  @override
  Future<void> markFailed({
    required int id,
    required String error,
    required DateTime now,
  }) async {
    final db = await _db;
    await db.update(
      ComicLocalDb.comicDownloadQueueTable,
      <String, Object?>{
        'status': ComicDownloadQueueStatus.failed.dbValue,
        'last_error': error,
        'updated_at': _ms(now),
      },
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  @override
  Future<void> requestCancel({required int id, required DateTime now}) async {
    final db = await _db;
    await db.update(
      ComicLocalDb.comicDownloadQueueTable,
      <String, Object?>{
        'status': ComicDownloadQueueStatus.cancelRequested.dbValue,
        'updated_at': _ms(now),
      },
      where: 'id = ? AND status = ?',
      whereArgs: <Object>[id, ComicDownloadQueueStatus.running.dbValue],
    );
  }

  @override
  Future<void> retry({required int id, required DateTime now}) async {
    final db = await _db;
    await db.update(
      ComicLocalDb.comicDownloadQueueTable,
      <String, Object?>{
        'status': ComicDownloadQueueStatus.pending.dbValue,
        'completed_images': 0,
        'total_images': null,
        'last_error': null,
        'updated_at': _ms(now),
      },
      where: 'id = ? AND status = ?',
      whereArgs: <Object>[id, ComicDownloadQueueStatus.failed.dbValue],
    );
  }

  @override
  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete(
      ComicLocalDb.comicDownloadQueueTable,
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  @override
  Future<bool> deleteIfNotRunning(int id) async {
    final db = await _db;
    final deleted = await db.delete(
      ComicLocalDb.comicDownloadQueueTable,
      where: 'id = ? AND status NOT IN (?, ?)',
      whereArgs: <Object>[
        id,
        ComicDownloadQueueStatus.running.dbValue,
        ComicDownloadQueueStatus.cancelRequested.dbValue,
      ],
    );
    return deleted > 0;
  }

  @override
  Future<void> deleteByEpisode(String comicId, String episodeId) async {
    final db = await _db;
    await db.delete(
      ComicLocalDb.comicDownloadQueueTable,
      where: 'comic_id = ? AND episode_id = ?',
      whereArgs: <Object>[comicId, episodeId],
    );
  }

  @override
  Future<void> deleteByComic(String comicId) async {
    final db = await _db;
    await db.delete(
      ComicLocalDb.comicDownloadQueueTable,
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
  }

  ComicDownloadQueueEntry _entryFromRow(Map<String, Object?> row) {
    return ComicDownloadQueueEntry(
      id: row['id'] as int,
      comicId: row['comic_id'] as String,
      episodeId: row['episode_id'] as String,
      comicTitle: row['comic_title'] as String,
      episodeTitle: row['episode_title'] as String,
      status: ComicDownloadQueueStatusX.fromDbValue(row['status'] as String),
      completedImages: row['completed_images'] as int? ?? 0,
      totalImages: row['total_images'] as int?,
      lastError: row['last_error'] as String?,
      createdAt: _date(row['created_at'] as int),
      updatedAt: _date(row['updated_at'] as int),
    );
  }

  int _ms(DateTime value) => value.millisecondsSinceEpoch;

  DateTime _date(int value) => DateTime.fromMillisecondsSinceEpoch(value);
}

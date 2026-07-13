import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_chapter_sync_repository.dart';

class SqfliteNovelChapterSyncRepository implements NovelChapterSyncRepository {
  const SqfliteNovelChapterSyncRepository(this._dbFuture);

  static const String _contentType = 'novel';

  final Future<Database> _dbFuture;

  @override
  Future<void> beginRun({
    required String runId,
    required String novelId,
    required NovelChapterSyncMode mode,
  }) async {
    _requireText(runId, 'runId');
    final normalizedNovelId = _requireText(novelId, 'novelId');
    final db = await _dbFuture;
    await db.transaction((txn) async {
      await txn.delete(
        ComicLocalDb.novelEpisodeSyncStagingTable,
        where: 'novel_id = ?',
        whereArgs: <Object?>[normalizedNovelId],
      );
      final isInitial = mode == NovelChapterSyncMode.initialFull;
      final updated = await txn.update(
        ComicLocalDb.novelSourceStateTable,
        <String, Object?>{
          if (isInitial)
            'hydration_state':
                NovelChapterHydrationState.hydrating.storageValue,
          'last_error': null,
        },
        where: isInitial
            ? 'novel_id = ?'
            : 'novel_id = ? AND hydration_state = ?',
        whereArgs: <Object?>[
          normalizedNovelId,
          if (!isInitial) NovelChapterHydrationState.ready.storageValue,
        ],
      );
      if (updated != 1) {
        throw StateError(
          isInitial
              ? 'Novel source state does not exist: $normalizedNovelId'
              : 'Novel source state is not ready for incremental sync: '
                    '$normalizedNovelId',
        );
      }
    });
  }

  @override
  Future<void> stageEpisodes({
    required String runId,
    required List<NovelEpisodeDraft> episodes,
  }) async {
    if (episodes.isEmpty) {
      return;
    }
    final normalizedRunId = _requireText(runId, 'runId');
    final novelId = _requireText(
      episodes.first.novelId,
      'episodes.first.novelId',
    );
    if (episodes.any((episode) => episode.novelId.trim() != novelId)) {
      throw StateError('A staging batch cannot contain multiple novels.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final db = await _dbFuture;
    await db.transaction((txn) async {
      for (final draft in episodes) {
        await txn.insert(
          ComicLocalDb.novelEpisodeSyncStagingTable,
          <String, Object?>{
            'run_id': normalizedRunId,
            'novel_id': novelId,
            'episode_id': _requireText(draft.episodeId, 'draft.episodeId'),
            'source_tid': _requireText(draft.sourceTid, 'draft.sourceTid'),
            'source_pid': _requireText(draft.sourcePid, 'draft.sourcePid'),
            'author_filtered_page': draft.sourcePage,
            'episode_title': _requireText(
              draft.episodeTitle,
              'draft.episodeTitle',
            ),
            'order_index': draft.orderIndex,
            'dateline_text': _trimToNull(draft.datelineText),
            'raw_html': draft.rawHtml,
            'plain_text': draft.plainText,
            'paragraph_json': jsonEncode(draft.paragraphs),
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<NovelChapterSyncResult> promote({
    required String runId,
    required NovelChapterSyncRequest request,
    required NovelChapterSyncCheckpoint checkpoint,
    required int fetchedPages,
  }) async {
    final normalizedRunId = _requireText(runId, 'runId');
    final normalizedNovelId = _requireText(request.novelId, 'request.novelId');
    if (checkpoint.novelId != normalizedNovelId ||
        checkpoint.publisherId.trim() != request.publisherId.trim()) {
      throw StateError('Novel chapter checkpoint does not match its request.');
    }
    final db = await _dbFuture;
    return db.transaction((txn) async {
      final stagedRows = await txn.query(
        ComicLocalDb.novelEpisodeSyncStagingTable,
        where: 'run_id = ? AND novel_id = ?',
        whereArgs: <Object?>[normalizedRunId, normalizedNovelId],
        orderBy: 'order_index ASC',
      );
      if (stagedRows.isEmpty) {
        throw StateError('Novel chapter synchronization produced no chapters.');
      }

      final existingRows = await txn.query(
        ComicLocalDb.workEpisodesTable,
        columns: const <String>['episode_id', 'order_index'],
        where: 'work_id = ? AND content_type = ?',
        whereArgs: <Object?>[normalizedNovelId, _contentType],
      );
      final existingOrderById = <String, int>{
        for (final row in existingRows)
          row['episode_id'] as String: (row['order_index'] as num).toInt(),
      };
      final existingIds = existingOrderById.keys.toSet();
      final stagedIds = <String>{};
      var insertedCount = 0;
      var updatedCount = 0;
      var nextOrderIndex = existingOrderById.values.fold<int>(
        0,
        (next, orderIndex) => orderIndex >= next ? orderIndex + 1 : next,
      );
      final now = checkpoint.completedAt.millisecondsSinceEpoch;

      for (final row in stagedRows) {
        final episodeId = row['episode_id'] as String;
        stagedIds.add(episodeId);
        final existingOrderIndex = existingOrderById[episodeId];
        final orderIndex = request.mode == NovelChapterSyncMode.incremental
            ? existingOrderIndex ?? nextOrderIndex++
            : (row['order_index'] as num).toInt();
        if (existingOrderIndex != null) {
          updatedCount++;
        } else {
          insertedCount++;
        }
        // DO UPDATE preserves the parent episode row identity. REPLACE would
        // perform a delete/insert pair and cascade-delete bookmarks.
        await txn.rawInsert(
          '''
          INSERT INTO ${ComicLocalDb.workEpisodesTable} (
            episode_id,
            work_id,
            content_type,
            source_tid,
            source_pid,
            source_page,
            episode_title,
            order_index,
            dateline_text
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(episode_id) DO UPDATE SET
            work_id = excluded.work_id,
            content_type = excluded.content_type,
            source_tid = excluded.source_tid,
            source_pid = excluded.source_pid,
            source_page = excluded.source_page,
            episode_title = excluded.episode_title,
            order_index = excluded.order_index,
            dateline_text = excluded.dateline_text
          ''',
          <Object?>[
            episodeId,
            normalizedNovelId,
            _contentType,
            row['source_tid'],
            row['source_pid'],
            row['author_filtered_page'],
            row['episode_title'],
            orderIndex,
            row['dateline_text'],
          ],
        );
        await txn.rawInsert(
          '''
          INSERT INTO ${ComicLocalDb.novelEpisodeContentTable} (
            episode_id,
            raw_html,
            plain_text,
            paragraph_json,
            updated_at
          ) VALUES (?, ?, ?, ?, ?)
          ON CONFLICT(episode_id) DO UPDATE SET
            raw_html = excluded.raw_html,
            plain_text = excluded.plain_text,
            paragraph_json = excluded.paragraph_json,
            updated_at = excluded.updated_at
          ''',
          <Object?>[
            episodeId,
            row['raw_html'],
            row['plain_text'],
            row['paragraph_json'],
            now,
          ],
        );
      }

      if (request.mode == NovelChapterSyncMode.initialFull) {
        for (final staleId in existingIds.difference(stagedIds)) {
          await txn.delete(
            ComicLocalDb.workEpisodesTable,
            where: 'episode_id = ? AND work_id = ? AND content_type = ?',
            whereArgs: <Object?>[staleId, normalizedNovelId, _contentType],
          );
        }
      }

      final sourceStateUpdated = await txn.rawUpdate(
        '''
        UPDATE ${ComicLocalDb.novelSourceStateTable}
        SET publisher_id = COALESCE(publisher_id, ?),
            hydration_state = ?,
            chapters_hydrated_at = CASE
              WHEN ? = ? THEN ?
              ELSE COALESCE(chapters_hydrated_at, ?)
            END,
            last_completed_author_page = ?,
            last_seen_pid = ?,
            last_sync_at = ?,
            last_error = NULL
        WHERE novel_id = ?
          AND (publisher_id IS NULL OR publisher_id = ?)
        ''',
        <Object?>[
          request.publisherId.trim(),
          NovelChapterHydrationState.ready.storageValue,
          request.mode.name,
          NovelChapterSyncMode.initialFull.name,
          now,
          now,
          checkpoint.lastCompletedAuthorPage,
          _trimToNull(checkpoint.lastSeenPid),
          now,
          normalizedNovelId,
          request.publisherId.trim(),
        ],
      );
      if (sourceStateUpdated != 1) {
        throw StateError(
          'Novel source state is missing or publisher identity changed: '
          '$normalizedNovelId',
        );
      }
      await txn.update(
        ComicLocalDb.worksTable,
        <String, Object?>{'updated_at': now},
        where: 'work_id = ? AND content_type = ?',
        whereArgs: <Object?>[normalizedNovelId, _contentType],
      );
      await txn.delete(
        ComicLocalDb.novelEpisodeSyncStagingTable,
        where: 'run_id = ?',
        whereArgs: <Object?>[normalizedRunId],
      );
      final totalCount = Sqflite.firstIntValue(
        await txn.rawQuery(
          '''
          SELECT COUNT(*)
          FROM ${ComicLocalDb.workEpisodesTable}
          WHERE work_id = ? AND content_type = ?
          ''',
          <Object?>[normalizedNovelId, _contentType],
        ),
      );

      return NovelChapterSyncResult(
        mode: request.mode,
        fetchedPages: fetchedPages,
        insertedCount: insertedCount,
        updatedCount: updatedCount,
        totalCount: totalCount ?? 0,
        checkpoint: checkpoint,
      );
    });
  }

  @override
  Future<void> discardRun(String runId) async {
    final normalizedRunId = _requireText(runId, 'runId');
    final db = await _dbFuture;
    await db.delete(
      ComicLocalDb.novelEpisodeSyncStagingTable,
      where: 'run_id = ?',
      whereArgs: <Object?>[normalizedRunId],
    );
  }

  String _requireText(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
    return normalized;
  }

  String? _trimToNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

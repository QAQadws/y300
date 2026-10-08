import 'package:sqflite/sqflite.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import '../../domain/models/novel_reader_anchor_format.dart';
import '../../domain/models/novel_reader_preferences.dart';
import '../../domain/models/novel_reading_progress.dart';
import '../../domain/repositories/novel_reading_state_repository.dart';

class SqfliteNovelReadingStateRepository
    implements NovelReadingStateRepository {
  SqfliteNovelReadingStateRepository(this._dbFuture);
  final Future<Database> _dbFuture;

  @override
  Future<NovelReadingStateSnapshot> loadWorkState({
    required String novelId,
  }) async {
    final db = await _dbFuture;
    return db.transaction((txn) async {
      final positions = await txn.query(
        AppDatabase.novelReadingProgressTable,
        where: 'novel_id = ?',
        whereArgs: [novelId],
      );
      final states = await txn.query(
        AppDatabase.libraryEpisodeStateTable,
        where: 'content_type = ? AND work_id = ?',
        whereArgs: ['novel', novelId],
      );
      final work = await txn.query(
        AppDatabase.libraryWorkStateTable,
        columns: ['last_read_episode_id'],
        where: 'content_type = ? AND work_id = ?',
        whereArgs: ['novel', novelId],
        limit: 1,
      );
      final byEpisode = <String, NovelReadingProgress>{
        for (final row in positions) row['episode_id'] as String: _decode(row),
      };
      final recent = work.isEmpty
          ? null
          : work.single['last_read_episode_id'] as String?;
      return NovelReadingStateSnapshot(
        novelId: novelId,
        progressByEpisode: byEpisode,
        recentEpisodeId: byEpisode.containsKey(recent)
            ? recent
            : _latest(byEpisode.values)?.episodeId,
        episodeStates: {
          for (final row in states)
            row['episode_id'] as String: LibraryEpisodeState(
              moduleKey: LibraryModuleKey.novel,
              episodeId: row['episode_id'] as String,
              workId: novelId,
              isRead: row['is_read'] == 1 && row['read_state_version'] == 1,
              isBookmarked: row['is_bookmarked'] == 1,
              isDownloaded: row['is_downloaded'] == 1,
              readAt: row['read_state_version'] == 1
                  ? _date(row['read_at'])
                  : null,
              downloadedAt: _date(row['downloaded_at']),
            ),
        },
      );
    });
  }

  @override
  Future<NovelReadingProgress?> getChapterProgress({
    required String novelId,
    required String episodeId,
  }) async {
    final rows = await (await _dbFuture).query(
      AppDatabase.novelReadingProgressTable,
      where: 'novel_id = ? AND episode_id = ?',
      whereArgs: [novelId, episodeId],
      limit: 1,
    );
    return rows.isEmpty ? null : _decode(rows.single);
  }

  @override
  Future<bool> commitProgress({
    required NovelReadingProgress progress,
    bool markCompleted = false,
    bool Function()? canCommit,
  }) async {
    final fraction = progress.progressPercent;
    // SQLite can turn NaN into NULL. Reject malformed new reports before that
    // can be decoded as a zero carrying somebody else's validity evidence.
    if (!fraction.isFinite || fraction < 0 || fraction > 1) {
      return false;
    }
    return _mutate(canCommit, (txn) async {
      final row = _encode(progress);
      final updated = await txn.update(
        AppDatabase.novelReadingProgressTable,
        row,
        where: 'novel_id = ? AND episode_id = ?',
        whereArgs: [progress.novelId, progress.episodeId],
      );
      if (updated == 0) {
        await txn.insert(AppDatabase.novelReadingProgressTable, row);
      }
      await _writeRecent(
        txn,
        progress.novelId,
        progress.episodeId,
        progress.updatedAt.millisecondsSinceEpoch,
      );
      if (markCompleted) {
        await _writeRead(txn, progress.novelId, progress.episodeId, true);
      }
    });
  }

  @override
  Future<bool> setChapterRead({
    required String novelId,
    required String episodeId,
    required bool isRead,
    bool Function()? canCommit,
  }) {
    if (!isRead) {
      return resetChapter(
        novelId: novelId,
        episodeId: episodeId,
        canCommit: canCommit,
      );
    }
    return _mutate(
      canCommit,
      (txn) => _writeRead(txn, novelId, episodeId, true),
    );
  }

  @override
  Future<bool> resetChapter({
    required String novelId,
    required String episodeId,
    bool Function()? canCommit,
  }) {
    return _mutate(canCommit, (txn) async {
      await txn.delete(
        AppDatabase.novelReadingProgressTable,
        where: 'novel_id = ? AND episode_id = ?',
        whereArgs: [novelId, episodeId],
      );
      await _writeRead(txn, novelId, episodeId, false);
      final work = await txn.query(
        AppDatabase.libraryWorkStateTable,
        columns: ['last_read_episode_id'],
        where: 'content_type = ? AND work_id = ?',
        whereArgs: ['novel', novelId],
        limit: 1,
      );
      if (work.isEmpty || work.single['last_read_episode_id'] == episodeId) {
        final latest = await txn.query(
          AppDatabase.novelReadingProgressTable,
          columns: ['episode_id', 'updated_at'],
          where: 'novel_id = ?',
          whereArgs: [novelId],
          orderBy: 'updated_at DESC, episode_id ASC',
          limit: 1,
        );
        await _writeRecent(
          txn,
          novelId,
          latest.isEmpty ? null : latest.single['episode_id'] as String,
          latest.isEmpty ? null : latest.single['updated_at'] as int,
        );
      }
    });
  }

  Future<bool> _mutate(
    bool Function()? guard,
    Future<void> Function(Transaction) action,
  ) async {
    final db = await _dbFuture;
    try {
      return await db.transaction((txn) async {
        if (guard?.call() == false) throw const _RetiredMutation();
        await action(txn);
        // The transaction can wait on I/O while a route/reset retires its owner.
        // Roll back the entire position/recent/completion mutation in that case.
        if (guard?.call() == false) throw const _RetiredMutation();
        return true;
      });
    } on _RetiredMutation {
      return false;
    }
  }

  Future<void> _writeRecent(
    Transaction txn,
    String novelId,
    String? episodeId,
    int? readAt,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final values = <String, Object?>{
      'last_read_episode_id': episodeId,
      'last_read_at': readAt,
      'updated_at': now,
    };
    final count = await txn.update(
      AppDatabase.libraryWorkStateTable,
      values,
      where: 'content_type = ? AND work_id = ?',
      whereArgs: ['novel', novelId],
    );
    if (count == 0) {
      await txn.insert(AppDatabase.libraryWorkStateTable, {
        ...values,
        'content_type': 'novel',
        'work_id': novelId,
        'created_at': now,
      });
    }
  }

  Future<void> _writeRead(
    Transaction txn,
    String novelId,
    String episodeId,
    bool isRead,
  ) async {
    final values = <String, Object?>{
      'work_id': novelId,
      'is_read': isRead ? 1 : 0,
      'read_state_version': 1,
      'read_at': isRead ? DateTime.now().millisecondsSinceEpoch : null,
    };
    final count = await txn.update(
      AppDatabase.libraryEpisodeStateTable,
      values,
      where: 'content_type = ? AND episode_id = ?',
      whereArgs: ['novel', episodeId],
    );
    if (count == 0) {
      await txn.insert(AppDatabase.libraryEpisodeStateTable, {
        ...values,
        'content_type': 'novel',
        'episode_id': episodeId,
      });
    }
  }

  Map<String, Object?> _encode(NovelReadingProgress p) => {
    'novel_id': p.novelId,
    'episode_id': p.episodeId,
    'scroll_offset': p.scrollOffset,
    'flow_mode': p.flowMode.storageValue,
    'page_index': p.pageIndex < 0 ? 0 : p.pageIndex,
    'page_count': p.pageCount == null || p.pageCount! <= 0 ? null : p.pageCount,
    'anchor_node_id': _text(p.anchorNodeId),
    'anchor_text_offset': _offset(
      p.anchorTextOffset,
      p.anchorFormatVersion,
      p.anchorTextIdentity,
    ),
    'pagination_key': _text(p.paginationKey),
    'progress_percent': p.progressPercent,
    'anchor_format_version': p.anchorFormatVersion,
    'anchor_text_identity': p.anchorTextIdentity,
    'progress_percent_valid': p.isProgressPercentValid == null
        ? null
        : p.isProgressPercentValid!
        ? 1
        : 0,
    'percent_basis': p.percentBasis,
    'updated_at': p.updatedAt.millisecondsSinceEpoch,
  };

  NovelReadingProgress _decode(Map<String, Object?> row) {
    final version =
        (row['anchor_format_version'] as num?)?.toInt() ??
        NovelReaderAnchorFormat.legacyUnknown;
    final identity = row['anchor_text_identity'] as String?;
    return NovelReadingProgress(
      novelId: row['novel_id'] as String,
      episodeId: row['episode_id'] as String,
      scrollOffset: (row['scroll_offset'] as num?)?.toDouble() ?? 0,
      updatedAt:
          _date(row['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      flowMode: NovelReaderFlowModeCodec.fromStorage(
        row['flow_mode'] as String?,
      ),
      pageIndex: ((row['page_index'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30),
      pageCount: switch ((row['page_count'] as num?)?.toInt()) {
        final value? when value > 0 => value,
        _ => null,
      },
      anchorNodeId: _text(row['anchor_node_id'] as String?),
      anchorTextOffset: _offset(
        (row['anchor_text_offset'] as num?)?.toInt() ?? 0,
        version,
        identity,
      ),
      paginationKey: _text(row['pagination_key'] as String?),
      progressPercent: (row['progress_percent'] as num?)?.toDouble() ?? 0,
      anchorFormatVersion: version,
      anchorTextIdentity: identity,
      isProgressPercentValid: switch (row['progress_percent_valid']) {
        0 => false,
        1 => true,
        _ => null,
      },
      percentBasis:
          row['percent_basis'] as String? ??
          NovelProgressPercentBasis.legacyReaderLayout,
    );
  }

  NovelReadingProgress? _latest(Iterable<NovelReadingProgress> values) {
    final sorted = values.toList()
      ..sort((a, b) {
        final order = b.updatedAt.compareTo(a.updatedAt);
        return order == 0 ? a.episodeId.compareTo(b.episodeId) : order;
      });
    return sorted.isEmpty ? null : sorted.first;
  }

  int _offset(int value, int version, String? identity) =>
      NovelReaderAnchorFormat.isSupported(version, identity)
      ? value.clamp(0, 1 << 30)
      : value;
  String? _text(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
  DateTime? _date(Object? value) =>
      value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;
}

class _RetiredMutation implements Exception {
  const _RetiredMutation();
}

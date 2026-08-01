import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/repositories/comic_search_refresh_queue_repository.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';

class LocalComicSearchRefreshQueueRepository
    implements ComicSearchRefreshQueueRepository {
  LocalComicSearchRefreshQueueRepository(Future<Database> dbFuture)
    : _openDb = (() => dbFuture),
      _dbFuture = dbFuture;

  LocalComicSearchRefreshQueueRepository.lazy(this._openDb);

  final Future<Database> Function() _openDb;
  Future<Database>? _dbFuture;

  Future<Database> get _db async {
    return _dbFuture ??= _openDb();
  }

  static const List<String> _activeStatuses = <String>['pending', 'running'];

  @override
  Future<ComicSearchRefreshQueueUpsertResult> enqueue(
    ComicSearchRefreshQueueDraft draft, {
    required DateTime now,
  }) async {
    final comicId = _requiredComicId(draft.request);
    final db = await _db;
    return db.transaction<ComicSearchRefreshQueueUpsertResult>((txn) async {
      final active = await txn.query(
        ComicLocalDb.comicSearchRefreshQueueTable,
        where: 'comic_id = ? AND status IN (?, ?)',
        whereArgs: <Object>[comicId, ..._activeStatuses],
        orderBy: 'created_at ASC, id ASC',
        limit: 1,
      );

      if (active.isNotEmpty) {
        final current = _entryFromRow(active.first);
        if (current.status == ComicSearchRefreshQueueStatus.running) {
          return ComicSearchRefreshQueueUpsertResult(
            entry: current,
            deduplicated: true,
          );
        }
        await txn.update(
          ComicLocalDb.comicSearchRefreshQueueTable,
          _valuesFromDraft(
            draft,
            comicId: comicId,
            now: now,
            resetAttempts: true,
          ),
          where: 'id = ?',
          whereArgs: <Object>[current.id],
        );
        return ComicSearchRefreshQueueUpsertResult(
          entry: await _loadById(txn, current.id),
          deduplicated: true,
        );
      }

      final id = await txn.insert(
        ComicLocalDb.comicSearchRefreshQueueTable,
        <String, Object?>{
          ..._valuesFromDraft(draft, comicId: comicId, now: now),
          'created_at': _ms(now),
        },
      );
      return ComicSearchRefreshQueueUpsertResult(
        entry: await _loadById(txn, id),
        deduplicated: false,
      );
    });
  }

  @override
  Future<void> resetRunningToPending({required DateTime now}) async {
    final db = await _db;
    await db.update(
      ComicLocalDb.comicSearchRefreshQueueTable,
      <String, Object?>{
        'status': ComicSearchRefreshQueueStatus.pending.dbValue,
        'available_at': _ms(now),
        'started_at': null,
        'updated_at': _ms(now),
      },
      where: 'status = ?',
      whereArgs: <Object>[ComicSearchRefreshQueueStatus.running.dbValue],
    );
  }

  @override
  Future<ComicSearchRefreshQueueEntry?> claimNextPending({
    required DateTime now,
  }) async {
    final db = await _db;
    return db.transaction<ComicSearchRefreshQueueEntry?>((txn) async {
      final rows = await txn.query(
        ComicLocalDb.comicSearchRefreshQueueTable,
        where: 'status = ? AND available_at <= ?',
        whereArgs: <Object>[
          ComicSearchRefreshQueueStatus.pending.dbValue,
          _ms(now),
        ],
        orderBy: 'available_at ASC, created_at ASC, id ASC',
        limit: 1,
      );
      if (rows.isEmpty) {
        return null;
      }
      final id = rows.first['id'] as int;
      await txn.update(
        ComicLocalDb.comicSearchRefreshQueueTable,
        <String, Object?>{
          'status': ComicSearchRefreshQueueStatus.running.dbValue,
          'started_at': _ms(now),
          'updated_at': _ms(now),
        },
        where: 'id = ?',
        whereArgs: <Object>[id],
      );
      return _loadById(txn, id);
    });
  }

  @override
  Future<void> markCompleted({required int id, required DateTime now}) async {
    final db = await _db;
    await db.update(
      ComicLocalDb.comicSearchRefreshQueueTable,
      <String, Object?>{
        'status': ComicSearchRefreshQueueStatus.completed.dbValue,
        'completed_at': _ms(now),
        'last_error': null,
        'updated_at': _ms(now),
      },
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  @override
  Future<void> markRetry({
    required int id,
    required int attempts,
    required String lastError,
    required DateTime availableAt,
    required DateTime now,
  }) async {
    final db = await _db;
    await db.update(
      ComicLocalDb.comicSearchRefreshQueueTable,
      <String, Object?>{
        'status': ComicSearchRefreshQueueStatus.pending.dbValue,
        'attempts': attempts,
        'available_at': _ms(availableAt),
        'started_at': null,
        'last_error': lastError,
        'updated_at': _ms(now),
      },
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  @override
  Future<void> markFailed({
    required int id,
    required int attempts,
    required String lastError,
    required DateTime now,
  }) async {
    final db = await _db;
    await db.update(
      ComicLocalDb.comicSearchRefreshQueueTable,
      <String, Object?>{
        'status': ComicSearchRefreshQueueStatus.failed.dbValue,
        'attempts': attempts,
        'last_error': lastError,
        'completed_at': _ms(now),
        'updated_at': _ms(now),
      },
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  @override
  Future<void> deleteByComicId(String comicId) async {
    final normalized = comicId.trim();
    if (normalized.isEmpty) {
      return;
    }
    final db = await _db;
    await db.delete(
      ComicLocalDb.comicSearchRefreshQueueTable,
      where: 'comic_id = ?',
      whereArgs: <Object>[normalized],
    );
  }

  @override
  Future<List<ComicSearchRefreshQueueEntry>> loadActiveEntries() async {
    final db = await _db;
    final rows = await db.query(
      ComicLocalDb.comicSearchRefreshQueueTable,
      where: 'status IN (?, ?)',
      whereArgs: _activeStatuses,
      orderBy:
          "CASE status WHEN 'running' THEN 0 ELSE 1 END, available_at ASC, created_at ASC, id ASC",
    );
    return rows.map(_entryFromRow).toList(growable: false);
  }

  Map<String, Object?> _valuesFromDraft(
    ComicSearchRefreshQueueDraft draft, {
    required String comicId,
    required DateTime now,
    bool resetAttempts = false,
  }) {
    final request = draft.request;
    return <String, Object?>{
      'comic_id': comicId,
      'source_tid': request.sourceTid.trim(),
      'display_title': _normalizeNullable(request.displayTitle),
      'source_title': _normalizeNullable(request.sourceTitle),
      'custom_title': _normalizeNullable(request.customTitle),
      'custom_search_title': _normalizeNullable(request.customSearchTitle),
      'title': _resolveTitle(draft),
      'origin': draft.origin.dbValue,
      'status': ComicSearchRefreshQueueStatus.pending.dbValue,
      if (resetAttempts) 'attempts': 0,
      'available_at': _ms(now),
      'started_at': null,
      'completed_at': null,
      'last_error': null,
      'updated_at': _ms(now),
    };
  }

  Future<ComicSearchRefreshQueueEntry> _loadById(
    Transaction txn,
    int id,
  ) async {
    final rows = await txn.query(
      ComicLocalDb.comicSearchRefreshQueueTable,
      where: 'id = ?',
      whereArgs: <Object>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Comic search refresh queue entry $id not found');
    }
    return _entryFromRow(rows.first);
  }

  ComicSearchRefreshQueueEntry _entryFromRow(Map<String, Object?> row) {
    final comicId = row['comic_id'] as String;
    return ComicSearchRefreshQueueEntry(
      id: row['id'] as int,
      comicId: comicId,
      title: row['title'] as String,
      request: ComicEpisodeRefreshRequest(
        comicId: comicId,
        sourceTid: row['source_tid'] as String,
        displayTitle: row['display_title'] as String?,
        sourceTitle: row['source_title'] as String?,
        customTitle: row['custom_title'] as String?,
        customSearchTitle: row['custom_search_title'] as String?,
      ),
      origin: ComicSearchRefreshOriginX.fromDbValue(row['origin'] as String),
      status: ComicSearchRefreshQueueStatusX.fromDbValue(
        row['status'] as String,
      ),
      attempts: row['attempts'] as int? ?? 0,
      availableAt: _date(row['available_at'] as int),
      createdAt: _date(row['created_at'] as int),
      updatedAt: _date(row['updated_at'] as int),
      startedAt: _nullableDate(row['started_at'] as int?),
      completedAt: _nullableDate(row['completed_at'] as int?),
      lastError: row['last_error'] as String?,
    );
  }

  String _requiredComicId(ComicEpisodeRefreshRequest request) {
    final comicId = request.comicId?.trim();
    if (comicId == null || comicId.isEmpty) {
      throw ArgumentError(
        'Comic search refresh queue requires request.comicId',
      );
    }
    return comicId;
  }

  String _resolveTitle(ComicSearchRefreshQueueDraft draft) {
    final choices = <String?>[
      draft.title,
      draft.request.displayTitle,
      draft.request.customTitle,
      draft.request.sourceTitle,
      draft.request.comicId,
    ];
    for (final choice in choices) {
      final normalized = _normalizeNullable(choice);
      if (normalized != null) {
        return normalized;
      }
    }
    return draft.request.sourceTid;
  }

  String? _normalizeNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  int _ms(DateTime value) => value.millisecondsSinceEpoch;

  DateTime _date(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

  DateTime? _nullableDate(int? ms) {
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
}

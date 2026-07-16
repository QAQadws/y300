import 'dart:async';

import 'package:sqflite/sqflite.dart';
import 'package:y300/features/history/data/local/history_entry_dao.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/repositories/history_repository.dart';
import 'package:y300/features/history/domain/services/history_retention_policy.dart';

class SqfliteHistoryRepository implements HistoryRepository {
  SqfliteHistoryRepository(
    Future<Database> database, {
    HistoryEntryDao dao = const HistoryEntryDao(),
    HistoryRetentionPolicy retentionPolicy = const HistoryRetentionPolicy(),
  }) : _databaseProvider = (() => database),
       _dao = dao,
       _retentionPolicy = retentionPolicy;

  SqfliteHistoryRepository.withDatabaseProvider(
    Future<Database> Function() databaseProvider, {
    HistoryEntryDao dao = const HistoryEntryDao(),
    HistoryRetentionPolicy retentionPolicy = const HistoryRetentionPolicy(),
  }) : _databaseProvider = databaseProvider,
       _dao = dao,
       _retentionPolicy = retentionPolicy;

  final Future<Database> Function() _databaseProvider;
  final HistoryEntryDao _dao;
  final HistoryRetentionPolicy _retentionPolicy;
  final StreamController<HistoryChange> _changes =
      StreamController<HistoryChange>.broadcast(sync: true);

  @override
  Future<void> recordVisit(HistoryEntry candidate) async {
    final db = await _databaseProvider();
    await db.transaction((txn) async {
      await _dao.upsertVisit(txn, candidate);
      await _dao.prune(txn, maxEntries: _retentionPolicy.maxEntries);
    });
    _emit(
      HistoryChange(kind: HistoryChangeKind.recorded, target: candidate.target),
    );
  }

  @override
  Future<HistoryQueryPage> query(HistoryQuery query) async {
    final db = await _databaseProvider();
    return _dao.query(db, query);
  }

  @override
  Future<void> delete(HistoryTargetKey target) async {
    final db = await _databaseProvider();
    final deleted = await _dao.delete(db, target);
    if (deleted > 0) {
      _emit(HistoryChange(kind: HistoryChangeKind.deleted, target: target));
    }
  }

  @override
  Future<void> clear() async {
    final db = await _databaseProvider();
    final deleted = await _dao.clear(db);
    if (deleted > 0) {
      _emit(const HistoryChange(kind: HistoryChangeKind.cleared));
    }
  }

  @override
  Future<void> restore(HistoryEntry entry) async {
    final db = await _databaseProvider();
    final restored = await db.transaction<int>((txn) async {
      final changed = await _dao.restore(txn, entry);
      if (changed > 0) {
        await _dao.prune(txn, maxEntries: _retentionPolicy.maxEntries);
      }
      return changed;
    });
    if (restored > 0) {
      _emit(
        HistoryChange(kind: HistoryChangeKind.restored, target: entry.target),
      );
    }
  }

  @override
  Stream<HistoryChange> watchChanges() => _changes.stream;

  void dispose() {
    unawaited(_changes.close());
  }

  void _emit(HistoryChange change) {
    if (!_changes.isClosed) {
      _changes.add(change);
    }
  }
}

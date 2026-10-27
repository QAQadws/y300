import 'package:sqflite/sqflite.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/favorites/domain/services/favorite_parse_service.dart';

class FavoriteParseJob {
  const FavoriteParseJob({
    required this.accountId,
    required this.revision,
    required this.target,
  });
  final String accountId;
  final int revision;
  final FavoriteParseTarget target;
}

/// Queue state is independent from the directory's sync baseline.
class FavoriteParseJobRepository {
  FavoriteParseJobRepository(this.database);
  final Future<Database> database;

  Future<bool> enqueue(
    String accountId,
    FavoriteParseTarget target, {
    required bool Function() isCurrent,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      if (!isCurrent()) throw StateError('favorite_parse_owner_changed');
      final old = await txn.query(
        AppDatabase.favoriteParseJobsTable,
        where: 'account_id = ? AND tid = ?',
        whereArgs: [accountId, target.tid],
      );
      if (!target.confirmed) {
        final active = await txn.query(
          AppDatabase.favoriteThreadsTable,
          columns: ['tid'],
          where: 'tid = ? AND removed_at IS NULL',
          whereArgs: [target.tid],
        );
        if (active.isEmpty) throw StateError('favorite_parse_target_inactive');
      }
      if (!isCurrent()) throw StateError('favorite_parse_owner_changed');
      if (old.isNotEmpty &&
          ['queued', 'running'].contains(old.single['state'])) {
        final upgraded =
            target.confirmed &&
            (old.single['confirmed'] != 1 ||
                (target.remoteFavoriteId != null &&
                    target.remoteFavoriteId != old.single['favid']));
        if (upgraded && old.single['state'] == 'running') {
          // Preserve a stronger request across a crash while its predecessor is
          // running. The old revision may no longer acknowledge this row.
          await txn.update(
            AppDatabase.favoriteParseJobsTable,
            {
              'state': 'queued',
              'revision': (old.single['revision'] as int) + 1,
              'confirmed': 1,
              'favid': target.remoteFavoriteId,
              'title': target.title,
            },
            where: 'account_id = ? AND tid = ?',
            whereArgs: [accountId, target.tid],
          );
          return true;
        }
        // A confirmed add upgrades a waiting manual retry without losing its
        // evidence. A running request is covered by its existing execution.
        if (target.confirmed && old.single['state'] == 'queued') {
          await txn.update(
            AppDatabase.favoriteParseJobsTable,
            {
              'confirmed': 1,
              'favid': target.remoteFavoriteId,
              'title': target.title,
            },
            where: 'account_id = ? AND tid = ?',
            whereArgs: [accountId, target.tid],
          );
        }
        return false;
      }
      await txn.insert(AppDatabase.favoriteParseJobsTable, {
        'account_id': accountId,
        'tid': target.tid,
        'state': 'queued',
        'revision': ((old.firstOrNull?['revision'] as int?) ?? 0) + 1,
        'confirmed': target.confirmed ? 1 : 0,
        'favid': target.remoteFavoriteId,
        'title': target.title,
        'error_code': null,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    });
  }

  Future<void> recover(String accountId) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE ${AppDatabase.favoriteParseJobsTable} SET state = ?, revision = revision + 1 WHERE account_id = ? AND state = ?',
      ['queued', accountId, 'running'],
    );
  }

  Future<FavoriteParseJob?> claim(String accountId) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        AppDatabase.favoriteParseJobsTable,
        where: 'account_id = ? AND state = ?',
        whereArgs: [accountId, 'queued'],
        orderBy: 'created_at, tid',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final row = rows.single;
      await txn.update(
        AppDatabase.favoriteParseJobsTable,
        {'state': 'running'},
        where: 'account_id = ? AND tid = ?',
        whereArgs: [accountId, row['tid']],
      );
      return FavoriteParseJob(
        accountId: accountId,
        revision: row['revision'] as int,
        target: FavoriteParseTarget(
          tid: row['tid'] as String,
          confirmed: row['confirmed'] == 1,
          remoteFavoriteId: row['favid'] as String?,
          title: row['title'] as String?,
        ),
      );
    });
  }

  Future<bool> isCurrent(FavoriteParseJob job) async {
    final db = await database;
    return (await db.query(
      AppDatabase.favoriteParseJobsTable,
      columns: ['tid'],
      where: 'account_id = ? AND tid = ? AND revision = ? AND state = ?',
      whereArgs: [job.accountId, job.target.tid, job.revision, 'running'],
    )).isNotEmpty;
  }

  Future<void> finish(FavoriteParseJob job, {String? errorCode}) async {
    final db = await database;
    await db.update(
      AppDatabase.favoriteParseJobsTable,
      {
        'state': errorCode == null ? 'completed' : 'failed',
        'error_code': errorCode,
      },
      where: 'account_id = ? AND tid = ? AND revision = ? AND state = ?',
      whereArgs: [job.accountId, job.target.tid, job.revision, 'running'],
    );
  }

  Future<void> cancel(String accountId, Set<String> tids) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final tid in tids) {
        await txn.rawUpdate(
          'UPDATE ${AppDatabase.favoriteParseJobsTable} SET state = ?, revision = revision + 1 WHERE account_id = ? AND tid = ?',
          ['cancelled', accountId, tid],
        );
      }
    });
  }
}

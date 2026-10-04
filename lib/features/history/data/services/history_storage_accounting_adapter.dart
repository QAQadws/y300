import 'dart:io' as io;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/history/data/local/history_local_db.dart';

class HistoryStorageAccountingAdapter implements StorageAccountingAdapter {
  const HistoryStorageAccountingAdapter({
    Future<Database>? databaseFuture,
    Future<Database> Function()? databaseProvider,
    Future<String>? databasePathFuture,
  }) : _databaseFuture = databaseFuture,
       _databaseProvider = databaseProvider,
       _databasePathFuture = databasePathFuture;

  final Future<Database>? _databaseFuture;
  final Future<Database> Function()? _databaseProvider;
  final Future<String>? _databasePathFuture;

  @override
  StorageBucket get bucket => StorageBucket.history;

  @override
  Future<StorageUsageSection> calculateUsage() async {
    final count = await _loadEntryCount();
    final bytes = await _databaseFileBytes();
    return StorageUsageSection(
      bucket: bucket,
      labelRef: StorageUsageLabelRef(
        kind: StorageUsageLabelKind.bucket,
        code: bucket.id,
      ),
      bytes: bytes,
      clearable: false,
      slices: <StorageUsageSlice>[
        if (bytes > 0)
          StorageUsageSlice(
            id: 'history:sqlite',
            labelRef: const StorageUsageLabelRef(
              kind: StorageUsageLabelKind.database,
              code: 'history',
            ),
            bytes: bytes,
            protected: true,
          ),
        StorageUsageSlice(
          id: 'history:entries',
          labelRef: StorageUsageLabelRef(
            kind: StorageUsageLabelKind.historyKind,
            code: 'entries',
            count: count,
          ),
          bytes: 0,
          protected: true,
        ),
      ],
    );
  }

  Future<int> _loadEntryCount() async {
    try {
      final db =
          await (_databaseProvider?.call() ??
              _databaseFuture ??
              HistoryLocalDb.open());
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS count FROM ${HistoryLocalDb.entriesTable}',
      );
      return rows.first['count'] as int? ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<int> _databaseFileBytes() async {
    final path =
        await (_databasePathFuture ??
            (() async =>
                p.join(await getDatabasesPath(), HistoryLocalDb.dbName))());
    var bytes = 0;
    for (final suffix in const <String>['', '-wal', '-shm']) {
      final file = io.File('$path$suffix');
      if (await file.exists()) {
        bytes += await file.length();
      }
    }
    return bytes;
  }
}

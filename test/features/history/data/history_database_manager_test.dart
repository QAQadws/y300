import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/history/data/local/history_database_manager.dart';
import 'package:y300/features/history/data/repositories/sqflite_history_repository.dart';
import 'package:y300/features/history/data/services/history_data_lifecycle_service.dart';
import 'package:y300/features/history/domain/models/history_models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'full data reset closes, deletes, and can reopen history storage',
    () async {
      const dbName = 'history_records_phase7_lifecycle_test.db';
      await deleteDatabase(dbName);
      final manager = HistoryDatabaseManager(databaseName: dbName);
      final repository = SqfliteHistoryRepository.withDatabaseProvider(
        manager.open,
      );
      final lifecycle = HistoryDataLifecycleService(
        databaseManager: manager,
        repository: repository,
      );
      addTearDown(() async {
        repository.dispose();
        await manager.dispose();
        await deleteDatabase(dbName);
      });

      final databaseBeforeReset = await manager.open();
      await repository.recordVisit(_entry('100'));
      expect(
        (await repository.query(const HistoryQuery())).items,
        hasLength(1),
      );

      await lifecycle.deleteAllData();

      expect(databaseBeforeReset.isOpen, isFalse);
      expect(await databaseExists(dbName), isFalse);

      final databaseAfterReset = await manager.open();
      expect(databaseAfterReset.isOpen, isTrue);
      expect((await repository.query(const HistoryQuery())).items, isEmpty);
    },
  );

  test('manager dispose waits for and closes the active connection', () async {
    const dbName = 'history_records_phase7_dispose_test.db';
    await deleteDatabase(dbName);
    final manager = HistoryDatabaseManager(databaseName: dbName);
    final db = await manager.open();

    await manager.dispose();

    expect(db.isOpen, isFalse);
    expect(manager.isDisposed, isTrue);
    await expectLater(manager.open(), throwsStateError);
    await deleteDatabase(dbName);
  });
}

HistoryEntry _entry(String tid) {
  final at = DateTime.utc(2026, 7, 16);
  return HistoryEntry(
    target: HistoryTargetKey(type: HistoryTargetType.thread, id: tid),
    title: '帖子',
    contextLabel: '详情',
    lastSurface: HistoryVisitSurface.threadNative,
    firstVisitedAt: at,
    lastVisitedAt: at,
    visitCount: 1,
  );
}

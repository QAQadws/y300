import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/core/persistence/app_database.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'AppDatabase phase3 migration creates favorite tables and indexes',
    () async {
      const dbName = 'comic_shelf_test_favorite_phase3.db';
      await deleteDatabase(dbName);

      final db = await AppDatabase.open(databaseName: dbName);
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final tableNames = tables.map((row) => row['name']).toSet();

      expect(tableNames.contains(AppDatabase.favoriteSyncStateTable), isTrue);
      expect(tableNames.contains(AppDatabase.favoriteThreadsTable), isTrue);
      expect(tableNames.contains(AppDatabase.favoriteCategoriesTable), isTrue);
      expect(
        tableNames.contains(AppDatabase.favoriteThreadCategoryTable),
        isTrue,
      );

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index'",
      );
      final indexNames = indexes.map((row) => row['name']).toSet();
      expect(indexNames.contains('idx_favorite_threads_kind_order'), isTrue);
      expect(indexNames.contains('idx_favorite_threads_removed'), isTrue);
      expect(
        indexNames.contains('idx_favorite_thread_category_category'),
        isTrue,
      );

      await db.close();
      await deleteDatabase(dbName);
    },
  );
}

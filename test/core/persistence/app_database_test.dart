import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/core/persistence/app_database.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory directory;
  late String databasePath;
  Database? database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('y300-shared-db-');
    databasePath = p.join(directory.path, AppDatabase.dbName);
  });

  tearDown(() async {
    await database?.close();
    database = null;
    await directory.delete(recursive: true);
  });

  test(
    'shared entry keeps the physical database and single connection',
    () async {
      expect(AppDatabase.dbName, 'comic_shelf.db');
      expect(AppDatabase.dbVersion, 41);
      database = await AppDatabase.open(databaseName: databasePath);
      final second = await AppDatabase.open(databaseName: databasePath);
      expect(identical(database, second), isTrue);
      expect(await database!.getVersion(), 41);
      expect(await File(databasePath).exists(), isTrue);
      final foreignKeys = await database!.rawQuery('PRAGMA foreign_keys');
      expect(foreignKeys.single.values.single, 1);
    },
  );

  test('cross-feature writes roll back together and survive reopening', () async {
    database = await AppDatabase.open(databaseName: databasePath);
    final db = database!;
    await db.insert(AppDatabase.comicsTable, <String, Object?>{
      'comic_id': 'comic',
      'source_tid': '100',
      'source_fid': '30',
      'title': 'comic before',
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert(AppDatabase.worksTable, <String, Object?>{
      'work_id': 'novel',
      'content_type': 'novel',
      'source_tid': '200',
      'source_fid': '49',
      'title': 'novel before',
      'updated_at': 1,
    });
    await db.insert(AppDatabase.favoriteThreadsTable, <String, Object?>{
      'tid': '100',
      'title': 'favorite before',
      'first_seen_at': 1,
      'last_seen_at': 1,
    });
    await db.insert(AppDatabase.libraryWorkStateTable, <String, Object?>{
      'content_type': 'comic',
      'work_id': 'comic',
      'intro_text': 'state before',
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert(AppDatabase.cachedDocumentsTable, <String, Object?>{
      'cache_key': 'document',
      'namespace': 'thread',
      'owner_type': 'comic',
      'owner_id': 'comic',
      'source_url': 'https://www.yamibo.com/thread-100-1-1.html',
      'body': 'cache before',
      'fetched_at': 1,
      'updated_at': 1,
    });

    await expectLater(
      db.transaction((txn) async {
        await txn.update(AppDatabase.comicsTable, {'title': 'comic after'});
        await txn.update(AppDatabase.worksTable, {'title': 'novel after'});
        await txn.update(AppDatabase.favoriteThreadsTable, {
          'title': 'favorite after',
        });
        await txn.update(AppDatabase.libraryWorkStateTable, {
          'intro_text': 'state after',
        });
        await txn.update(AppDatabase.cachedDocumentsTable, {
          'body': 'cache after',
        });
        // A real FK failure after all writes must abort the shared transaction.
        await txn.insert(
          AppDatabase.favoriteThreadCategoryTable,
          <String, Object?>{
            'tid': '100',
            'category_id': 'missing-category',
            'assigned_at': 2,
          },
        );
      }),
      throwsA(isA<DatabaseException>()),
    );

    await db.close();
    database = await AppDatabase.open(databaseName: databasePath);
    final reopened = database!;
    expect(
      (await reopened.query(AppDatabase.comicsTable)).single['title'],
      'comic before',
    );
    expect(
      (await reopened.query(AppDatabase.worksTable)).single['title'],
      'novel before',
    );
    expect(
      (await reopened.query(AppDatabase.favoriteThreadsTable)).single['title'],
      'favorite before',
    );
    expect(
      (await reopened.query(
        AppDatabase.libraryWorkStateTable,
      )).single['intro_text'],
      'state before',
    );
    expect(
      (await reopened.query(AppDatabase.cachedDocumentsTable)).single['body'],
      'cache before',
    );
    expect(
      await reopened.query(AppDatabase.favoriteThreadCategoryTable),
      isEmpty,
    );
    expect(await reopened.getVersion(), 41);
    expect((await reopened.rawQuery('PRAGMA foreign_key_check')), isEmpty);
  });
}

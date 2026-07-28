import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/local/comic_local_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/library_shared/domain/models/library_operation_failure.dart';

class ComicShelfStore {
  ComicShelfStore(this._dbFuture, {this.defaultCategoryId = 'default'});

  final Future<Database> _dbFuture;
  final String defaultCategoryId;

  Future<List<ComicShelfCategory>> getCategories() async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.categoriesTable,
      orderBy: 'sort_order ASC, created_at ASC',
    );

    return rows
        .map(
          (row) => ComicShelfCategory(
            categoryId: row['category_id'] as String,
            name: row['name'] as String,
            sortOrder: row['sort_order'] as int,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              row['created_at'] as int,
            ),
          ),
        )
        .toList(growable: false);
  }

  Future<String> createCategory({required String name}) async {
    final sanitized = name.trim();
    if (sanitized.isEmpty) {
      throw ArgumentError('分类名称不能为空');
    }

    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    final categoryId = 'c$now${Random().nextInt(1000)}';

    await db.transaction((txn) async {
      final countResult = await txn.rawQuery(
        'SELECT COUNT(*) AS count FROM ${ComicLocalDb.categoriesTable}',
      );
      final sortOrder = (countResult.first['count'] as int?) ?? 0;

      await txn.insert(ComicLocalDb.categoriesTable, <String, Object?>{
        'category_id': categoryId,
        'name': sanitized,
        'sort_order': sortOrder,
        'created_at': now,
      });
    });

    return categoryId;
  }

  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {
    final sanitized = newName.trim();
    if (sanitized.isEmpty) {
      throw ArgumentError('分类名称不能为空');
    }
    if (categoryId == defaultCategoryId) {
      throw const LibraryOperationException(
        LibraryOperationFailureCode.defaultCategoryImmutable,
      );
    }

    final db = await _dbFuture;
    await db.update(
      ComicLocalDb.categoriesTable,
      <String, Object?>{'name': sanitized},
      where: 'category_id = ?',
      whereArgs: <Object>[categoryId],
    );
  }

  Future<void> deleteCategory({required String categoryId}) async {
    if (categoryId == defaultCategoryId) {
      throw const LibraryOperationException(
        LibraryOperationFailureCode.defaultCategoryImmutable,
      );
    }

    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      final rows = await txn.query(
        ComicLocalDb.shelfItemsTable,
        columns: <String>['comic_id'],
        where: 'category_id = ?',
        whereArgs: <Object>[categoryId],
      );

      for (final row in rows) {
        final comicId = row['comic_id'] as String;
        final existsInDefault = await txn.query(
          ComicLocalDb.shelfItemsTable,
          columns: <String>['id'],
          where: 'category_id = ? AND comic_id = ?',
          whereArgs: <Object>[defaultCategoryId, comicId],
          limit: 1,
        );

        if (existsInDefault.isEmpty) {
          final sortOrder = await nextSortOrderInTxn(
            txn,
            categoryId: defaultCategoryId,
          );
          await txn.insert(
            ComicLocalDb.shelfItemsTable,
            ShelfItemRecord(
              categoryId: defaultCategoryId,
              comicId: comicId,
              addedAt: now,
              sortOrder: sortOrder,
            ).toMap(),
          );
        }
      }

      await txn.delete(
        ComicLocalDb.shelfItemsTable,
        where: 'category_id = ?',
        whereArgs: <Object>[categoryId],
      );

      await txn.delete(
        ComicLocalDb.categoriesTable,
        where: 'category_id = ?',
        whereArgs: <Object>[categoryId],
      );
    });
  }

  Future<void> moveComicToCategory({
    required String comicId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {
    if (fromCategoryId == toCategoryId) {
      return;
    }

    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      final targetExists = await txn.query(
        ComicLocalDb.shelfItemsTable,
        columns: <String>['id'],
        where: 'category_id = ? AND comic_id = ?',
        whereArgs: <Object>[toCategoryId, comicId],
        limit: 1,
      );

      if (targetExists.isEmpty) {
        final sortOrder = await nextSortOrderInTxn(
          txn,
          categoryId: toCategoryId,
        );
        await txn.insert(
          ComicLocalDb.shelfItemsTable,
          ShelfItemRecord(
            categoryId: toCategoryId,
            comicId: comicId,
            addedAt: now,
            sortOrder: sortOrder,
          ).toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      await txn.delete(
        ComicLocalDb.shelfItemsTable,
        where: 'category_id = ? AND comic_id = ?',
        whereArgs: <Object>[fromCategoryId, comicId],
      );
    });
  }

  Future<ComicShelfDisplaySettings> getDisplaySettings() async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.settingsTable,
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object>['grid_column_count'],
      limit: 1,
    );

    final value = rows.isEmpty ? null : rows.first['value'] as String;
    final parsed = int.tryParse(value ?? '');
    return ComicShelfDisplaySettings(
      gridColumnCount: normalizeColumnCount(parsed ?? 3),
    );
  }

  Future<void> updateGridColumnCount({required int columnCount}) async {
    final db = await _dbFuture;
    final normalized = normalizeColumnCount(columnCount);

    await db.insert(ComicLocalDb.settingsTable, <String, Object?>{
      'key': 'grid_column_count',
      'value': normalized.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> isInShelf({required String comicId}) async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.shelfItemsTable,
      columns: <String>['id'],
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<List<ComicShelfItem>> getShelfItems({
    String categoryId = 'default',
  }) async {
    final db = await _dbFuture;
    final rows = await db.rawQuery(
      '''
      SELECT
        si.category_id,
        si.added_at,
        c.comic_id,
        c.source_typeid,
        c.source_tag_name,
        c.title,
        c.source_title,
        c.custom_title,
        c.author,
        c.source_author,
        c.custom_author,
        c.translation_group,
        c.source_translation_group,
        c.custom_translation_group,
        c.custom_search_title,
        COALESCE(c.custom_cover_image_url, c.cover_image_url) AS cover_image_url,
        c.custom_cover_image_url,
        c.cover_local_path,
        c.custom_cover_local_path,
        c.custom_cover_focus_x,
        c.custom_cover_focus_y
      FROM ${ComicLocalDb.shelfItemsTable} si
      INNER JOIN ${ComicLocalDb.comicsTable} c
        ON si.comic_id = c.comic_id
      WHERE si.category_id = ?
      ORDER BY si.sort_order ASC, si.added_at DESC
    ''',
      <Object>[categoryId],
    );

    return rows
        .map(
          (row) => ComicShelfItem(
            comicId: row['comic_id'] as String,
            sourceTypeId: row['source_typeid'] as String?,
            sourceTagName: row['source_tag_name'] as String?,
            title: row['title'] as String,
            sourceTitle: row['source_title'] as String?,
            customTitle: row['custom_title'] as String?,
            author: row['author'] as String?,
            sourceAuthor: row['source_author'] as String?,
            customAuthor: row['custom_author'] as String?,
            translationGroup: row['translation_group'] as String?,
            sourceTranslationGroup: row['source_translation_group'] as String?,
            customTranslationGroup: row['custom_translation_group'] as String?,
            customSearchTitle: row['custom_search_title'] as String?,
            coverImageUrl: row['cover_image_url'] as String?,
            customCoverImageUrl: row['custom_cover_image_url'] as String?,
            coverLocalPath: row['cover_local_path'] as String?,
            customCoverLocalPath: row['custom_cover_local_path'] as String?,
            customCoverFocusX: (row['custom_cover_focus_x'] as num?)
                ?.toDouble(),
            customCoverFocusY: (row['custom_cover_focus_y'] as num?)
                ?.toDouble(),
            categoryId: row['category_id'] as String,
            addedAt: DateTime.fromMillisecondsSinceEpoch(
              row['added_at'] as int,
            ),
          ),
        )
        .toList(growable: false);
  }

  Future<void> removeFromShelf({required String comicId}) async {
    final db = await _dbFuture;
    await db.delete(
      ComicLocalDb.shelfItemsTable,
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
  }

  Future<void> ensureShelfItemExistsInTxn(
    DatabaseExecutor executor, {
    required String categoryId,
    required String comicId,
    required int addedAt,
  }) async {
    final existingShelfRows = await executor.query(
      ComicLocalDb.shelfItemsTable,
      columns: <String>['id'],
      where: 'category_id = ? AND comic_id = ?',
      whereArgs: <Object>[categoryId, comicId],
      limit: 1,
    );

    if (existingShelfRows.isNotEmpty) {
      return;
    }

    final sortOrder = await nextSortOrderInTxn(
      executor,
      categoryId: categoryId,
    );
    await executor.insert(
      ComicLocalDb.shelfItemsTable,
      ShelfItemRecord(
        categoryId: categoryId,
        comicId: comicId,
        addedAt: addedAt,
        sortOrder: sortOrder,
      ).toMap(),
    );
  }

  Future<int> nextSortOrderInTxn(
    DatabaseExecutor executor, {
    required String categoryId,
  }) async {
    final countResult = await executor.rawQuery(
      'SELECT COUNT(*) AS count FROM ${ComicLocalDb.shelfItemsTable} '
      'WHERE category_id = ?',
      <Object>[categoryId],
    );
    return (countResult.first['count'] as int?) ?? 0;
  }

  int normalizeColumnCount(int value) {
    if (value < 2) {
      return 2;
    }
    if (value > 4) {
      return 4;
    }
    return value;
  }
}

import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/favorites/data/repositories/local/favorite_cache_row_mapper.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';

/// Owns category assignment, visibility and category write transactions.
class FavoriteCategoryStore {
  const FavoriteCategoryStore(this._dbFuture);

  final Future<Database> _dbFuture;

  static const Set<String> _systemCategoryIds = <String>{
    favoriteDefaultCategoryId,
    favoriteComicCategoryId,
    favoriteNovelCategoryId,
    favoriteInvalidCategoryId,
  };

  Future<List<LibraryCategory>> loadVisibleCategories() async {
    final db = await _dbFuture;
    final now = DateTime.fromMillisecondsSinceEpoch(0);
    final categories = <LibraryCategory>[];

    final comicCount = await _countSystemCategory(db, favoriteComicCategoryId);
    if (comicCount > 0) {
      categories.add(
        LibraryCategory(
          categoryId: favoriteComicCategoryId,
          name: '漫画',
          sortOrder: 0,
          createdAt: now,
          visibleMatchCount: comicCount,
        ),
      );
    }

    final novelCount = await _countSystemCategory(db, favoriteNovelCategoryId);
    if (novelCount > 0) {
      categories.add(
        LibraryCategory(
          categoryId: favoriteNovelCategoryId,
          name: '小说',
          sortOrder: 1,
          createdAt: now,
          visibleMatchCount: novelCount,
        ),
      );
    }

    final invalidCount = await _countSystemCategory(
      db,
      favoriteInvalidCategoryId,
    );
    if (invalidCount > 0) {
      categories.add(
        LibraryCategory(
          categoryId: favoriteInvalidCategoryId,
          name: '无效',
          sortOrder: 2,
          createdAt: now,
          visibleMatchCount: invalidCount,
        ),
      );
    }

    final defaultCount = await _countSystemCategory(
      db,
      favoriteDefaultCategoryId,
    );
    if (defaultCount > 0) {
      categories.add(
        LibraryCategory(
          categoryId: favoriteDefaultCategoryId,
          name: '默认',
          sortOrder: 3,
          createdAt: now,
          visibleMatchCount: defaultCount,
        ),
      );
    }

    final customRows = await db.query(
      AppDatabase.favoriteCategoriesTable,
      orderBy: 'sort_order ASC, created_at ASC',
    );
    for (final row in customRows) {
      final categoryId = row['category_id'] as String;
      categories.add(
        LibraryCategory(
          categoryId: categoryId,
          name: row['name'] as String,
          sortOrder: (row['sort_order'] as int? ?? 0) + 100,
          createdAt: FavoriteCacheRowMapper.dateTime(row['created_at']) ?? now,
          visibleMatchCount: await _countCustomCategory(db, categoryId),
        ),
      );
    }

    return categories;
  }

  Future<String> createCategory({required String name}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('分类名称不能为空');
    }
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    final categoryId = 'fav_$now${Random().nextInt(1000)}';
    final countRows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM ${AppDatabase.favoriteCategoriesTable}',
    );
    final sortOrder = countRows.first['count'] as int? ?? 0;
    await db.insert(AppDatabase.favoriteCategoriesTable, <String, Object?>{
      'category_id': categoryId,
      'name': trimmed,
      'sort_order': sortOrder,
      'created_at': now,
    });
    return categoryId;
  }

  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {
    if (_systemCategoryIds.contains(categoryId)) {
      return;
    }
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('分类名称不能为空');
    }
    final db = await _dbFuture;
    await db.update(
      AppDatabase.favoriteCategoriesTable,
      <String, Object?>{'name': trimmed},
      where: 'category_id = ?',
      whereArgs: <Object>[categoryId],
    );
  }

  Future<void> deleteCategory({required String categoryId}) async {
    if (_systemCategoryIds.contains(categoryId)) {
      return;
    }
    final db = await _dbFuture;
    await db.transaction((txn) async {
      await txn.delete(
        AppDatabase.favoriteThreadCategoryTable,
        where: 'category_id = ?',
        whereArgs: <Object>[categoryId],
      );
      await txn.delete(
        AppDatabase.favoriteCategoriesTable,
        where: 'category_id = ?',
        whereArgs: <Object>[categoryId],
      );
    });
  }

  Future<void> moveThreadToCategory({
    required String tid,
    required String toCategoryId,
  }) async {
    final db = await _dbFuture;
    final normalizedTid = tid.trim();
    if (_systemCategoryIds.contains(toCategoryId)) {
      await db.delete(
        AppDatabase.favoriteThreadCategoryTable,
        where: 'tid = ?',
        whereArgs: <Object>[normalizedTid],
      );
      return;
    }

    await db.insert(
      AppDatabase.favoriteThreadCategoryTable,
      <String, Object?>{
        'tid': normalizedTid,
        'category_id': toCategoryId,
        'assigned_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> _countSystemCategory(Database db, String categoryId) async {
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS count
      FROM ${AppDatabase.favoriteThreadsTable} ft
      LEFT JOIN ${AppDatabase.favoriteThreadCategoryTable} fc
        ON fc.tid = ft.tid
      WHERE ft.removed_at IS NULL
        AND ${_systemCategoryAssignmentSqlCondition(categoryId)}
        AND ${_systemCategorySqlCondition(categoryId)}
      ''');
    return rows.first['count'] as int? ?? 0;
  }

  Future<int> _countCustomCategory(Database db, String categoryId) async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM ${AppDatabase.favoriteThreadsTable} ft
      INNER JOIN ${AppDatabase.favoriteThreadCategoryTable} fc
        ON fc.tid = ft.tid
      WHERE ft.removed_at IS NULL
        AND fc.category_id = ?
        AND ft.detail_state <> 'invalid'
      ''',
      <Object>[categoryId],
    );
    return rows.first['count'] as int? ?? 0;
  }

  Future<List<FavoriteThreadCacheRecord>> loadRecordsForCategory(
    Database db,
    String categoryId,
  ) async {
    final List<Map<String, Object?>> rows;
    if (_systemCategoryIds.contains(categoryId)) {
      rows = await db.rawQuery('''
        SELECT ft.*, fc.category_id AS custom_category_id
        FROM ${AppDatabase.favoriteThreadsTable} ft
        LEFT JOIN ${AppDatabase.favoriteThreadCategoryTable} fc
          ON fc.tid = ft.tid
        WHERE ft.removed_at IS NULL
          AND ${_systemCategoryAssignmentSqlCondition(categoryId)}
          AND ${_systemCategorySqlCondition(categoryId)}
        ORDER BY ft.remote_order ASC, ft.dateline DESC, ft.last_seen_at DESC
        ''');
    } else {
      rows = await db.rawQuery(
        '''
        SELECT ft.*, fc.category_id AS custom_category_id
        FROM ${AppDatabase.favoriteThreadsTable} ft
        INNER JOIN ${AppDatabase.favoriteThreadCategoryTable} fc
          ON fc.tid = ft.tid
        WHERE ft.removed_at IS NULL
          AND fc.category_id = ?
          AND ft.detail_state <> 'invalid'
        ORDER BY ft.remote_order ASC, ft.dateline DESC, ft.last_seen_at DESC
        ''',
        <Object>[categoryId],
      );
    }
    return rows.map(FavoriteCacheRowMapper.record).toList(growable: false);
  }

  Future<List<LibraryCategory>> loadSnapshotCategories(
    Database db, {
    required Map<String, int> rawCountByCategory,
  }) async {
    final now = DateTime.fromMillisecondsSinceEpoch(0);
    final categories = <LibraryCategory>[];

    final comicCount = rawCountByCategory[favoriteComicCategoryId] ?? 0;
    if (comicCount > 0) {
      categories.add(
        LibraryCategory(
          categoryId: favoriteComicCategoryId,
          name: '漫画',
          sortOrder: 0,
          createdAt: now,
          visibleMatchCount: comicCount,
        ),
      );
    }

    final novelCount = rawCountByCategory[favoriteNovelCategoryId] ?? 0;
    if (novelCount > 0) {
      categories.add(
        LibraryCategory(
          categoryId: favoriteNovelCategoryId,
          name: '小说',
          sortOrder: 1,
          createdAt: now,
          visibleMatchCount: novelCount,
        ),
      );
    }

    final invalidCount = rawCountByCategory[favoriteInvalidCategoryId] ?? 0;
    if (invalidCount > 0) {
      categories.add(
        LibraryCategory(
          categoryId: favoriteInvalidCategoryId,
          name: '无效',
          sortOrder: 2,
          createdAt: now,
          visibleMatchCount: invalidCount,
        ),
      );
    }

    final defaultCount = rawCountByCategory[favoriteDefaultCategoryId] ?? 0;
    if (defaultCount > 0) {
      categories.add(
        LibraryCategory(
          categoryId: favoriteDefaultCategoryId,
          name: '默认',
          sortOrder: 3,
          createdAt: now,
          visibleMatchCount: defaultCount,
        ),
      );
    }

    final customRows = await db.query(
      AppDatabase.favoriteCategoriesTable,
      orderBy: 'sort_order ASC, created_at ASC',
    );
    for (final row in customRows) {
      final categoryId = row['category_id'] as String;
      categories.add(
        LibraryCategory(
          categoryId: categoryId,
          name: row['name'] as String,
          sortOrder: (row['sort_order'] as int? ?? 0) + 100,
          createdAt: FavoriteCacheRowMapper.dateTime(row['created_at']) ?? now,
          visibleMatchCount: rawCountByCategory[categoryId] ?? 0,
        ),
      );
    }

    return categories;
  }

  String _systemCategorySqlCondition(String categoryId) {
    switch (categoryId) {
      case favoriteComicCategoryId:
        return "ft.detail_state <> 'invalid' AND ft.content_kind = 'comic'";
      case favoriteNovelCategoryId:
        return "ft.detail_state <> 'invalid' AND ft.content_kind = 'novel'";
      case favoriteInvalidCategoryId:
        return "ft.detail_state = 'invalid'";
      case favoriteDefaultCategoryId:
      default:
        return "ft.detail_state <> 'invalid' AND "
            "(ft.content_kind IS NULL OR ft.content_kind NOT IN ('comic', 'novel'))";
    }
  }

  String _systemCategoryAssignmentSqlCondition(String categoryId) {
    return categoryId == favoriteInvalidCategoryId
        ? '1 = 1'
        : 'fc.category_id IS NULL';
  }
}

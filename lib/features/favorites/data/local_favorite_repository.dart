import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/favorites/domain/favorite_cache_models.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

abstract class LocalFavoriteRepository {
  Future<FavoriteSyncSnapshot?> getSyncSnapshot();

  Future<int> countActiveThreads();

  Future<Set<String>> getActiveTids();

  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsForSnapshot();

  Future<void> finishSync({
    required FavoriteSyncMode mode,
    required int remoteCount,
    String? status,
    String? message,
  });

  Future<void> markSyncFailure(String message);

  Future<int> upsertRemotePage({
    required FavoriteThreadsPage page,
    required int pageStartOrder,
  });

  Future<List<FavoriteThreadCacheRecord>> getMissingDetailRecords({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  });

  Future<void> updateThreadDetailMeta({
    required String tid,
    required String fid,
    required String typeid,
    required String? tagName,
    required ThreadContentKind contentKind,
    required String? workId,
  });

  Future<List<FavoriteThreadCacheRecord>> markRemovedTids(
    Set<String> activeRemoteTids,
  );

  Future<FavoriteThreadCacheRecord?> getActiveThreadByTid(String tid);

  Future<FavoriteRouteTarget?> getRouteTargetByShelfWorkId(String workId);

  Future<List<LibraryCategory>> loadVisibleCategories();

  Future<List<LibraryWorkItem>> loadCategoryItems(String categoryId);

  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  });

  Future<String> createCategory({required String name});

  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  });

  Future<void> deleteCategory({required String categoryId});

  Future<void> moveThreadToCategory({
    required String tid,
    required String toCategoryId,
  });

  Future<String?> pickRandomWorkId({required String categoryId});
}

class SqfliteLocalFavoriteRepository implements LocalFavoriteRepository {
  SqfliteLocalFavoriteRepository(this._dbFuture);

  final Future<Database> _dbFuture;

  static const Set<String> _systemCategoryIds = <String>{
    favoriteDefaultCategoryId,
    favoriteComicCategoryId,
    favoriteNovelCategoryId,
  };

  @override
  Future<FavoriteSyncSnapshot?> getSyncSnapshot() async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.favoriteSyncStateTable,
      where: 'sync_key = ?',
      whereArgs: <Object>[favoriteSyncKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _snapshotFromRow(rows.first);
  }

  @override
  Future<int> countActiveThreads() async {
    final db = await _dbFuture;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM ${ComicLocalDb.favoriteThreadsTable}
      WHERE removed_at IS NULL
      ''',
    );
    return rows.first['count'] as int? ?? 0;
  }

  @override
  Future<Set<String>> getActiveTids() async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.favoriteThreadsTable,
      columns: <String>['tid'],
      where: 'removed_at IS NULL',
    );
    return rows.map((row) => row['tid'] as String).toSet();
  }

  @override
  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsForSnapshot() async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.favoriteThreadsTable,
      where: 'removed_at IS NULL',
      orderBy: 'remote_order ASC, last_seen_at DESC',
    );
    return rows.map(_recordFromRow).toList(growable: false);
  }

  @override
  Future<void> finishSync({
    required FavoriteSyncMode mode,
    required int remoteCount,
    String? status,
    String? message,
  }) async {
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    final localActiveCount = await countActiveThreads();
    final old = await getSyncSnapshot();

    await db.insert(
      ComicLocalDb.favoriteSyncStateTable,
      <String, Object?>{
        'sync_key': favoriteSyncKey,
        'remote_count': remoteCount,
        'local_active_count': localActiveCount,
        'last_synced_at': now,
        'last_full_synced_at': mode == FavoriteSyncMode.fullDiff
            ? now
            : old?.lastFullSyncedAt?.millisecondsSinceEpoch,
        'status': status ?? 'ok',
        'message': message,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> markSyncFailure(String message) async {
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    final old = await getSyncSnapshot();
    await db.insert(
      ComicLocalDb.favoriteSyncStateTable,
      <String, Object?>{
        'sync_key': favoriteSyncKey,
        'remote_count': old?.remoteCount ?? 0,
        'local_active_count': await countActiveThreads(),
        'last_synced_at': old?.lastSyncedAt?.millisecondsSinceEpoch,
        'last_full_synced_at': old?.lastFullSyncedAt?.millisecondsSinceEpoch,
        'status': 'failed',
        'message': message,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await db.update(
      ComicLocalDb.favoriteSyncStateTable,
      <String, Object?>{'last_synced_at': now},
      where: 'sync_key = ?',
      whereArgs: <Object>[favoriteSyncKey],
    );
  }

  @override
  Future<int> upsertRemotePage({
    required FavoriteThreadsPage page,
    required int pageStartOrder,
  }) async {
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = 0;

    await db.transaction((txn) async {
      for (var index = 0; index < page.items.length; index++) {
        final item = page.items[index];
        final tid = item.tid.trim();
        if (tid.isEmpty) {
          continue;
        }

        final oldRows = await txn.query(
          ComicLocalDb.favoriteThreadsTable,
          where: 'tid = ?',
          whereArgs: <Object>[tid],
          limit: 1,
        );
        final old = oldRows.isEmpty ? null : oldRows.first;
        final firstSeenAt = (old?['first_seen_at'] as int?) ?? now;

        final values = <String, Object?>{
          'tid': tid,
          'favid': _normalizeNullable(item.favid),
          'title': _nonEmpty(item.title, fallback: '未命名收藏'),
          'description': _normalizeNullable(item.description),
          'author': _normalizeNullable(item.author),
          'replies': item.replies,
          'url': _normalizeNullable(item.url),
          'dateline': item.dateline == 0 ? null : item.dateline,
          'remote_order': pageStartOrder + index,
          'first_seen_at': firstSeenAt,
          'last_seen_at': now,
          'removed_at': null,
        };

        if (old == null) {
          await txn.insert(
            ComicLocalDb.favoriteThreadsTable,
            <String, Object?>{
              ...values,
              'source_fid': null,
              'source_typeid': null,
              'source_tag_name': null,
              'content_kind': 'unknown',
              'work_id': null,
              'detail_loaded_at': null,
            },
          );
        } else {
          await txn.update(
            ComicLocalDb.favoriteThreadsTable,
            values,
            where: 'tid = ?',
            whereArgs: <Object>[tid],
          );
        }
        changed++;
      }
    });

    return changed;
  }

  @override
  Future<List<FavoriteThreadCacheRecord>> getMissingDetailRecords({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async {
    final db = await _dbFuture;
    final queryLimit = limit + excludedTids.length;
    final rows = await db.rawQuery(
      '''
      SELECT ft.*, fc.category_id AS custom_category_id
      FROM ${ComicLocalDb.favoriteThreadsTable} ft
      LEFT JOIN ${ComicLocalDb.favoriteThreadCategoryTable} fc
        ON fc.tid = ft.tid
      WHERE ft.removed_at IS NULL
        AND ft.detail_loaded_at IS NULL
      ORDER BY ft.remote_order ASC, ft.last_seen_at DESC
      LIMIT ?
      ''',
      <Object>[queryLimit],
    );
    return rows
        .map(_recordFromRow)
        .where((record) => !excludedTids.contains(record.tid))
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<void> updateThreadDetailMeta({
    required String tid,
    required String fid,
    required String typeid,
    required String? tagName,
    required ThreadContentKind contentKind,
    required String? workId,
  }) async {
    final db = await _dbFuture;
    await db.update(
      ComicLocalDb.favoriteThreadsTable,
      <String, Object?>{
        'source_fid': _normalizeNullable(fid),
        'source_typeid': _normalizeNullable(typeid),
        'source_tag_name': _normalizeNullable(tagName),
        'content_kind': favoriteContentKindToDb(contentKind),
        'work_id': _normalizeNullable(workId),
        'detail_loaded_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'tid = ?',
      whereArgs: <Object>[tid.trim()],
    );
  }

  @override
  Future<List<FavoriteThreadCacheRecord>> markRemovedTids(
    Set<String> activeRemoteTids,
  ) async {
    final db = await _dbFuture;
    final activeRows = await db.rawQuery(
      '''
      SELECT ft.*, fc.category_id AS custom_category_id
      FROM ${ComicLocalDb.favoriteThreadsTable} ft
      LEFT JOIN ${ComicLocalDb.favoriteThreadCategoryTable} fc
        ON fc.tid = ft.tid
      WHERE ft.removed_at IS NULL
      ''',
    );
    final removed = activeRows
        .map(_recordFromRow)
        .where((record) => !activeRemoteTids.contains(record.tid))
        .toList(growable: false);
    if (removed.isEmpty) {
      return removed;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      for (final record in removed) {
        await txn.update(
          ComicLocalDb.favoriteThreadsTable,
          <String, Object?>{'removed_at': now},
          where: 'tid = ?',
          whereArgs: <Object>[record.tid],
        );
      }
    });
    return removed;
  }

  @override
  Future<FavoriteThreadCacheRecord?> getActiveThreadByTid(String tid) async {
    final db = await _dbFuture;
    final rows = await db.rawQuery(
      '''
      SELECT ft.*, fc.category_id AS custom_category_id
      FROM ${ComicLocalDb.favoriteThreadsTable} ft
      LEFT JOIN ${ComicLocalDb.favoriteThreadCategoryTable} fc
        ON fc.tid = ft.tid
      WHERE ft.tid = ? AND ft.removed_at IS NULL
      LIMIT 1
      ''',
      <Object>[tid.trim()],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _recordFromRow(rows.first);
  }

  @override
  Future<FavoriteRouteTarget?> getRouteTargetByShelfWorkId(String workId) async {
    final tid = FavoriteShelfWorkId.parseTid(workId);
    if (tid == null) {
      return null;
    }
    final record = await getActiveThreadByTid(tid);
    if (record == null) {
      return null;
    }
    return FavoriteRouteTarget(
      tid: record.tid,
      title: record.title,
      contentKind: record.contentKind,
      workId: record.workId,
    );
  }

  @override
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

    final defaultCount = await _countSystemCategory(db, favoriteDefaultCategoryId);
    if (defaultCount > 0) {
      categories.add(
        LibraryCategory(
          categoryId: favoriteDefaultCategoryId,
          name: '默认',
          sortOrder: 2,
          createdAt: now,
          visibleMatchCount: defaultCount,
        ),
      );
    }

    final customRows = await db.query(
      ComicLocalDb.favoriteCategoriesTable,
      orderBy: 'sort_order ASC, created_at ASC',
    );
    for (final row in customRows) {
      final categoryId = row['category_id'] as String;
      categories.add(
        LibraryCategory(
          categoryId: categoryId,
          name: row['name'] as String,
          sortOrder: (row['sort_order'] as int? ?? 0) + 100,
          createdAt: _toDateTime(row['created_at']) ?? now,
          visibleMatchCount: await _countCustomCategory(db, categoryId),
        ),
      );
    }

    return categories;
  }

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems(String categoryId) async {
    final db = await _dbFuture;
    final records = await _loadRecordsForCategory(db, categoryId);
    return Future.wait(records.map((record) => _mapWorkItem(db, record)));
  }

  @override
  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    final normalizedKeyword = keyword.trim().toLowerCase();
    final result = <String, List<LibraryWorkItem>>{};
    for (final category in categories) {
      var items = await loadCategoryItems(category.categoryId);
      items = items.where((item) {
        if (normalizedKeyword.isNotEmpty) {
          final title = item.title.toLowerCase();
          final secondary = (item.secondaryName ?? '').toLowerCase();
          if (!title.contains(normalizedKeyword) && !secondary.contains(normalizedKeyword)) {
            return false;
          }
        }
        return _matchesFilters(item, filters);
      }).toList(growable: false);
      result[category.categoryId] = _sortItems(items, sortOption);
    }
    return result;
  }

  @override
  Future<String> createCategory({required String name}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('分类名称不能为空');
    }
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    final categoryId = 'fav_$now${Random().nextInt(1000)}';
    final countRows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM ${ComicLocalDb.favoriteCategoriesTable}',
    );
    final sortOrder = countRows.first['count'] as int? ?? 0;
    await db.insert(
      ComicLocalDb.favoriteCategoriesTable,
      <String, Object?>{
        'category_id': categoryId,
        'name': trimmed,
        'sort_order': sortOrder,
        'created_at': now,
      },
    );
    return categoryId;
  }

  @override
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
      ComicLocalDb.favoriteCategoriesTable,
      <String, Object?>{'name': trimmed},
      where: 'category_id = ?',
      whereArgs: <Object>[categoryId],
    );
  }

  @override
  Future<void> deleteCategory({required String categoryId}) async {
    if (_systemCategoryIds.contains(categoryId)) {
      return;
    }
    final db = await _dbFuture;
    await db.transaction((txn) async {
      await txn.delete(
        ComicLocalDb.favoriteThreadCategoryTable,
        where: 'category_id = ?',
        whereArgs: <Object>[categoryId],
      );
      await txn.delete(
        ComicLocalDb.favoriteCategoriesTable,
        where: 'category_id = ?',
        whereArgs: <Object>[categoryId],
      );
    });
  }

  @override
  Future<void> moveThreadToCategory({
    required String tid,
    required String toCategoryId,
  }) async {
    final db = await _dbFuture;
    final normalizedTid = tid.trim();
    if (_systemCategoryIds.contains(toCategoryId)) {
      await db.delete(
        ComicLocalDb.favoriteThreadCategoryTable,
        where: 'tid = ?',
        whereArgs: <Object>[normalizedTid],
      );
      return;
    }

    await db.insert(
      ComicLocalDb.favoriteThreadCategoryTable,
      <String, Object?>{
        'tid': normalizedTid,
        'category_id': toCategoryId,
        'assigned_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<String?> pickRandomWorkId({required String categoryId}) async {
    final items = await loadCategoryItems(categoryId);
    if (items.isEmpty) {
      return null;
    }
    final random = Random();
    return items[random.nextInt(items.length)].workId;
  }

  Future<int> _countSystemCategory(Database db, String categoryId) async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM ${ComicLocalDb.favoriteThreadsTable} ft
      LEFT JOIN ${ComicLocalDb.favoriteThreadCategoryTable} fc
        ON fc.tid = ft.tid
      WHERE ft.removed_at IS NULL
        AND fc.category_id IS NULL
        AND ${_systemCategorySqlCondition(categoryId)}
      ''',
    );
    return rows.first['count'] as int? ?? 0;
  }

  Future<int> _countCustomCategory(Database db, String categoryId) async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM ${ComicLocalDb.favoriteThreadsTable} ft
      INNER JOIN ${ComicLocalDb.favoriteThreadCategoryTable} fc
        ON fc.tid = ft.tid
      WHERE ft.removed_at IS NULL
        AND fc.category_id = ?
      ''',
      <Object>[categoryId],
    );
    return rows.first['count'] as int? ?? 0;
  }

  Future<List<FavoriteThreadCacheRecord>> _loadRecordsForCategory(
    Database db,
    String categoryId,
  ) async {
    final List<Map<String, Object?>> rows;
    if (_systemCategoryIds.contains(categoryId)) {
      rows = await db.rawQuery(
        '''
        SELECT ft.*, fc.category_id AS custom_category_id
        FROM ${ComicLocalDb.favoriteThreadsTable} ft
        LEFT JOIN ${ComicLocalDb.favoriteThreadCategoryTable} fc
          ON fc.tid = ft.tid
        WHERE ft.removed_at IS NULL
          AND fc.category_id IS NULL
          AND ${_systemCategorySqlCondition(categoryId)}
        ORDER BY ft.remote_order ASC, ft.dateline DESC, ft.last_seen_at DESC
        ''',
      );
    } else {
      rows = await db.rawQuery(
        '''
        SELECT ft.*, fc.category_id AS custom_category_id
        FROM ${ComicLocalDb.favoriteThreadsTable} ft
        INNER JOIN ${ComicLocalDb.favoriteThreadCategoryTable} fc
          ON fc.tid = ft.tid
        WHERE ft.removed_at IS NULL
          AND fc.category_id = ?
        ORDER BY ft.remote_order ASC, ft.dateline DESC, ft.last_seen_at DESC
        ''',
        <Object>[categoryId],
      );
    }
    return rows.map(_recordFromRow).toList(growable: false);
  }

  String _systemCategorySqlCondition(String categoryId) {
    switch (categoryId) {
      case favoriteComicCategoryId:
        return "ft.content_kind = 'comic'";
      case favoriteNovelCategoryId:
        return "ft.content_kind = 'novel'";
      case favoriteDefaultCategoryId:
      default:
        return "(ft.content_kind IS NULL OR ft.content_kind NOT IN ('comic', 'novel'))";
    }
  }

  Future<LibraryWorkItem> _mapWorkItem(
    Database db,
    FavoriteThreadCacheRecord record,
  ) async {
    final tagRows = await db.rawQuery(
      '''
      SELECT 1
      FROM ${ComicLocalDb.libraryWorkTagsTable}
      WHERE content_type = ? AND work_id = ?
      LIMIT 1
      ''',
      <Object>['favorite', record.shelfWorkId],
    );
    final addedAt = record.dateline ?? record.firstSeenAt;
    final totalCount = max(1, record.replies + 1);
    final cover = await _loadModuleCover(db, record);
    return LibraryWorkItem(
      workId: record.shelfWorkId,
      categoryId: record.resolvedCategoryId,
      title: record.title,
      secondaryName: record.author,
      coverImageUrl: cover.coverImageUrl,
      coverLocalPath: cover.coverLocalPath,
      customCoverLocalPath: cover.customCoverLocalPath,
      unreadCount: 0,
      totalChapterCount: totalCount,
      readChapterCount: 0,
      addedAt: addedAt,
      workUpdatedAt: record.dateline,
      lastFetchedAt: record.detailLoadedAt,
      hasTags: tagRows.isNotEmpty,
    );
  }

  Future<_FavoriteCoverSnapshot> _loadModuleCover(
    Database db,
    FavoriteThreadCacheRecord record,
  ) async {
    // 收藏页自身只缓存线程元数据；封面归漫画/小说模块维护。
    // 列表模式展示时按 workId 轻量读取模块封面，避免复制缓存策略。
    final workId = record.workId?.trim();
    if (workId == null || workId.isEmpty) {
      return const _FavoriteCoverSnapshot.empty();
    }

    switch (record.contentKind) {
      case ThreadContentKind.comic:
        final rows = await db.query(
          ComicLocalDb.comicsTable,
          columns: const <String>[
            'cover_image_url',
            'custom_cover_image_url',
            'cover_local_path',
            'custom_cover_local_path',
          ],
          where: 'comic_id = ?',
          whereArgs: <Object>[workId],
          limit: 1,
        );
        return _coverSnapshotFromRows(rows);
      case ThreadContentKind.novel:
        final rows = await db.query(
          ComicLocalDb.worksTable,
          columns: const <String>[
            'cover_image_url',
            'cover_local_path',
            'custom_cover_local_path',
          ],
          where: 'work_id = ? AND content_type = ?',
          whereArgs: <Object>[workId, 'novel'],
          limit: 1,
        );
        return _coverSnapshotFromRows(rows);
      case ThreadContentKind.unknown:
      case ThreadContentKind.forum:
        return const _FavoriteCoverSnapshot.empty();
    }
  }

  _FavoriteCoverSnapshot _coverSnapshotFromRows(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) {
      return const _FavoriteCoverSnapshot.empty();
    }
    final row = rows.first;
    final customCoverImageUrl = row['custom_cover_image_url'] as String?;
    return _FavoriteCoverSnapshot(
      coverImageUrl: customCoverImageUrl ?? row['cover_image_url'] as String?,
      coverLocalPath: row['cover_local_path'] as String?,
      customCoverLocalPath: row['custom_cover_local_path'] as String?,
    );
  }

  bool _matchesFilters(LibraryWorkItem item, LibraryFilterSet filters) {
    return _matchesTriState(filters.downloaded, item.isDownloaded) &&
        _matchesTriState(filters.unread, item.unreadCount > 0) &&
        _matchesTriState(filters.read, item.readChapterCount > 0) &&
        _matchesTriState(filters.hasTags, item.hasTags);
  }

  bool _matchesTriState(TriStateFilterValue value, bool actual) {
    switch (value) {
      case TriStateFilterValue.ignore:
        return true;
      case TriStateFilterValue.include:
        return actual;
      case TriStateFilterValue.exclude:
        return !actual;
    }
  }

  List<LibraryWorkItem> _sortItems(
    List<LibraryWorkItem> source,
    LibraryShelfSortOption sortOption,
  ) {
    final items = List<LibraryWorkItem>.from(source);
    items.sort((a, b) {
      int cmp;
      switch (sortOption.field) {
        case LibraryShelfSortField.name:
          cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          break;
        case LibraryShelfSortField.chapterCount:
          cmp = a.totalChapterCount.compareTo(b.totalChapterCount);
          break;
        case LibraryShelfSortField.unreadCount:
          cmp = a.unreadCount.compareTo(b.unreadCount);
          break;
        case LibraryShelfSortField.workUpdatedAt:
          cmp = _dateOrEpoch(a.workUpdatedAt).compareTo(_dateOrEpoch(b.workUpdatedAt));
          break;
        case LibraryShelfSortField.fetchedAt:
          cmp = _dateOrEpoch(a.lastFetchedAt).compareTo(_dateOrEpoch(b.lastFetchedAt));
          break;
        case LibraryShelfSortField.lastCheckedAt:
          cmp = _dateOrEpoch(a.lastCheckedAt).compareTo(_dateOrEpoch(b.lastCheckedAt));
          break;
        case LibraryShelfSortField.lastReadAt:
          cmp = _dateOrEpoch(a.lastReadAt).compareTo(_dateOrEpoch(b.lastReadAt));
          break;
        case LibraryShelfSortField.favoriteAddedAt:
          cmp = a.addedAt.compareTo(b.addedAt);
          break;
      }
      return sortOption.direction == LibrarySortDirection.desc ? -cmp : cmp;
    });
    return items;
  }

  FavoriteSyncSnapshot _snapshotFromRow(Map<String, Object?> row) {
    return FavoriteSyncSnapshot(
      syncKey: row['sync_key'] as String,
      remoteCount: row['remote_count'] as int? ?? 0,
      localActiveCount: row['local_active_count'] as int? ?? 0,
      lastSyncedAt: _toDateTime(row['last_synced_at']),
      lastFullSyncedAt: _toDateTime(row['last_full_synced_at']),
      status: row['status'] as String?,
      message: row['message'] as String?,
    );
  }

  FavoriteThreadCacheRecord _recordFromRow(Map<String, Object?> row) {
    return FavoriteThreadCacheRecord(
      tid: row['tid'] as String,
      favid: row['favid'] as String?,
      title: row['title'] as String,
      description: row['description'] as String?,
      author: row['author'] as String?,
      replies: row['replies'] as int? ?? 0,
      url: row['url'] as String?,
      dateline: _toDatelineDate(row['dateline']),
      remoteOrder: row['remote_order'] as int?,
      sourceFid: row['source_fid'] as String?,
      sourceTypeid: row['source_typeid'] as String?,
      sourceTagName: row['source_tag_name'] as String?,
      contentKind: favoriteContentKindFromDb(row['content_kind'] as String?),
      workId: row['work_id'] as String?,
      detailLoadedAt: _toDateTime(row['detail_loaded_at']),
      firstSeenAt: _toDateTime(row['first_seen_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      lastSeenAt: _toDateTime(row['last_seen_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      removedAt: _toDateTime(row['removed_at']),
      customCategoryId: row['custom_category_id'] as String?,
    );
  }

  DateTime _dateOrEpoch(DateTime? value) {
    return value ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  DateTime? _toDateTime(Object? value) {
    if (value is! int || value <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  DateTime? _toDatelineDate(Object? value) {
    if (value is! int || value <= 0) {
      return null;
    }
    final millis = value < 1000000000000 ? value * 1000 : value;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  String _nonEmpty(String value, {required String fallback}) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  String? _normalizeNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class _FavoriteCoverSnapshot {
  const _FavoriteCoverSnapshot({
    this.coverImageUrl,
    this.coverLocalPath,
    this.customCoverLocalPath,
  });

  const _FavoriteCoverSnapshot.empty()
      : coverImageUrl = null,
        coverLocalPath = null,
        customCoverLocalPath = null;

  final String? coverImageUrl;
  final String? coverLocalPath;
  final String? customCoverLocalPath;
}

import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/favorites/data/repositories/local/favorite_cache_row_mapper.dart';
import 'package:y300/features/favorites/data/repositories/local/favorite_category_store.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_query_utils.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_asset_factory.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

/// Reads shelves with the existing batch JOIN and compatibility queries.
class FavoriteShelfReadModel {
  const FavoriteShelfReadModel(
    this._dbFuture, {
    required FavoriteCategoryStore categoryStore,
  }) : _categoryStore = categoryStore;

  final Future<Database> _dbFuture;
  final FavoriteCategoryStore _categoryStore;

  Future<List<LibraryWorkItem>> loadCategoryItems(String categoryId) async {
    final db = await _dbFuture;
    final records = await _categoryStore.loadRecordsForCategory(db, categoryId);
    return Future.wait(records.map((record) => _mapWorkItem(db, record)));
  }

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
      items = items
          .where((item) {
            if (normalizedKeyword.isNotEmpty) {
              final title = item.title.toLowerCase();
              final secondary = (item.secondaryName ?? '').toLowerCase();
              if (!title.contains(normalizedKeyword) &&
                  !secondary.contains(normalizedKeyword)) {
                return false;
              }
            }
            return _matchesFilters(item, filters);
          })
          .toList(growable: false);
      result[category.categoryId] = _sortItems(items, sortOption);
    }
    return result;
  }

  Future<LibraryShelfSnapshot> queryShelfSnapshot({
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    final db = await _dbFuture;
    final rows = await db.rawQuery('''
      WITH favorite_tag_stats AS (
        SELECT work_id, 1 AS has_tags
        FROM ${AppDatabase.libraryWorkTagsTable}
        WHERE content_type = 'favorite'
        GROUP BY work_id
      )
      SELECT
        ft.*,
        fc.category_id AS custom_category_id,
        CASE
          WHEN ft.content_kind = 'comic' THEN COALESCE(c.custom_cover_image_url, c.cover_image_url)
          WHEN ft.content_kind = 'novel' AND w.cover_hidden = 0 THEN w.cover_image_url
          ELSE NULL
        END AS module_cover_image_url,
        CASE
          WHEN ft.content_kind = 'comic' THEN c.custom_cover_image_url
          ELSE NULL
        END AS module_custom_cover_image_url,
        CASE
          WHEN ft.content_kind = 'comic' THEN c.cover_local_path
          WHEN ft.content_kind = 'novel' AND w.cover_hidden = 0 THEN w.cover_local_path
          ELSE NULL
        END AS module_cover_local_path,
        CASE
          WHEN ft.content_kind = 'comic' THEN c.custom_cover_local_path
          WHEN ft.content_kind = 'novel' AND w.cover_hidden = 0 THEN w.custom_cover_local_path
          ELSE NULL
        END AS module_custom_cover_local_path,
        CASE
          WHEN ft.content_kind = 'comic' THEN c.cover_revision
          WHEN ft.content_kind = 'novel' THEN w.cover_revision
          ELSE 0
        END AS module_cover_revision,
        CASE
          WHEN ft.content_kind = 'comic' THEN c.custom_cover_revision
          WHEN ft.content_kind = 'novel' THEN w.custom_cover_revision
          ELSE 0
        END AS module_custom_cover_revision,
        COALESCE(tags.has_tags, 0) AS has_tags
      FROM ${AppDatabase.favoriteThreadsTable} ft
      LEFT JOIN ${AppDatabase.favoriteThreadCategoryTable} fc
        ON fc.tid = ft.tid
      LEFT JOIN ${AppDatabase.comicsTable} c
        ON ft.content_kind = 'comic' AND c.comic_id = ft.work_id
      LEFT JOIN ${AppDatabase.worksTable} w
        ON ft.content_kind = 'novel' AND w.work_id = ft.work_id AND w.content_type = 'novel'
      LEFT JOIN favorite_tag_stats tags
        ON tags.work_id = 'favorite:' || ft.tid
      WHERE ft.removed_at IS NULL
      ORDER BY ft.remote_order ASC, ft.dateline DESC, ft.last_seen_at DESC
      ''');

    final sourceByCategory = <String, List<LibraryWorkItem>>{};
    final rawCountByCategory = <String, int>{};
    for (final row in rows) {
      final item = _rowToSnapshotWorkItem(row);
      sourceByCategory
          .putIfAbsent(item.categoryId, () => <LibraryWorkItem>[])
          .add(item);
      rawCountByCategory[item.categoryId] =
          (rawCountByCategory[item.categoryId] ?? 0) + 1;
    }

    final categories = await _categoryStore.loadSnapshotCategories(
      db,
      rawCountByCategory: rawCountByCategory,
    );
    for (final category in categories) {
      sourceByCategory.putIfAbsent(
        category.categoryId,
        () => <LibraryWorkItem>[],
      );
    }

    final queried = LibraryShelfQueryUtils.filterAndSortByCategory(
      source: sourceByCategory,
      filters: filters,
      sortOption: sortOption,
      keyword: keyword,
    );
    return LibraryShelfSnapshot(
      categories: categories,
      itemsByCategory: queried,
      visibleMatchCountByCategory: LibraryShelfQueryUtils.countByCategory(
        queried,
      ),
    );
  }

  Future<String?> pickRandomWorkId({required String categoryId}) async {
    final items = await loadCategoryItems(categoryId);
    if (items.isEmpty) {
      return null;
    }
    final random = Random();
    return items[random.nextInt(items.length)].workId;
  }

  Future<LibraryWorkItem> _mapWorkItem(
    Database db,
    FavoriteThreadCacheRecord record,
  ) async {
    final tagRows = await db.rawQuery(
      '''
      SELECT 1
      FROM ${AppDatabase.libraryWorkTagsTable}
      WHERE content_type = ? AND work_id = ?
      LIMIT 1
      ''',
      <Object>['favorite', record.shelfWorkId],
    );
    final addedAt = record.favoritedAt ?? record.firstSeenAt;
    final totalCount = max(1, record.replyCount + 1);
    final cover = await _loadModuleCover(db, record);
    return LibraryWorkItem(
      workId: record.shelfWorkId,
      categoryId: record.resolvedCategoryId,
      title: record.title,
      secondaryName: record.authorName,
      coverImageUrl: cover.coverImageUrl,
      customCoverImageUrl: cover.customCoverImageUrl,
      coverLocalPath: cover.coverLocalPath,
      customCoverLocalPath: cover.customCoverLocalPath,
      coverAsset:
          record.contentKind == ThreadContentKind.comic ||
              record.contentKind == ThreadContentKind.novel
          ? LibraryCoverAssetFactory.preferred(
              ownerType: record.contentKind == ThreadContentKind.comic
                  ? 'comic'
                  : 'novel',
              ownerId: record.workId ?? record.shelfWorkId,
              sourceUrl: cover.coverImageUrl,
              sourceLegacyPath: cover.coverLocalPath,
              sourceRevision: cover.coverRevision,
              customSourceUrl: cover.customCoverImageUrl,
              customLegacyPath: cover.customCoverLocalPath,
              customRevision: cover.customCoverRevision,
            )
          : null,
      unreadCount: 0,
      totalChapterCount: totalCount,
      readChapterCount: 0,
      addedAt: addedAt,
      workUpdatedAt: record.favoritedAt,
      lastFetchedAt: record.detailLoadedAt,
      hasTags: tagRows.isNotEmpty,
    );
  }

  LibraryWorkItem _rowToSnapshotWorkItem(Map<String, Object?> row) {
    final tid = row['tid'] as String;
    final dateline = FavoriteCacheRowMapper.datelineDate(row['dateline']);
    final firstSeenAt =
        FavoriteCacheRowMapper.dateTime(row['first_seen_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final addedAt = dateline ?? firstSeenAt;
    final totalCount = max(1, (row['replies'] as int? ?? 0) + 1);
    final workId = FavoriteShelfWorkId.fromTid(tid);
    return LibraryWorkItem(
      workId: workId,
      categoryId: _resolvedCategoryIdFromRow(row),
      title: row['title'] as String,
      secondaryName: row['author'] as String?,
      coverImageUrl: row['module_cover_image_url'] as String?,
      customCoverImageUrl: row['module_custom_cover_image_url'] as String?,
      coverLocalPath: row['module_cover_local_path'] as String?,
      customCoverLocalPath: row['module_custom_cover_local_path'] as String?,
      coverAsset:
          row['content_kind'] == 'comic' || row['content_kind'] == 'novel'
          ? LibraryCoverAssetFactory.preferred(
              ownerType: row['content_kind'] == 'comic' ? 'comic' : 'novel',
              ownerId: row['work_id'] as String? ?? workId,
              sourceUrl: row['module_cover_image_url'] as String?,
              sourceLegacyPath: row['module_cover_local_path'] as String?,
              sourceRevision: row['module_cover_revision'] as int? ?? 0,
              customSourceUrl: row['module_custom_cover_image_url'] as String?,
              customLegacyPath:
                  row['module_custom_cover_local_path'] as String?,
              customRevision: row['module_custom_cover_revision'] as int? ?? 0,
            )
          : null,
      unreadCount: 0,
      totalChapterCount: totalCount,
      readChapterCount: 0,
      addedAt: addedAt,
      workUpdatedAt: dateline,
      lastFetchedAt: FavoriteCacheRowMapper.dateTime(row['detail_loaded_at']),
      hasTags: (row['has_tags'] as int? ?? 0) == 1,
    );
  }

  String _resolvedCategoryIdFromRow(Map<String, Object?> row) {
    if (favoriteDetailStateFromDb(row['detail_state'] as String?) ==
        FavoriteDetailState.invalid) {
      return favoriteInvalidCategoryId;
    }
    final custom = FavoriteCacheRowMapper.normalizeNullable(
      row['custom_category_id'] as String?,
    );
    if (custom != null) {
      return custom;
    }
    switch (favoriteContentKindFromDb(row['content_kind'] as String?)) {
      case ThreadContentKind.comic:
        return favoriteComicCategoryId;
      case ThreadContentKind.novel:
        return favoriteNovelCategoryId;
      case ThreadContentKind.unknown:
      case ThreadContentKind.forum:
        return favoriteDefaultCategoryId;
    }
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
          AppDatabase.comicsTable,
          columns: const <String>[
            'cover_image_url',
            'custom_cover_image_url',
            'cover_local_path',
            'custom_cover_local_path',
            'cover_revision',
            'custom_cover_revision',
          ],
          where: 'comic_id = ?',
          whereArgs: <Object>[workId],
          limit: 1,
        );
        return _coverSnapshotFromRows(rows);
      case ThreadContentKind.novel:
        final rows = await db.query(
          AppDatabase.worksTable,
          columns: const <String>[
            'cover_image_url',
            'cover_local_path',
            'custom_cover_local_path',
            'cover_revision',
            'custom_cover_revision',
            'cover_hidden',
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

  _FavoriteCoverSnapshot _coverSnapshotFromRows(
    List<Map<String, Object?>> rows,
  ) {
    if (rows.isEmpty) {
      return const _FavoriteCoverSnapshot.empty();
    }
    final row = rows.first;
    if ((row['cover_hidden'] as int? ?? 0) == 1) {
      return const _FavoriteCoverSnapshot.empty();
    }
    final customCoverImageUrl = row['custom_cover_image_url'] as String?;
    return _FavoriteCoverSnapshot(
      coverImageUrl: customCoverImageUrl ?? row['cover_image_url'] as String?,
      customCoverImageUrl: customCoverImageUrl,
      coverLocalPath: row['cover_local_path'] as String?,
      customCoverLocalPath: row['custom_cover_local_path'] as String?,
      coverRevision: row['cover_revision'] as int? ?? 0,
      customCoverRevision: row['custom_cover_revision'] as int? ?? 0,
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
          cmp = _dateOrEpoch(
            a.workUpdatedAt,
          ).compareTo(_dateOrEpoch(b.workUpdatedAt));
          break;
        case LibraryShelfSortField.fetchedAt:
          cmp = _dateOrEpoch(
            a.lastFetchedAt,
          ).compareTo(_dateOrEpoch(b.lastFetchedAt));
          break;
        case LibraryShelfSortField.lastCheckedAt:
          cmp = _dateOrEpoch(
            a.lastCheckedAt,
          ).compareTo(_dateOrEpoch(b.lastCheckedAt));
          break;
        case LibraryShelfSortField.lastReadAt:
          cmp = _dateOrEpoch(
            a.lastReadAt,
          ).compareTo(_dateOrEpoch(b.lastReadAt));
          break;
        case LibraryShelfSortField.favoriteAddedAt:
          cmp = a.addedAt.compareTo(b.addedAt);
          break;
      }
      return sortOption.direction == LibrarySortDirection.desc ? -cmp : cmp;
    });
    return items;
  }

  DateTime _dateOrEpoch(DateTime? value) {
    return value ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
}

class _FavoriteCoverSnapshot {
  const _FavoriteCoverSnapshot({
    this.coverImageUrl,
    this.customCoverImageUrl,
    this.coverLocalPath,
    this.customCoverLocalPath,
    this.coverRevision = 0,
    this.customCoverRevision = 0,
  });

  const _FavoriteCoverSnapshot.empty()
    : coverImageUrl = null,
      customCoverImageUrl = null,
      coverLocalPath = null,
      customCoverLocalPath = null,
      coverRevision = 0,
      customCoverRevision = 0;

  final String? coverImageUrl;
  final String? customCoverImageUrl;
  final String? coverLocalPath;
  final String? customCoverLocalPath;
  final int coverRevision;
  final int customCoverRevision;
}

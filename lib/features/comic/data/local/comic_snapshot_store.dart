import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_query_utils.dart';

class ComicSnapshotStore {
  ComicSnapshotStore(this._dbFuture);

  final Future<Database> _dbFuture;

  Future<LibraryShelfSnapshot> queryShelfSnapshot({
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    final db = await _dbFuture;
    final categories = await _loadLibraryCategories(db);
    final rows = await db.rawQuery('''
      WITH chapter_stats AS (
        SELECT
          e.comic_id AS work_id,
          COUNT(*) AS total_count,
          SUM(CASE WHEN COALESCE(s.is_read, 0) = 0 THEN 1 ELSE 0 END) AS unread_count,
          SUM(CASE WHEN COALESCE(s.is_read, 0) = 1 THEN 1 ELSE 0 END) AS read_count,
          SUM(CASE WHEN COALESCE(s.is_downloaded, 0) = 1 THEN 1 ELSE 0 END) AS downloaded_count
        FROM ${ComicLocalDb.episodesTable} e
        LEFT JOIN ${ComicLocalDb.libraryEpisodeStateTable} s
          ON s.content_type = 'comic'
         AND s.episode_id = e.episode_id
        GROUP BY e.comic_id
      ),
      tag_stats AS (
        SELECT work_id, 1 AS has_tags
        FROM ${ComicLocalDb.libraryWorkTagsTable}
        WHERE content_type = 'comic'
        GROUP BY work_id
      ),
      work_state AS (
        SELECT
          work_id,
          last_read_at,
          check_updated_at,
          fetched_updated_at
        FROM ${ComicLocalDb.libraryWorkStateTable}
        WHERE content_type = 'comic'
      )
      SELECT
        si.category_id,
        si.added_at,
        si.sort_order,
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
        c.custom_cover_focus_y,
        c.updated_at AS work_updated_at,
        COALESCE(cs.total_count, 0) AS total_count,
        COALESCE(cs.unread_count, 0) AS unread_count,
        COALESCE(cs.read_count, 0) AS read_count,
        COALESCE(cs.downloaded_count, 0) AS downloaded_count,
        COALESCE(ts.has_tags, 0) AS has_tags,
        ws.last_read_at,
        ws.check_updated_at,
        ws.fetched_updated_at
      FROM ${ComicLocalDb.shelfItemsTable} si
      INNER JOIN ${ComicLocalDb.comicsTable} c
        ON si.comic_id = c.comic_id
      LEFT JOIN chapter_stats cs
        ON cs.work_id = c.comic_id
      LEFT JOIN tag_stats ts
        ON ts.work_id = c.comic_id
      LEFT JOIN work_state ws
        ON ws.work_id = c.comic_id
      ORDER BY si.category_id ASC, si.sort_order ASC, si.added_at DESC
    ''');

    final sourceByCategory = <String, List<LibraryWorkItem>>{
      for (final category in categories)
        category.categoryId: <LibraryWorkItem>[],
    };
    for (final row in rows) {
      final item = rowToLibraryWorkItem(row);
      sourceByCategory
          .putIfAbsent(item.categoryId, () => <LibraryWorkItem>[])
          .add(item);
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

  Future<ComicShelfWorkStats> getShelfWorkStats({
    required String comicId,
  }) async {
    final db = await _dbFuture;
    final rows = await db.rawQuery(
      '''
      SELECT
        COUNT(e.episode_id) AS total_count,
        SUM(CASE WHEN COALESCE(s.is_read, 0) = 0 THEN 1 ELSE 0 END) AS unread_count,
        SUM(CASE WHEN COALESCE(s.is_read, 0) = 1 THEN 1 ELSE 0 END) AS read_count,
        SUM(CASE WHEN COALESCE(s.is_downloaded, 0) = 1 THEN 1 ELSE 0 END) AS downloaded_count
      FROM ${ComicLocalDb.episodesTable} e
      LEFT JOIN ${ComicLocalDb.libraryEpisodeStateTable} s
        ON s.content_type = 'comic'
       AND s.episode_id = e.episode_id
      WHERE e.comic_id = ?
    ''',
      <Object>[comicId],
    );

    final row = rows.isEmpty ? null : rows.first;
    return ComicShelfWorkStats(
      totalCount: row?['total_count'] as int? ?? 0,
      unreadCount: row?['unread_count'] as int? ?? 0,
      readCount: row?['read_count'] as int? ?? 0,
      downloadedCount: row?['downloaded_count'] as int? ?? 0,
    );
  }

  Future<List<LibraryCategory>> _loadLibraryCategories(Database db) async {
    final rows = await db.query(
      ComicLocalDb.categoriesTable,
      orderBy: 'sort_order ASC, created_at ASC',
    );
    return rows
        .map(
          (row) => LibraryCategory(
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

  LibraryWorkItem rowToLibraryWorkItem(Map<String, Object?> row) {
    final customSource = _normalizeNullable(
      row['custom_cover_image_url'] as String?,
    );
    final customLocal = _normalizeNullable(
      row['custom_cover_local_path'] as String?,
    );
    final hasPendingCustomCover = customSource != null && customLocal == null;
    final unreadCount = row['unread_count'] as int? ?? 0;
    final readCount = row['read_count'] as int? ?? 0;
    return LibraryWorkItem(
      workId: row['comic_id'] as String,
      categoryId: row['category_id'] as String,
      title: row['title'] as String,
      secondaryName: _shelfSecondaryName(
        author: row['author'] as String?,
        translationGroup: row['translation_group'] as String?,
      ),
      coverImageUrl: row['cover_image_url'] as String?,
      customCoverImageUrl: customSource,
      coverLocalPath: hasPendingCustomCover
          ? null
          : row['cover_local_path'] as String?,
      customCoverLocalPath: customLocal,
      customCoverFocusX: (row['custom_cover_focus_x'] as num?)?.toDouble(),
      customCoverFocusY: (row['custom_cover_focus_y'] as num?)?.toDouble(),
      unreadCount: unreadCount,
      totalChapterCount: row['total_count'] as int? ?? unreadCount + readCount,
      readChapterCount: readCount,
      addedAt: DateTime.fromMillisecondsSinceEpoch(
        row['added_at'] as int? ?? 0,
      ),
      lastReadAt: _toDateTime(row['last_read_at']),
      workUpdatedAt: _toDateTime(row['work_updated_at']),
      lastCheckedAt: _toDateTime(row['check_updated_at']),
      lastFetchedAt: _toDateTime(row['fetched_updated_at']),
      hasTags: (row['has_tags'] as int? ?? 0) == 1,
      isDownloaded: (row['downloaded_count'] as int? ?? 0) > 0,
    );
  }

  String? _shelfSecondaryName({
    required String? author,
    required String? translationGroup,
  }) {
    final normalizedAuthor = _normalizeNullable(author);
    final normalizedGroup = _normalizeNullable(translationGroup);
    if (normalizedAuthor != null && normalizedGroup != null) {
      return '$normalizedAuthor / $normalizedGroup';
    }
    return normalizedGroup ?? normalizedAuthor;
  }

  DateTime? _toDateTime(Object? value) {
    if (value is! int || value <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  String? _normalizeNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

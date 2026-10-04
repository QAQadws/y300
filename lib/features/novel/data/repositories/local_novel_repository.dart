import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/library_shared/domain/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/data/repositories/local_library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_operation_failure.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_query_utils.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_asset_factory.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/data/services/novel_reader_progress_diagnostics.dart';

const _progressDiagnostics = NovelReaderProgressDiagnostics();

class LocalNovelRepository
    implements
        NovelRepository,
        NovelShelfSnapshotRepository,
        NovelCoverCacheWriter,
        NovelCustomMetadataWriter,
        NovelCustomCoverWriter,
        NovelCustomCoverAssetWriter {
  LocalNovelRepository(
    this._dbFuture, {
    LibraryStateRepository? stateRepository,
  }) : _stateRepository =
           stateRepository ?? LocalLibraryStateRepository(_dbFuture);

  final Future<Database> _dbFuture;
  final LibraryStateRepository _stateRepository;

  static const String _contentType = 'novel';
  static const String _defaultCategoryId = 'default';

  @override
  Future<List<NovelShelfCategory>> getCategories() async {
    final db = await _dbFuture;
    final rows = await db.query(
      AppDatabase.novelCategoriesTable,
      orderBy: 'sort_order ASC, created_at ASC',
    );

    return rows
        .map(
          (row) => NovelShelfCategory(
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

  @override
  Future<String> createCategory({required String name}) async {
    final sanitized = name.trim();
    if (sanitized.isEmpty) {
      throw ArgumentError('分类名称不能为空');
    }

    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    final categoryId = 'n$now${Random().nextInt(1000)}';

    await db.transaction((txn) async {
      final countResult = await txn.rawQuery(
        'SELECT COUNT(*) AS count FROM ${AppDatabase.novelCategoriesTable}',
      );
      final sortOrder = (countResult.first['count'] as int?) ?? 0;
      await txn.insert(AppDatabase.novelCategoriesTable, <String, Object?>{
        'category_id': categoryId,
        'name': sanitized,
        'sort_order': sortOrder,
        'created_at': now,
      });
    });

    return categoryId;
  }

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {
    final sanitized = newName.trim();
    if (sanitized.isEmpty) {
      throw ArgumentError('分类名称不能为空');
    }
    if (categoryId == _defaultCategoryId) {
      throw const LibraryOperationException(
        LibraryOperationFailureCode.defaultCategoryImmutable,
      );
    }

    final db = await _dbFuture;
    await db.update(
      AppDatabase.novelCategoriesTable,
      <String, Object?>{'name': sanitized},
      where: 'category_id = ?',
      whereArgs: <Object>[categoryId],
    );
  }

  @override
  Future<void> deleteCategory({required String categoryId}) async {
    if (categoryId == _defaultCategoryId) {
      throw const LibraryOperationException(
        LibraryOperationFailureCode.defaultCategoryImmutable,
      );
    }

    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      final rows = await txn.query(
        AppDatabase.novelShelfItemsTable,
        columns: <String>['novel_id'],
        where: 'category_id = ?',
        whereArgs: <Object>[categoryId],
      );

      for (final row in rows) {
        final novelId = row['novel_id'] as String;
        final existsInDefault = await txn.query(
          AppDatabase.novelShelfItemsTable,
          columns: <String>['id'],
          where: 'category_id = ? AND novel_id = ?',
          whereArgs: <Object>[_defaultCategoryId, novelId],
          limit: 1,
        );
        if (existsInDefault.isEmpty) {
          final sortOrder = await _nextShelfSortOrder(
            txn,
            categoryId: _defaultCategoryId,
          );
          await txn.insert(AppDatabase.novelShelfItemsTable, <String, Object?>{
            'category_id': _defaultCategoryId,
            'novel_id': novelId,
            'added_at': now,
            'sort_order': sortOrder,
          });
        }
      }

      await txn.delete(
        AppDatabase.novelShelfItemsTable,
        where: 'category_id = ?',
        whereArgs: <Object>[categoryId],
      );
      await txn.delete(
        AppDatabase.novelCategoriesTable,
        where: 'category_id = ?',
        whereArgs: <Object>[categoryId],
      );
    });
  }

  @override
  Future<void> moveNovelToCategory({
    required String novelId,
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
        AppDatabase.novelShelfItemsTable,
        columns: <String>['id'],
        where: 'category_id = ? AND novel_id = ?',
        whereArgs: <Object>[toCategoryId, novelId],
        limit: 1,
      );
      if (targetExists.isEmpty) {
        final sortOrder = await _nextShelfSortOrder(
          txn,
          categoryId: toCategoryId,
        );
        await txn.insert(
          AppDatabase.novelShelfItemsTable,
          <String, Object?>{
            'category_id': toCategoryId,
            'novel_id': novelId,
            'added_at': now,
            'sort_order': sortOrder,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      await txn.delete(
        AppDatabase.novelShelfItemsTable,
        where: 'category_id = ? AND novel_id = ?',
        whereArgs: <Object>[fromCategoryId, novelId],
      );
    });
  }

  @override
  Future<List<NovelItem>> getShelfItems({
    String categoryId = _defaultCategoryId,
  }) async {
    final db = await _dbFuture;
    final rows = await db.rawQuery(
      '''
      SELECT
        w.work_id,
        w.source_tid,
        w.source_fid,
        w.source_typeid,
        w.source_tag_name,
        w.title,
        w.custom_title,
        w.author,
        w.cover_image_url,
        w.cover_local_path,
        w.custom_cover_local_path,
        w.cover_revision,
        w.custom_cover_revision,
        w.custom_cover_focus_x,
        w.custom_cover_focus_y,
        w.cover_hidden,
        w.updated_at,
        si.category_id,
        COUNT(e.episode_id) AS episode_count
      FROM ${AppDatabase.novelShelfItemsTable} si
      INNER JOIN ${AppDatabase.worksTable} w
        ON si.novel_id = w.work_id
      LEFT JOIN ${AppDatabase.workEpisodesTable} e
        ON e.work_id = w.work_id AND e.content_type = ?
      WHERE w.content_type = ? AND si.category_id = ?
      GROUP BY w.work_id, si.category_id
      ORDER BY si.sort_order ASC, si.added_at DESC
    ''',
      <Object>[_contentType, _contentType, categoryId],
    );

    return rows.map(_rowToNovelItem).toList(growable: false);
  }

  @override
  Future<LibraryShelfSnapshot> queryShelfSnapshot({
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    final db = await _dbFuture;
    final categories = await _loadLibraryCategories(db);
    final rows = await db.rawQuery(
      '''
      WITH episode_stats AS (
        SELECT
          work_id,
          COUNT(*) AS total_count
        FROM ${AppDatabase.workEpisodesTable}
        WHERE content_type = ?
        GROUP BY work_id
      ),
      bookmark_stats AS (
        SELECT work_id, 1 AS has_bookmarks
        FROM ${AppDatabase.libraryEpisodeStateTable}
        WHERE content_type = ? AND is_bookmarked = 1
        GROUP BY work_id
      ),
      tag_stats AS (
        SELECT work_id, 1 AS has_tags
        FROM ${AppDatabase.libraryWorkTagsTable}
        WHERE content_type = ?
        GROUP BY work_id
      ),
      work_state AS (
        SELECT
          work_id,
          last_read_at,
          check_updated_at,
          fetched_updated_at
        FROM ${AppDatabase.libraryWorkStateTable}
        WHERE content_type = ?
      )
      SELECT
        si.category_id,
        si.added_at,
        si.sort_order,
        w.work_id,
        w.source_tid,
        w.source_fid,
        w.source_typeid,
        w.source_tag_name,
        w.title,
        w.custom_title,
        w.author,
        w.cover_image_url,
        w.cover_local_path,
        w.custom_cover_local_path,
        w.cover_revision,
        w.custom_cover_revision,
        w.custom_cover_focus_x,
        w.custom_cover_focus_y,
        w.cover_hidden,
        w.updated_at AS work_updated_at,
        COALESCE(es.total_count, 0) AS total_count,
        COALESCE(bs.has_bookmarks, 0) AS has_bookmarks,
        COALESCE(ts.has_tags, 0) AS has_tags,
        ws.last_read_at,
        ws.check_updated_at,
        ws.fetched_updated_at
      FROM ${AppDatabase.novelShelfItemsTable} si
      INNER JOIN ${AppDatabase.worksTable} w
        ON si.novel_id = w.work_id
      LEFT JOIN episode_stats es
        ON es.work_id = w.work_id
      LEFT JOIN bookmark_stats bs
        ON bs.work_id = w.work_id
      LEFT JOIN tag_stats ts
        ON ts.work_id = w.work_id
      LEFT JOIN work_state ws
        ON ws.work_id = w.work_id
      WHERE w.content_type = ?
      ORDER BY si.category_id ASC, si.sort_order ASC, si.added_at DESC
    ''',
      <Object>[
        _contentType,
        _contentType,
        _contentType,
        _contentType,
        _contentType,
      ],
    );

    final sourceByCategory = <String, List<LibraryWorkItem>>{
      for (final category in categories)
        category.categoryId: <LibraryWorkItem>[],
    };
    for (final row in rows) {
      final item = _rowToLibraryWorkItem(row);
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

  @override
  Future<NovelItem?> getDetail({required String novelId}) async {
    final db = await _dbFuture;
    final rows = await db.rawQuery(
      '''
      SELECT
        w.work_id,
        w.source_tid,
        w.source_fid,
        w.source_typeid,
        w.source_tag_name,
        w.title,
        w.custom_title,
        w.author,
        w.cover_image_url,
        w.cover_local_path,
        w.custom_cover_local_path,
        w.cover_revision,
        w.custom_cover_revision,
        w.custom_cover_focus_x,
        w.custom_cover_focus_y,
        w.cover_hidden,
        w.updated_at,
        ? AS category_id,
        COUNT(e.episode_id) AS episode_count
      FROM ${AppDatabase.worksTable} w
      LEFT JOIN ${AppDatabase.workEpisodesTable} e
        ON e.work_id = w.work_id AND e.content_type = ?
      WHERE w.work_id = ? AND w.content_type = ?
      GROUP BY w.work_id
      LIMIT 1
    ''',
      <Object>[_defaultCategoryId, _contentType, novelId, _contentType],
    );

    if (rows.isEmpty) {
      return null;
    }
    return _rowToNovelItem(rows.first);
  }

  @override
  Future<void> updateCoverCache({
    required String novelId,
    String? coverImageUrl,
    String? coverLocalPath,
    String? customCoverLocalPath,
  }) async {
    final db = await _dbFuture;
    final values = <String, Object?>{
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    if (coverImageUrl != null) {
      values['cover_image_url'] = _normalizeNullable(coverImageUrl);
    }
    if (coverLocalPath != null) {
      values['cover_local_path'] = _normalizeNullable(coverLocalPath);
    }
    if (customCoverLocalPath != null) {
      values['custom_cover_local_path'] = _normalizeNullable(
        customCoverLocalPath,
      );
    }
    await db.update(
      AppDatabase.worksTable,
      values,
      where: 'work_id = ? AND content_type = ?',
      whereArgs: <Object>[novelId, _contentType],
    );
  }

  @override
  Future<void> updateCustomMetadata({
    required String novelId,
    String? customTitle,
  }) async {
    final db = await _dbFuture;
    await db.update(
      AppDatabase.worksTable,
      <String, Object?>{
        'custom_title': _normalizeNullable(customTitle),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'work_id = ? AND content_type = ?',
      whereArgs: <Object>[novelId, _contentType],
    );
  }

  @override
  Future<void> updateCustomCover({
    required String novelId,
    required String customCoverLocalPath,
    double? focusX,
    double? focusY,
  }) async {
    final normalizedPath = _normalizeNullable(customCoverLocalPath);
    if (normalizedPath == null) {
      throw ArgumentError('自定义封面路径不能为空');
    }
    final db = await _dbFuture;
    await db.transaction((txn) async {
      final rows = await txn.query(
        AppDatabase.worksTable,
        columns: const <String>['custom_cover_revision'],
        where: 'work_id = ? AND content_type = ?',
        whereArgs: <Object>[novelId, _contentType],
        limit: 1,
      );
      final nextRevision =
          (rows.isEmpty
              ? 0
              : rows.single['custom_cover_revision'] as int? ?? 0) +
          1;
      await txn.update(
        AppDatabase.worksTable,
        <String, Object?>{
          'custom_cover_local_path': normalizedPath,
          'custom_cover_revision': nextRevision,
          'custom_cover_focus_x': focusX,
          'custom_cover_focus_y': focusY,
          'cover_hidden': 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'work_id = ? AND content_type = ?',
        whereArgs: <Object>[novelId, _contentType],
      );
    });
  }

  @override
  Future<void> activateCustomCoverAsset({
    required String novelId,
    required int revision,
    double? focusX,
    double? focusY,
  }) async {
    if (revision <= 0) {
      throw ArgumentError.value(revision, 'revision');
    }
    final db = await _dbFuture;
    await db.update(
      AppDatabase.worksTable,
      <String, Object?>{
        'custom_cover_local_path': null,
        'custom_cover_revision': revision,
        'custom_cover_focus_x': focusX,
        'custom_cover_focus_y': focusY,
        'cover_hidden': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'work_id = ? AND content_type = ?',
      whereArgs: <Object>[novelId, _contentType],
    );
  }

  @override
  Future<void> updateCustomCoverFocus({
    required String novelId,
    double? focusX,
    double? focusY,
  }) async {
    final db = await _dbFuture;
    await db.update(
      AppDatabase.worksTable,
      <String, Object?>{
        'custom_cover_focus_x': focusX,
        'custom_cover_focus_y': focusY,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'work_id = ? AND content_type = ?',
      whereArgs: <Object>[novelId, _contentType],
    );
  }

  @override
  Future<void> removeCustomCover({required String novelId}) async {
    final db = await _dbFuture;
    await db.update(
      AppDatabase.worksTable,
      <String, Object?>{
        'custom_cover_local_path': null,
        'custom_cover_revision': 0,
        'custom_cover_focus_x': null,
        'custom_cover_focus_y': null,
        'cover_hidden': 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'work_id = ? AND content_type = ?',
      whereArgs: <Object>[novelId, _contentType],
    );
  }

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  }) async {
    final db = await _dbFuture;
    final rows = await db.query(
      AppDatabase.workEpisodesTable,
      where: 'work_id = ? AND content_type = ?',
      whereArgs: <Object>[novelId, _contentType],
      orderBy: 'order_index ${descending ? 'DESC' : 'ASC'}',
    );

    return rows
        .map(
          (row) => NovelEpisodeItem(
            episodeId: row['episode_id'] as String,
            novelId: row['work_id'] as String,
            sourceTid: row['source_tid'] as String,
            sourcePid: row['source_pid'] as String?,
            sourcePage: row['source_page'] as int?,
            episodeTitle: (row['episode_title'] as String?) ?? '',
            orderIndex: row['order_index'] as int,
            datelineText: row['dateline_text'] as String?,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<NovelChapterContent?> getChapterContent({
    required String episodeId,
  }) async {
    final db = await _dbFuture;
    final rows = await db.query(
      AppDatabase.novelEpisodeContentTable,
      where: 'episode_id = ?',
      whereArgs: <Object>[episodeId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final paragraphJson = (row['paragraph_json'] as String?) ?? '[]';
    final paragraphs = (jsonDecode(paragraphJson) as List<dynamic>)
        .map((item) => item.toString())
        .toList(growable: false);

    return NovelChapterContent(
      episodeId: episodeId,
      rawHtml: (row['raw_html'] as String?) ?? '',
      plainText: (row['plain_text'] as String?) ?? '',
      paragraphs: paragraphs,
    );
  }

  @override
  Future<void> removeFromShelf({required String novelId}) async {
    final db = await _dbFuture;
    await db.delete(
      AppDatabase.novelShelfItemsTable,
      where: 'novel_id = ?',
      whereArgs: <Object>[novelId],
    );
  }

  @override
  Future<void> purgeWork({required String novelId}) async {
    final db = await _dbFuture;
    await db.transaction((txn) async {
      await txn.delete(
        AppDatabase.readerBookmarksTable,
        where: 'novel_id = ?',
        whereArgs: <Object>[novelId],
      );
      await txn.delete(
        AppDatabase.novelReadingProgressTable,
        where: 'novel_id = ?',
        whereArgs: <Object>[novelId],
      );
      await txn.delete(
        AppDatabase.worksTable,
        where: 'work_id = ? AND content_type = ?',
        whereArgs: <Object>[novelId, _contentType],
      );
    });
  }

  @override
  Future<void> saveReadingProgress({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
    NovelReaderFlowMode flowMode = NovelReaderFlowMode.vertical,
    int pageIndex = 0,
    int? pageCount,
    String? anchorNodeId,
    int anchorTextOffset = 0,
    String? paginationKey,
    double progressPercent = 0,
  }) async {
    final db = await _dbFuture;
    await db.insert(
      AppDatabase.novelReadingProgressTable,
      <String, Object?>{
        'novel_id': novelId,
        'episode_id': episodeId,
        'scroll_offset': scrollOffset,
        'flow_mode': flowMode.storageValue,
        'page_index': pageIndex < 0 ? 0 : pageIndex,
        'page_count': pageCount == null || pageCount <= 0 ? null : pageCount,
        'anchor_node_id': _normalizeNullable(anchorNodeId),
        'anchor_text_offset': anchorTextOffset.clamp(0, 1 << 30).toInt(),
        'pagination_key': _normalizeNullable(paginationKey),
        'progress_percent': progressPercent.clamp(0.0, 1.0).toDouble(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _progressDiagnostics.log(
      'db_save',
      fields: <String, Object?>{
        'novelId': novelId,
        'episodeId': episodeId,
        'flowMode': flowMode.name,
        'scrollOffset': scrollOffset.toStringAsFixed(2),
        'progressPercent': progressPercent.toStringAsFixed(4),
        'pageIndex': pageIndex,
        'pageCount': pageCount,
      },
    );
  }

  @override
  Future<NovelReadingProgress?> getReadingProgress({
    required String novelId,
  }) async {
    final db = await _dbFuture;
    final rows = await db.query(
      AppDatabase.novelReadingProgressTable,
      where: 'novel_id = ?',
      whereArgs: <Object>[novelId],
      limit: 1,
    );
    if (rows.isEmpty) {
      _progressDiagnostics.log(
        'db_load_miss',
        fields: <String, Object?>{'novelId': novelId},
      );
      return null;
    }

    final row = rows.first;
    final episodeId = (row['episode_id'] as String?) ?? '';
    if (episodeId.isEmpty) {
      _progressDiagnostics.log(
        'db_load_invalid',
        fields: <String, Object?>{'novelId': novelId},
      );
      return null;
    }

    final progress = NovelReadingProgress(
      novelId: novelId,
      episodeId: episodeId,
      scrollOffset: (row['scroll_offset'] as num?)?.toDouble() ?? 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['updated_at'] as int?) ?? 0,
      ),
      flowMode: NovelReaderFlowModeCodec.fromStorage(
        row['flow_mode'] as String?,
      ),
      pageIndex: ((row['page_index'] as num?)?.toInt() ?? 0)
          .clamp(0, 1 << 30)
          .toInt(),
      pageCount: switch ((row['page_count'] as num?)?.toInt()) {
        final value? when value > 0 => value,
        _ => null,
      },
      anchorNodeId: _normalizeNullable(row['anchor_node_id'] as String?),
      anchorTextOffset: ((row['anchor_text_offset'] as num?)?.toInt() ?? 0)
          .clamp(0, 1 << 30)
          .toInt(),
      paginationKey: _normalizeNullable(row['pagination_key'] as String?),
      progressPercent: ((row['progress_percent'] as num?)?.toDouble() ?? 0)
          .clamp(0.0, 1.0)
          .toDouble(),
    );
    _progressDiagnostics.log(
      'db_load',
      fields: <String, Object?>{
        'novelId': progress.novelId,
        'episodeId': progress.episodeId,
        'flowMode': progress.flowMode.name,
        'scrollOffset': progress.scrollOffset.toStringAsFixed(2),
        'progressPercent': progress.progressPercent.toStringAsFixed(4),
        'pageIndex': progress.pageIndex,
        'pageCount': progress.pageCount,
      },
    );
    return progress;
  }

  @override
  Future<List<NovelReaderBookmark>> listReaderBookmarks({
    required String novelId,
  }) async {
    final db = await _dbFuture;
    final readerRows = await db.query(
      AppDatabase.readerBookmarksTable,
      where: 'novel_id = ?',
      whereArgs: <Object>[novelId],
      orderBy: 'created_at ASC',
    );
    final episodeRows = await db.rawQuery(
      '''
      SELECT e.episode_id, e.episode_title
      FROM ${AppDatabase.workEpisodesTable} e
      INNER JOIN ${AppDatabase.libraryEpisodeStateTable} state
        ON state.episode_id = e.episode_id
       AND state.content_type = ?
       AND state.work_id = e.work_id
      WHERE e.work_id = ?
        AND e.content_type = ?
        AND state.is_bookmarked = 1
      ORDER BY e.order_index ASC
    ''',
      <Object>[_contentType, novelId, _contentType],
    );
    final readerBookmarks = readerRows
        .map(_rowToReaderBookmark)
        .whereType<NovelReaderBookmark>()
        .toList(growable: false);
    final episodeBookmarks = episodeRows
        .map((row) => _rowToEpisodeBookmark(row, novelId: novelId))
        .whereType<NovelReaderBookmark>()
        .toList(growable: false);
    return <NovelReaderBookmark>[...episodeBookmarks, ...readerBookmarks];
  }

  @override
  Future<void> addReaderBookmark({
    required NovelReaderBookmark bookmark,
  }) async {
    final db = await _dbFuture;
    await db.insert(
      AppDatabase.readerBookmarksTable,
      <String, Object?>{
        'bookmark_id': bookmark.bookmarkId,
        'novel_id': bookmark.novelId,
        'episode_id': bookmark.episodeId,
        'node_id': _normalizeNullable(bookmark.anchor.nodeId),
        'text_offset': bookmark.anchor.textOffset < 0
            ? 0
            : bookmark.anchor.textOffset,
        'page_index': bookmark.anchor.pageIndex < 0
            ? 0
            : bookmark.anchor.pageIndex,
        'scroll_offset': bookmark.anchor.scrollOffset < 0
            ? 0
            : bookmark.anchor.scrollOffset,
        'progress_percent': bookmark.anchor.progressPercent
            .clamp(0.0, 1.0)
            .toDouble(),
        'title': bookmark.title,
        'snippet': bookmark.snippet,
        'note': _normalizeNullable(bookmark.note),
        'created_at': bookmark.createdAt.millisecondsSinceEpoch,
        'updated_at': bookmark.updatedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> removeReaderBookmark({required String bookmarkId}) async {
    final db = await _dbFuture;
    await db.delete(
      AppDatabase.readerBookmarksTable,
      where: 'bookmark_id = ?',
      whereArgs: <Object>[bookmarkId],
    );
  }

  @override
  Future<void> toggleEpisodeBookmark({
    required String novelId,
    required String episodeId,
    required bool isBookmarked,
  }) async {
    await _stateRepository.upsertEpisodeState(
      moduleKey: LibraryModuleKey.novel,
      episodeId: episodeId,
      workId: novelId,
      isBookmarked: isBookmarked,
    );
  }

  NovelItem _rowToNovelItem(Map<String, Object?> row) {
    final coverHidden = (row['cover_hidden'] as int? ?? 0) == 1;
    return NovelItem(
      novelId: row['work_id'] as String,
      sourceTid: row['source_tid'] as String,
      sourceFid: row['source_fid'] as String,
      sourceTypeId: row['source_typeid'] as String?,
      sourceTagName: row['source_tag_name'] as String?,
      title: row['title'] as String,
      author: row['author'] as String?,
      customTitle: row['custom_title'] as String?,
      coverImageUrl: row['cover_image_url'] as String?,
      coverLocalPath: row['cover_local_path'] as String?,
      customCoverLocalPath: row['custom_cover_local_path'] as String?,
      coverRevision: row['cover_revision'] as int? ?? 0,
      customCoverRevision: row['custom_cover_revision'] as int? ?? 0,
      customCoverFocusX: (row['custom_cover_focus_x'] as num?)?.toDouble(),
      customCoverFocusY: (row['custom_cover_focus_y'] as num?)?.toDouble(),
      coverHidden: coverHidden,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['updated_at'] as int?) ?? 0,
      ),
      episodeCount: (row['episode_count'] as int?) ?? 0,
      categoryId: (row['category_id'] as String?) ?? _defaultCategoryId,
    );
  }

  Future<List<LibraryCategory>> _loadLibraryCategories(Database db) async {
    final rows = await db.query(
      AppDatabase.novelCategoriesTable,
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

  LibraryWorkItem _rowToLibraryWorkItem(Map<String, Object?> row) {
    final coverHidden = (row['cover_hidden'] as int? ?? 0) == 1;
    return LibraryWorkItem(
      workId: row['work_id'] as String,
      categoryId: (row['category_id'] as String?) ?? _defaultCategoryId,
      title: _preferredRowText(row['custom_title'], row['title']) ?? '',
      secondaryName: _preferredRowText(row['author'], null),
      coverImageUrl: coverHidden ? null : row['cover_image_url'] as String?,
      coverLocalPath: coverHidden ? null : row['cover_local_path'] as String?,
      customCoverLocalPath: coverHidden
          ? null
          : row['custom_cover_local_path'] as String?,
      coverAsset: coverHidden
          ? null
          : LibraryCoverAssetFactory.preferred(
              ownerType: 'novel',
              ownerId: row['work_id'] as String,
              sourceUrl: row['cover_image_url'] as String?,
              sourceLegacyPath: row['cover_local_path'] as String?,
              sourceRevision: row['cover_revision'] as int? ?? 0,
              customLegacyPath: row['custom_cover_local_path'] as String?,
              customRevision: row['custom_cover_revision'] as int? ?? 0,
            ),
      customCoverFocusX: coverHidden
          ? null
          : (row['custom_cover_focus_x'] as num?)?.toDouble(),
      customCoverFocusY: coverHidden
          ? null
          : (row['custom_cover_focus_y'] as num?)?.toDouble(),
      unreadCount: 0,
      totalChapterCount: row['total_count'] as int? ?? 0,
      readChapterCount: 0,
      addedAt: DateTime.fromMillisecondsSinceEpoch(
        row['added_at'] as int? ?? 0,
      ),
      lastReadAt: _toDateTime(row['last_read_at']),
      workUpdatedAt: _toDateTime(row['work_updated_at']),
      lastCheckedAt: _toDateTime(row['check_updated_at']),
      lastFetchedAt: _toDateTime(row['fetched_updated_at']),
      hasTags: (row['has_tags'] as int? ?? 0) == 1,
      hasBookmarks: (row['has_bookmarks'] as int? ?? 0) == 1,
    );
  }

  NovelReaderBookmark? _rowToReaderBookmark(Map<String, Object?> row) {
    final bookmarkId = _normalizeNullable(row['bookmark_id'] as String?);
    final novelId = _normalizeNullable(row['novel_id'] as String?);
    final episodeId = _normalizeNullable(row['episode_id'] as String?);
    if (bookmarkId == null || novelId == null || episodeId == null) {
      return null;
    }
    return NovelReaderBookmark(
      bookmarkId: bookmarkId,
      novelId: novelId,
      episodeId: episodeId,
      anchor: NovelReaderTextAnchor(
        episodeId: episodeId,
        nodeId: _normalizeNullable(row['node_id'] as String?),
        textOffset: ((row['text_offset'] as num?)?.toInt() ?? 0)
            .clamp(0, 1 << 30)
            .toInt(),
        pageIndex: ((row['page_index'] as num?)?.toInt() ?? 0)
            .clamp(0, 1 << 30)
            .toInt(),
        scrollOffset: ((row['scroll_offset'] as num?)?.toDouble() ?? 0)
            .clamp(0.0, double.infinity)
            .toDouble(),
        progressPercent: ((row['progress_percent'] as num?)?.toDouble() ?? 0)
            .clamp(0.0, 1.0)
            .toDouble(),
      ),
      title: (row['title'] as String?) ?? '',
      snippet: (row['snippet'] as String?) ?? '',
      note: _normalizeNullable(row['note'] as String?),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (row['created_at'] as int?) ?? 0,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['updated_at'] as int?) ?? 0,
      ),
    );
  }

  NovelReaderBookmark? _rowToEpisodeBookmark(
    Map<String, Object?> row, {
    required String novelId,
  }) {
    final episodeId = _normalizeNullable(row['episode_id'] as String?);
    if (episodeId == null) {
      return null;
    }
    final updatedAt = DateTime.fromMillisecondsSinceEpoch(0);
    return NovelReaderBookmark(
      bookmarkId: 'episode-bookmark:$episodeId',
      novelId: novelId,
      episodeId: episodeId,
      anchor: NovelReaderTextAnchor(episodeId: episodeId),
      title: (row['episode_title'] as String?) ?? '',
      snippet: '',
      createdAt: updatedAt,
      updatedAt: updatedAt,
    );
  }

  Future<int> _nextShelfSortOrder(
    Transaction txn, {
    required String categoryId,
  }) async {
    final countResult = await txn.rawQuery(
      'SELECT COUNT(*) AS count FROM ${AppDatabase.novelShelfItemsTable} WHERE category_id = ?',
      <Object>[categoryId],
    );
    return (countResult.first['count'] as int?) ?? 0;
  }

  String? _normalizeNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  DateTime? _toDateTime(Object? value) {
    if (value is! int || value <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
}

String? _preferredRowText(Object? preferred, Object? fallback) {
  for (final value in <Object?>[preferred, fallback]) {
    if (value is! String) {
      continue;
    }
    final normalized = value.trim();
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  return null;
}

import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:y300/features/cache/domain/image_cache_keys.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/favorites/data/favorite_first_sync_request_governor.dart';
import 'package:y300/features/library_shared/data/local_library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_query_utils.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/novel/domain/services/novel_episode_discovery_service.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

class LocalNovelRepository
    implements NovelRepository, NovelShelfSnapshotRepository, NovelCoverCacheWriter {
  LocalNovelRepository(
    this._dbFuture, {
    required NovelThreadGateway threadGateway,
    required NovelEpisodeDiscoveryService discoveryService,
    ImageCacheService? imageCacheService,
  })  : _threadGateway = threadGateway,
        _discoveryService = discoveryService,
        _imageCacheService = imageCacheService,
        _stateRepository = LocalLibraryStateRepository(_dbFuture);

  final Future<Database> _dbFuture;
  final NovelThreadGateway _threadGateway;
  final NovelEpisodeDiscoveryService _discoveryService;
  final ImageCacheService? _imageCacheService;
  final LocalLibraryStateRepository _stateRepository;

  static const String _contentType = 'novel';
  static const int _maxRefreshPages = 10;
  static const String _defaultCategoryId = 'default';

  @override
  Future<List<NovelShelfCategory>> getCategories() async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.novelCategoriesTable,
      orderBy: 'sort_order ASC, created_at ASC',
    );

    return rows
        .map(
          (row) => NovelShelfCategory(
            categoryId: row['category_id'] as String,
            name: row['name'] as String,
            sortOrder: row['sort_order'] as int,
            createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
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
        'SELECT COUNT(*) AS count FROM ${ComicLocalDb.novelCategoriesTable}',
      );
      final sortOrder = (countResult.first['count'] as int?) ?? 0;
      await txn.insert(
        ComicLocalDb.novelCategoriesTable,
        <String, Object?>{
          'category_id': categoryId,
          'name': sanitized,
          'sort_order': sortOrder,
          'created_at': now,
        },
      );
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
      throw StateError('默认分类不允许重命名');
    }

    final db = await _dbFuture;
    await db.update(
      ComicLocalDb.novelCategoriesTable,
      <String, Object?>{'name': sanitized},
      where: 'category_id = ?',
      whereArgs: <Object>[categoryId],
    );
  }

  @override
  Future<void> deleteCategory({required String categoryId}) async {
    if (categoryId == _defaultCategoryId) {
      throw StateError('默认分类不允许删除');
    }

    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      final rows = await txn.query(
        ComicLocalDb.novelShelfItemsTable,
        columns: <String>['novel_id'],
        where: 'category_id = ?',
        whereArgs: <Object>[categoryId],
      );

      for (final row in rows) {
        final novelId = row['novel_id'] as String;
        final existsInDefault = await txn.query(
          ComicLocalDb.novelShelfItemsTable,
          columns: <String>['id'],
          where: 'category_id = ? AND novel_id = ?',
          whereArgs: <Object>[_defaultCategoryId, novelId],
          limit: 1,
        );
        if (existsInDefault.isEmpty) {
          final sortOrder = await _nextShelfSortOrder(txn, categoryId: _defaultCategoryId);
          await txn.insert(
            ComicLocalDb.novelShelfItemsTable,
            <String, Object?>{
              'category_id': _defaultCategoryId,
              'novel_id': novelId,
              'added_at': now,
              'sort_order': sortOrder,
            },
          );
        }
      }

      await txn.delete(
        ComicLocalDb.novelShelfItemsTable,
        where: 'category_id = ?',
        whereArgs: <Object>[categoryId],
      );
      await txn.delete(
        ComicLocalDb.novelCategoriesTable,
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
        ComicLocalDb.novelShelfItemsTable,
        columns: <String>['id'],
        where: 'category_id = ? AND novel_id = ?',
        whereArgs: <Object>[toCategoryId, novelId],
        limit: 1,
      );
      if (targetExists.isEmpty) {
        final sortOrder = await _nextShelfSortOrder(txn, categoryId: toCategoryId);
        await txn.insert(
          ComicLocalDb.novelShelfItemsTable,
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
        ComicLocalDb.novelShelfItemsTable,
        where: 'category_id = ? AND novel_id = ?',
        whereArgs: <Object>[fromCategoryId, novelId],
      );
    });
  }

  @override
  Future<List<NovelItem>> getShelfItems({String categoryId = _defaultCategoryId}) async {
    final db = await _dbFuture;
    final rows = await db.rawQuery('''
      SELECT
        w.work_id,
        w.source_tid,
        w.source_fid,
        w.source_typeid,
        w.source_tag_name,
        w.title,
        w.author,
        w.cover_image_url,
        w.cover_local_path,
        w.custom_cover_local_path,
        w.updated_at,
        si.category_id,
        COUNT(e.episode_id) AS episode_count
      FROM ${ComicLocalDb.novelShelfItemsTable} si
      INNER JOIN ${ComicLocalDb.worksTable} w
        ON si.novel_id = w.work_id
      LEFT JOIN ${ComicLocalDb.workEpisodesTable} e
        ON e.work_id = w.work_id AND e.content_type = ?
      WHERE w.content_type = ? AND si.category_id = ?
      GROUP BY w.work_id, si.category_id
      ORDER BY si.sort_order ASC, si.added_at DESC
    ''', <Object>[_contentType, _contentType, categoryId]);

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
    final rows = await db.rawQuery('''
      WITH episode_stats AS (
        SELECT
          work_id,
          COUNT(*) AS total_count
        FROM ${ComicLocalDb.workEpisodesTable}
        WHERE content_type = ?
        GROUP BY work_id
      ),
      state_stats AS (
        SELECT
          work_id,
          COUNT(*) AS state_count,
          SUM(CASE WHEN is_read = 0 THEN 1 ELSE 0 END) AS unread_count,
          SUM(CASE WHEN is_read = 1 THEN 1 ELSE 0 END) AS read_count,
          SUM(CASE WHEN is_downloaded = 1 THEN 1 ELSE 0 END) AS downloaded_count
        FROM ${ComicLocalDb.libraryEpisodeStateTable}
        WHERE content_type = ?
        GROUP BY work_id
      ),
      tag_stats AS (
        SELECT work_id, 1 AS has_tags
        FROM ${ComicLocalDb.libraryWorkTagsTable}
        WHERE content_type = ?
        GROUP BY work_id
      ),
      work_state AS (
        SELECT
          work_id,
          last_read_at,
          check_updated_at,
          fetched_updated_at
        FROM ${ComicLocalDb.libraryWorkStateTable}
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
        w.author,
        w.cover_image_url,
        w.cover_local_path,
        w.custom_cover_local_path,
        w.updated_at AS work_updated_at,
        COALESCE(es.total_count, ss.state_count, 0) AS total_count,
        COALESCE(ss.unread_count, 0) AS unread_count,
        COALESCE(ss.read_count, 0) AS read_count,
        COALESCE(ss.downloaded_count, 0) AS downloaded_count,
        COALESCE(ts.has_tags, 0) AS has_tags,
        ws.last_read_at,
        ws.check_updated_at,
        ws.fetched_updated_at
      FROM ${ComicLocalDb.novelShelfItemsTable} si
      INNER JOIN ${ComicLocalDb.worksTable} w
        ON si.novel_id = w.work_id
      LEFT JOIN episode_stats es
        ON es.work_id = w.work_id
      LEFT JOIN state_stats ss
        ON ss.work_id = w.work_id
      LEFT JOIN tag_stats ts
        ON ts.work_id = w.work_id
      LEFT JOIN work_state ws
        ON ws.work_id = w.work_id
      WHERE w.content_type = ?
      ORDER BY si.category_id ASC, si.sort_order ASC, si.added_at DESC
    ''', <Object>[_contentType, _contentType, _contentType, _contentType, _contentType]);

    final sourceByCategory = <String, List<LibraryWorkItem>>{
      for (final category in categories) category.categoryId: <LibraryWorkItem>[],
    };
    for (final row in rows) {
      final item = _rowToLibraryWorkItem(row);
      sourceByCategory.putIfAbsent(item.categoryId, () => <LibraryWorkItem>[]).add(item);
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
      visibleMatchCountByCategory: LibraryShelfQueryUtils.countByCategory(queried),
    );
  }

  @override
  Future<NovelItem?> getDetail({required String novelId}) async {
    final db = await _dbFuture;
    final rows = await db.rawQuery('''
      SELECT
        w.work_id,
        w.source_tid,
        w.source_fid,
        w.source_typeid,
        w.source_tag_name,
        w.title,
        w.author,
        w.cover_image_url,
        w.cover_local_path,
        w.custom_cover_local_path,
        w.updated_at,
        ? AS category_id,
        COUNT(e.episode_id) AS episode_count
      FROM ${ComicLocalDb.worksTable} w
      LEFT JOIN ${ComicLocalDb.workEpisodesTable} e
        ON e.work_id = w.work_id AND e.content_type = ?
      WHERE w.work_id = ? AND w.content_type = ?
      GROUP BY w.work_id
      LIMIT 1
    ''', <Object>[_defaultCategoryId, _contentType, novelId, _contentType]);

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
      values['custom_cover_local_path'] = _normalizeNullable(customCoverLocalPath);
    }
    await db.update(
      ComicLocalDb.worksTable,
      values,
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
      ComicLocalDb.workEpisodesTable,
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
            episodeTitle: (row['episode_title'] as String?) ?? '未命名章节',
            orderIndex: row['order_index'] as int,
            datelineText: row['dateline_text'] as String?,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<NovelChapterContent?> getChapterContent({required String episodeId}) async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.novelEpisodeContentTable,
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
  Future<void> upsertReaderPreferences(NovelReaderPreferences preferences) async {
    final db = await _dbFuture;
    await db.insert(
      ComicLocalDb.readerPreferencesTable,
      <String, Object?>{
        'content_type': _contentType,
        'font_size': preferences.fontSize,
        'line_height': preferences.lineHeight,
        'paragraph_spacing': preferences.paragraphSpacing,
        'page_padding': preferences.pagePadding,
        'theme_mode': preferences.themeMode,
        'font_family': preferences.fontFamily,
        'flow_mode': preferences.flowMode.storageValue,
        'theme_preset': preferences.themePreset.storageValue,
        'content_max_width': preferences.contentMaxWidth,
        'first_line_indent': preferences.firstLineIndent,
        'font_weight': preferences.fontWeight,
        'text_align': preferences.textAlign.storageValue,
        'show_progress_indicator': preferences.showProgressIndicator ? 1 : 0,
        'show_chapter_title': preferences.showChapterTitle ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<NovelReaderPreferences> getReaderPreferences() async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.readerPreferencesTable,
      where: 'content_type = ?',
      whereArgs: <Object>[_contentType],
      limit: 1,
    );
    if (rows.isEmpty) {
      return NovelReaderPreferences.defaults();
    }

    final row = rows.first;
    final defaults = NovelReaderPreferences.defaults();
    return NovelReaderPreferences(
      fontSize: (row['font_size'] as num?)?.toDouble() ?? defaults.fontSize,
      lineHeight: (row['line_height'] as num?)?.toDouble() ?? defaults.lineHeight,
      paragraphSpacing:
          (row['paragraph_spacing'] as num?)?.toDouble() ?? defaults.paragraphSpacing,
      pagePadding: (row['page_padding'] as num?)?.toDouble() ?? defaults.pagePadding,
      fontFamily: (row['font_family'] as String?) ?? defaults.fontFamily,
      flowMode: NovelReaderFlowModeCodec.fromStorage(row['flow_mode'] as String?),
      themePreset: NovelReaderThemePresetCodec.fromStorage(
        (row['theme_preset'] as String?) ?? (row['theme_mode'] as String?),
      ),
      contentMaxWidth:
          (row['content_max_width'] as num?)?.toDouble() ?? defaults.contentMaxWidth,
      firstLineIndent:
          (row['first_line_indent'] as num?)?.toDouble() ?? defaults.firstLineIndent,
      fontWeight: (row['font_weight'] as num?)?.toInt() ?? defaults.fontWeight,
      textAlign: NovelReaderTextAlignModeCodec.fromStorage(row['text_align'] as String?),
      showProgressIndicator:
          _intToBool(row['show_progress_indicator'] as int?, defaults.showProgressIndicator),
      showChapterTitle: _intToBool(
        row['show_chapter_title'] as int?,
        defaults.showChapterTitle,
      ),
    );
  }

  bool _intToBool(int? value, bool fallback) {
    if (value == null) {
      return fallback;
    }
    return value != 0;
  }

  @override
  Future<void> upsertNovelBySeed({
    required NovelRefreshSeed seed,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    final detail = await _runThreadRequest(
      executionContext: executionContext,
      kind: FavoriteFirstSyncRequestKind.novelSeedDetail,
      action: () => _threadGateway.getThreadDetail(tid: seed.tid, page: 1),
    );
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    final novelId = _buildNovelId(seed.fid, seed.tid);

    await db.transaction((txn) async {
      await txn.insert(
        ComicLocalDb.worksTable,
        <String, Object?>{
          'work_id': novelId,
          'content_type': _contentType,
          'source_tid': detail.tid,
          'source_fid': seed.fid,
          'source_typeid': _normalizeNullable(seed.typeid ?? detail.typeid),
          'source_tag_name': _normalizeNullable(seed.tagName),
          'title': detail.subject.trim().isEmpty ? '未命名小说' : detail.subject.trim(),
          'author': detail.author.trim().isEmpty ? null : detail.author.trim(),
          'cover_image_url': null,
          'cover_local_path': null,
          'custom_cover_local_path': null,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final exists = await txn.query(
        ComicLocalDb.novelShelfItemsTable,
        columns: <String>['id'],
        where: 'category_id = ? AND novel_id = ?',
        whereArgs: <Object>[_defaultCategoryId, novelId],
        limit: 1,
      );
      if (exists.isEmpty) {
        final sortOrder = await _nextShelfSortOrder(txn, categoryId: _defaultCategoryId);
        await txn.insert(
          ComicLocalDb.novelShelfItemsTable,
          <String, Object?>{
            'category_id': _defaultCategoryId,
            'novel_id': novelId,
            'added_at': now,
            'sort_order': sortOrder,
          },
        );
      }
    });
  }

  @override
  Future<NovelEpisodeRefreshResult> refreshEpisodes({
    required String novelId,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    final detail = await getDetail(novelId: novelId);
    if (detail == null) {
      throw StateError('小说不存在');
    }

    final pages = await _fetchPages(
      tid: detail.sourceTid,
      executionContext: executionContext,
    );
    final plan = _discoveryService.buildPlan(novelId: novelId, pages: pages);
    final db = await _dbFuture;
    var inserted = 0;
    var updated = 0;

    await db.transaction((txn) async {
      final planEpisodeIds = plan.episodes.map((episode) => episode.episodeId).toSet();
      for (final draft in plan.episodes) {
        final existing = await txn.query(
          ComicLocalDb.workEpisodesTable,
          columns: <String>['episode_id'],
          where: 'episode_id = ?',
          whereArgs: <Object>[draft.episodeId],
          limit: 1,
        );

        await txn.insert(
          ComicLocalDb.workEpisodesTable,
          <String, Object?>{
            'episode_id': draft.episodeId,
            'work_id': novelId,
            'content_type': _contentType,
            'source_tid': draft.sourceTid,
            'source_pid': draft.sourcePid,
            'source_page': draft.sourcePage,
            'episode_title': draft.episodeTitle,
            'order_index': draft.orderIndex,
            'dateline_text': draft.datelineText,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        await txn.insert(
          ComicLocalDb.novelEpisodeContentTable,
          <String, Object?>{
            'episode_id': draft.episodeId,
            'raw_html': draft.rawHtml,
            'plain_text': draft.plainText,
            'paragraph_json': jsonEncode(draft.paragraphs),
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        if (existing.isEmpty) {
          inserted++;
        } else {
          updated++;
        }
      }

      // A refresh is a full snapshot for one novel thread. Removing stale
      // episode rows prevents earlier bad parses (for example tid-as-chapter
      // entries) from continuing to appear after the parser has been fixed.
      if (planEpisodeIds.isNotEmpty) {
        final existingRows = await txn.query(
          ComicLocalDb.workEpisodesTable,
          columns: <String>['episode_id'],
          where: 'work_id = ? AND content_type = ?',
          whereArgs: <Object>[novelId, _contentType],
        );
        for (final row in existingRows) {
          final episodeId = row['episode_id'] as String;
          if (planEpisodeIds.contains(episodeId)) {
            continue;
          }
          await txn.delete(
            ComicLocalDb.novelEpisodeContentTable,
            where: 'episode_id = ?',
            whereArgs: <Object>[episodeId],
          );
          await txn.delete(
            ComicLocalDb.workEpisodesTable,
            where: 'episode_id = ?',
            whereArgs: <Object>[episodeId],
          );
        }
      }

      await txn.update(
        ComicLocalDb.worksTable,
        <String, Object?>{
          'title': plan.subject.trim().isEmpty ? detail.title : plan.subject.trim(),
          'author': plan.author.trim().isEmpty ? detail.author : plan.author.trim(),
          // Parser-produced cover is a candidate only; keep an existing cover
          // when the current refresh does not discover a reliable image.
          if (_normalizeNullable(plan.coverImageUrl) != null) 'cover_image_url': _normalizeNullable(plan.coverImageUrl),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'work_id = ? AND content_type = ?',
        whereArgs: <Object>[novelId, _contentType],
      );
    });

    final coverUrl = _normalizeNullable(plan.coverImageUrl);
    if (coverUrl != null) {
      final coverResult = await _cacheNovelCover(
        novelId: novelId,
        sourceUrl: coverUrl,
      );
      if (coverResult?.localPath != null) {
        await updateCoverCache(
          novelId: novelId,
          coverImageUrl: coverUrl,
          coverLocalPath: coverResult!.localPath,
        );
      }
    }

    final total = await getEpisodes(novelId: novelId);
    return NovelEpisodeRefreshResult(
      insertedCount: inserted,
      updatedCount: updated,
      totalCount: total.length,
    );
  }

  @override
  Future<void> removeFromShelf({required String novelId}) async {
    final db = await _dbFuture;
    await db.delete(
      ComicLocalDb.novelShelfItemsTable,
      where: 'novel_id = ?',
      whereArgs: <Object>[novelId],
    );
  }

  @override
  Future<void> purgeWork({required String novelId}) async {
    final db = await _dbFuture;
    await db.transaction((txn) async {
      await txn.delete(
        ComicLocalDb.readerBookmarksTable,
        where: 'novel_id = ?',
        whereArgs: <Object>[novelId],
      );
      await txn.delete(
        ComicLocalDb.novelReadingProgressTable,
        where: 'novel_id = ?',
        whereArgs: <Object>[novelId],
      );
      await txn.delete(
        ComicLocalDb.worksTable,
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
    String? anchorNodeId,
    double progressPercent = 0,
  }) async {
    final db = await _dbFuture;
    await db.insert(
      ComicLocalDb.novelReadingProgressTable,
      <String, Object?>{
        'novel_id': novelId,
        'episode_id': episodeId,
        'scroll_offset': scrollOffset,
        'flow_mode': flowMode.storageValue,
        'page_index': pageIndex < 0 ? 0 : pageIndex,
        'anchor_node_id': _normalizeNullable(anchorNodeId),
        'progress_percent': progressPercent.clamp(0.0, 1.0).toDouble(),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<NovelReadingProgress?> getReadingProgress({required String novelId}) async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.novelReadingProgressTable,
      where: 'novel_id = ?',
      whereArgs: <Object>[novelId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    final episodeId = (row['episode_id'] as String?) ?? '';
    if (episodeId.isEmpty) {
      return null;
    }

    return NovelReadingProgress(
      novelId: novelId,
      episodeId: episodeId,
      scrollOffset: (row['scroll_offset'] as num?)?.toDouble() ?? 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch((row['updated_at'] as int?) ?? 0),
      flowMode: NovelReaderFlowModeCodec.fromStorage(row['flow_mode'] as String?),
      pageIndex:
          ((row['page_index'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30).toInt(),
      anchorNodeId: _normalizeNullable(row['anchor_node_id'] as String?),
      progressPercent:
          ((row['progress_percent'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0).toDouble(),
    );
  }

  @override
  Future<List<NovelReaderBookmark>> listReaderBookmarks({
    required String novelId,
  }) async {
    final db = await _dbFuture;
    final readerRows = await db.query(
      ComicLocalDb.readerBookmarksTable,
      where: 'novel_id = ?',
      whereArgs: <Object>[novelId],
      orderBy: 'created_at ASC',
    );
    final episodeRows = await db.rawQuery('''
      SELECT e.episode_id, e.episode_title
      FROM ${ComicLocalDb.workEpisodesTable} e
      INNER JOIN ${ComicLocalDb.libraryEpisodeStateTable} state
        ON state.episode_id = e.episode_id
       AND state.content_type = ?
       AND state.work_id = e.work_id
      WHERE e.work_id = ?
        AND e.content_type = ?
        AND state.is_bookmarked = 1
      ORDER BY e.order_index ASC
    ''', <Object>[_contentType, novelId, _contentType]);
    final readerBookmarks = readerRows
        .map(_rowToReaderBookmark)
        .whereType<NovelReaderBookmark>()
        .toList(growable: false);
    final episodeBookmarks = episodeRows
        .map((row) => _rowToEpisodeBookmark(row, novelId: novelId))
        .whereType<NovelReaderBookmark>()
        .toList(growable: false);
    return <NovelReaderBookmark>[
      ...episodeBookmarks,
      ...readerBookmarks,
    ];
  }

  @override
  Future<void> addReaderBookmark({
    required NovelReaderBookmark bookmark,
  }) async {
    final db = await _dbFuture;
    await db.insert(
      ComicLocalDb.readerBookmarksTable,
      <String, Object?>{
        'bookmark_id': bookmark.bookmarkId,
        'novel_id': bookmark.novelId,
        'episode_id': bookmark.episodeId,
        'node_id': _normalizeNullable(bookmark.anchor.nodeId),
        'text_offset': bookmark.anchor.textOffset < 0 ? 0 : bookmark.anchor.textOffset,
        'page_index': bookmark.anchor.pageIndex < 0 ? 0 : bookmark.anchor.pageIndex,
        'scroll_offset': bookmark.anchor.scrollOffset < 0 ? 0 : bookmark.anchor.scrollOffset,
        'progress_percent':
            bookmark.anchor.progressPercent.clamp(0.0, 1.0).toDouble(),
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
  Future<void> removeReaderBookmark({
    required String bookmarkId,
  }) async {
    final db = await _dbFuture;
    await db.delete(
      ComicLocalDb.readerBookmarksTable,
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

  String _buildNovelId(String fid, String tid) => 'novel:$fid:$tid';

  NovelItem _rowToNovelItem(Map<String, Object?> row) {
    return NovelItem(
      novelId: row['work_id'] as String,
      sourceTid: row['source_tid'] as String,
      sourceFid: row['source_fid'] as String,
      sourceTypeId: row['source_typeid'] as String?,
      sourceTagName: row['source_tag_name'] as String?,
      title: row['title'] as String,
      author: row['author'] as String?,
      coverImageUrl: row['cover_image_url'] as String?,
      coverLocalPath: row['cover_local_path'] as String?,
      customCoverLocalPath: row['custom_cover_local_path'] as String?,
      updatedAt: DateTime.fromMillisecondsSinceEpoch((row['updated_at'] as int?) ?? 0),
      episodeCount: (row['episode_count'] as int?) ?? 0,
      categoryId: (row['category_id'] as String?) ?? _defaultCategoryId,
    );
  }

  Future<List<LibraryCategory>> _loadLibraryCategories(Database db) async {
    final rows = await db.query(
      ComicLocalDb.novelCategoriesTable,
      orderBy: 'sort_order ASC, created_at ASC',
    );
    return rows
        .map(
          (row) => LibraryCategory(
            categoryId: row['category_id'] as String,
            name: row['name'] as String,
            sortOrder: row['sort_order'] as int,
            createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
          ),
        )
        .toList(growable: false);
  }

  LibraryWorkItem _rowToLibraryWorkItem(Map<String, Object?> row) {
    final unreadCount = row['unread_count'] as int? ?? 0;
    final readCount = row['read_count'] as int? ?? 0;
    return LibraryWorkItem(
      workId: row['work_id'] as String,
      categoryId: (row['category_id'] as String?) ?? _defaultCategoryId,
      title: row['title'] as String,
      secondaryName: row['author'] as String?,
      coverImageUrl: row['cover_image_url'] as String?,
      coverLocalPath: row['cover_local_path'] as String?,
      customCoverLocalPath: row['custom_cover_local_path'] as String?,
      unreadCount: unreadCount,
      totalChapterCount: row['total_count'] as int? ?? unreadCount + readCount,
      readChapterCount: readCount,
      addedAt: DateTime.fromMillisecondsSinceEpoch(row['added_at'] as int? ?? 0),
      lastReadAt: _toDateTime(row['last_read_at']),
      workUpdatedAt: _toDateTime(row['work_updated_at']),
      lastCheckedAt: _toDateTime(row['check_updated_at']),
      lastFetchedAt: _toDateTime(row['fetched_updated_at']),
      hasTags: (row['has_tags'] as int? ?? 0) == 1,
      isDownloaded: (row['downloaded_count'] as int? ?? 0) > 0,
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
        progressPercent:
            ((row['progress_percent'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0).toDouble(),
      ),
      title: (row['title'] as String?) ?? '',
      snippet: (row['snippet'] as String?) ?? '',
      note: _normalizeNullable(row['note'] as String?),
      createdAt: DateTime.fromMillisecondsSinceEpoch((row['created_at'] as int?) ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch((row['updated_at'] as int?) ?? 0),
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
      title: (row['episode_title'] as String?) ?? '章节书签',
      snippet: '章节书签',
      createdAt: updatedAt,
      updatedAt: updatedAt,
    );
  }

  Future<int> _nextShelfSortOrder(Transaction txn, {required String categoryId}) async {
    final countResult = await txn.rawQuery(
      'SELECT COUNT(*) AS count FROM ${ComicLocalDb.novelShelfItemsTable} WHERE category_id = ?',
      <Object>[categoryId],
    );
    return (countResult.first['count'] as int?) ?? 0;
  }

  Future<List<ThreadDetailData>> _fetchPages({
    required String tid,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    final pages = <ThreadDetailData>[];
    for (var page = 1; page <= _maxRefreshPages; page++) {
      final detail = await _runThreadRequest(
        executionContext: executionContext,
        kind: FavoriteFirstSyncRequestKind.novelEpisodePage,
        action: () => _threadGateway.getThreadDetail(tid: tid, page: page),
      );
      if (detail.posts.isEmpty) {
        break;
      }
      pages.add(detail);
      if (!detail.hasMore || detail.posts.length < detail.perPage) {
        break;
      }
    }
    return pages;
  }

  Future<CachedImageResult?> _cacheNovelCover({
    required String novelId,
    required String sourceUrl,
  }) async {
    final cacheService = _imageCacheService;
    if (cacheService == null) {
      return null;
    }
    final result = await cacheService.ensureCached(
      ImageCacheRequest(
        cacheKey: ImageCacheKeys.novelCover(novelId),
        sourceUrl: sourceUrl,
        ownerType: ImageCacheOwnerType.novel,
        ownerId: novelId,
        role: ImageCacheRole.cover,
        protected: true,
      ),
    );
    return result.success ? result : null;
  }

  String? _normalizeNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<T> _runThreadRequest<T>({
    required FavoriteSyncExecutionContext? executionContext,
    required FavoriteFirstSyncRequestKind kind,
    required Future<T> Function() action,
  }) {
    final governor = executionContext?.governor;
    if (governor == null) {
      return action();
    }
    return governor.run(kind: kind, action: action);
  }

  DateTime? _toDateTime(Object? value) {
    if (value is! int || value <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
}

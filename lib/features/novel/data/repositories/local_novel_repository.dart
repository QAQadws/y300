import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/favorites/data/services/favorite_first_sync_request_governor.dart';
import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
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
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/novel/domain/services/novel_episode_discovery_service.dart';
import 'package:y300/features/novel/domain/services/novel_intro_section_extractor.dart';
import 'package:y300/features/novel/data/services/novel_reader_progress_diagnostics.dart';
import 'package:y300/features/novel/domain/services/novel_title_sanitizer.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';

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
    LegacyNovelThreadGateway? threadGateway,
    NovelEpisodeDiscoveryService? discoveryService,
    ImageCacheService? imageCacheService,
    NovelTitleSanitizer? titleSanitizer,
    NovelIntroSectionExtractor? introExtractor,
    LibraryStateRepository? stateRepository,
  }) : _threadGateway = threadGateway,
       _discoveryService = discoveryService,
       _titleSanitizer = titleSanitizer,
       _introExtractor = introExtractor,
       _stateRepository =
           stateRepository ?? LocalLibraryStateRepository(_dbFuture);

  final Future<Database> _dbFuture;
  final LegacyNovelThreadGateway? _threadGateway;
  final NovelEpisodeDiscoveryService? _discoveryService;
  final NovelTitleSanitizer? _titleSanitizer;
  final NovelIntroSectionExtractor? _introExtractor;
  final LibraryStateRepository _stateRepository;

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
        'SELECT COUNT(*) AS count FROM ${ComicLocalDb.novelCategoriesTable}',
      );
      final sortOrder = (countResult.first['count'] as int?) ?? 0;
      await txn.insert(ComicLocalDb.novelCategoriesTable, <String, Object?>{
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
      ComicLocalDb.novelCategoriesTable,
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
          final sortOrder = await _nextShelfSortOrder(
            txn,
            categoryId: _defaultCategoryId,
          );
          await txn.insert(ComicLocalDb.novelShelfItemsTable, <String, Object?>{
            'category_id': _defaultCategoryId,
            'novel_id': novelId,
            'added_at': now,
            'sort_order': sortOrder,
          });
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
        final sortOrder = await _nextShelfSortOrder(
          txn,
          categoryId: toCategoryId,
        );
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
      FROM ${ComicLocalDb.novelShelfItemsTable} si
      INNER JOIN ${ComicLocalDb.worksTable} w
        ON si.novel_id = w.work_id
      LEFT JOIN ${ComicLocalDb.workEpisodesTable} e
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
        FROM ${ComicLocalDb.workEpisodesTable}
        WHERE content_type = ?
        GROUP BY work_id
      ),
      bookmark_stats AS (
        SELECT work_id, 1 AS has_bookmarks
        FROM ${ComicLocalDb.libraryEpisodeStateTable}
        WHERE content_type = ? AND is_bookmarked = 1
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
      FROM ${ComicLocalDb.novelShelfItemsTable} si
      INNER JOIN ${ComicLocalDb.worksTable} w
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
      FROM ${ComicLocalDb.worksTable} w
      LEFT JOIN ${ComicLocalDb.workEpisodesTable} e
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
      ComicLocalDb.worksTable,
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
      ComicLocalDb.worksTable,
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
        ComicLocalDb.worksTable,
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
        ComicLocalDb.worksTable,
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
      ComicLocalDb.worksTable,
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
      ComicLocalDb.worksTable,
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
      ComicLocalDb.worksTable,
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

  /// Legacy fixture helper. Production ingest uses source metadata services.
  Future<void> upsertNovelBySeed({
    required NovelRefreshSeed seed,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    final threadGateway = _requireLegacyThreadGateway();
    final detail = await _runThreadRequest(
      executionContext: executionContext,
      kind: FavoriteFirstSyncRequestKind.novelSeedDetail,
      action: () => threadGateway.getThreadDetail(tid: seed.tid, page: 1),
    );
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    final novelId = _buildNovelId(seed.fid, seed.tid);

    await db.transaction((txn) async {
      await txn.insert(ComicLocalDb.worksTable, <String, Object?>{
        'work_id': novelId,
        'content_type': _contentType,
        'source_tid': detail.tid,
        'source_fid': seed.fid,
        'source_typeid': _normalizeNullable(seed.typeid ?? detail.typeid),
        'source_tag_name': _normalizeNullable(seed.tagName),
        'title': _sanitizeTitleForStorage(detail.subject),
        'author': detail.author.trim().isEmpty ? null : detail.author.trim(),
        'cover_image_url': null,
        'cover_local_path': null,
        'custom_cover_local_path': null,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final exists = await txn.query(
        ComicLocalDb.novelShelfItemsTable,
        columns: <String>['id'],
        where: 'category_id = ? AND novel_id = ?',
        whereArgs: <Object>[_defaultCategoryId, novelId],
        limit: 1,
      );
      if (exists.isEmpty) {
        final sortOrder = await _nextShelfSortOrder(
          txn,
          categoryId: _defaultCategoryId,
        );
        await txn.insert(ComicLocalDb.novelShelfItemsTable, <String, Object?>{
          'category_id': _defaultCategoryId,
          'novel_id': novelId,
          'added_at': now,
          'sort_order': sortOrder,
        });
      }
    });
  }

  /// Legacy fixture helper. Production updates use NovelChapterUpdateService.
  Future<NovelEpisodeRefreshResult> refreshEpisodes({
    required String novelId,
    NovelEpisodeRefreshMode mode = NovelEpisodeRefreshMode.full,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    final detail = await getDetail(novelId: novelId);
    if (detail == null) {
      throw StateError('小说不存在');
    }

    // 增量模式有三种降级到 full 的情况，全部由仓库内部判定，调用方不感知：
    //   1) 本地零章节 —— 没有起点
    //   2) 已知最大 source_page <= 1 —— 单页内全量与增量等价
    //   3) catalog 模式（page=1 上 >= 2 个章节）—— 目录散落多页，
    //      跳过首页会让 rule 链生成与目录不一致的标题，发生标题漂移
    final resolved = mode == NovelEpisodeRefreshMode.incremental
        ? await _resolveIncrementalContext(novelId: novelId)
        : null;

    if (resolved != null) {
      return _refreshEpisodesIncremental(
        novelId: novelId,
        detail: detail,
        context: resolved,
        executionContext: executionContext,
      );
    }
    return _refreshEpisodesFull(
      novelId: novelId,
      detail: detail,
      executionContext: executionContext,
    );
  }

  Future<NovelEpisodeRefreshResult> _refreshEpisodesFull({
    required String novelId,
    required NovelItem detail,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    final pages = await _fetchPages(
      tid: detail.sourceTid,
      executionContext: executionContext,
    );
    final plan = _requireLegacyDiscoveryService().buildPlan(
      novelId: novelId,
      pages: pages,
    );
    final db = await _dbFuture;
    var inserted = 0;
    var updated = 0;

    await db.transaction((txn) async {
      final planEpisodeIds = plan.episodes
          .map((episode) => episode.episodeId)
          .toSet();
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
          'title': _sanitizeTitleForStorage(
            plan.subject,
            fallback: detail.title,
          ),
          'author': plan.author.trim().isEmpty
              ? detail.author
              : plan.author.trim(),
          // Parser-produced cover is a candidate only; keep an existing cover
          // when the current refresh does not discover a reliable image.
          if (_normalizeNullable(plan.coverImageUrl) != null)
            'cover_image_url': _normalizeNullable(plan.coverImageUrl),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'work_id = ? AND content_type = ?',
        whereArgs: <Object>[novelId, _contentType],
      );
    });

    // 简介自动解析：仅当用户没有手动编辑过 intro_text 时才写入。
    // 这样可以保留用户的「编辑简介」结果，同时让首次入库 / 用户未编辑
    // 的小说自动获得简介展示。
    await _maybeWriteParsedIntro(novelId: novelId, pages: pages);

    final total = await getEpisodes(novelId: novelId);
    return NovelEpisodeRefreshResult(
      insertedCount: inserted,
      updatedCount: updated,
      totalCount: total.length,
    );
  }

  /// 增量刷新：保留所有旧章节，只把从 [_IncrementalRefreshContext.startPage]
  /// 起重新解析得到的章节合并写回；标题仍走 sanitizer，封面/简介/作者不动。
  Future<NovelEpisodeRefreshResult> _refreshEpisodesIncremental({
    required String novelId,
    required NovelItem detail,
    required _IncrementalRefreshContext context,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    final pages = await _fetchPages(
      tid: detail.sourceTid,
      startPage: context.startPage,
      executionContext: executionContext,
    );

    final db = await _dbFuture;

    // 起点页已经被论坛删了或越过了末页 —— 帖子层面没新内容，但论坛 subject
    // 字段可能仍然在变（楼主在标题里改更新时间是常见操作）。
    // 单独再发一发 page=startPage 的请求拿最新 subject 也没必要 —— 上面那个
    // _fetchPages 第一发就是 startPage，如果它返回 posts 空但 detail data 非空
    // 也算成功，所以这里只在 pages 完全空（终止于第一发就 break 之前）时退出。
    if (pages.isEmpty) {
      return NovelEpisodeRefreshResult(
        insertedCount: 0,
        updatedCount: 0,
        totalCount: (await getEpisodes(novelId: novelId)).length,
      );
    }

    final plan = _requireLegacyDiscoveryService().buildPlan(
      novelId: novelId,
      pages: pages,
      options: NovelDiscoveryOptions(
        orderIndexOffset: context.nextOrderIndex,
        skipCatalogExtraction: true,
        skipFirstChapterMetadata: true,
      ),
    );

    var inserted = 0;
    var updated = 0;
    // 新章节专用计数器：从 maxOrder+1 起严格递增，绕开 draft.orderIndex —— 因为
    // 既有章节会复用旧 order_index，让 draft 计数器和实际 DB 值脱节，新章节用
    // draft.orderIndex 会留下空洞（例如 0,1,3）。这里保证连续编号。
    var nextNewOrderIndex = context.nextOrderIndex;

    await db.transaction((txn) async {
      for (final draft in plan.episodes) {
        final existing = await txn.query(
          ComicLocalDb.workEpisodesTable,
          columns: <String>['episode_id', 'order_index', 'episode_title'],
          where: 'episode_id = ?',
          whereArgs: <Object>[draft.episodeId],
          limit: 1,
        );

        // 既有章节锁定 order_index 与标题（避免 rule 链覆盖之前 catalog 抽取
        // 出的更可信标题），仅更新位置元数据；新章节按计数器分配 order_index。
        final isExisting = existing.isNotEmpty;
        final int preservedOrderIndex;
        final String preservedTitle;
        if (isExisting) {
          preservedOrderIndex =
              (existing.first['order_index'] as int?) ?? draft.orderIndex;
          preservedTitle =
              (existing.first['episode_title'] as String?) ??
              draft.episodeTitle;
        } else {
          preservedOrderIndex = nextNewOrderIndex++;
          preservedTitle = draft.episodeTitle;
        }

        await txn.insert(
          ComicLocalDb.workEpisodesTable,
          <String, Object?>{
            'episode_id': draft.episodeId,
            'work_id': novelId,
            'content_type': _contentType,
            'source_tid': draft.sourceTid,
            'source_pid': draft.sourcePid,
            'source_page': draft.sourcePage,
            'episode_title': preservedTitle,
            'order_index': preservedOrderIndex,
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

        if (isExisting) {
          updated++;
        } else {
          inserted++;
        }
      }

      // 标题仍重写：论坛把更新时间塞进 subject 是常态，sanitize 是纯函数
      // 无副作用。author/cover_image_url/intro 在增量模式没有可信新数据，
      // 不动。
      await txn.update(
        ComicLocalDb.worksTable,
        <String, Object?>{
          'title': _sanitizeTitleForStorage(
            plan.subject,
            fallback: detail.title,
          ),
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'work_id = ? AND content_type = ?',
        whereArgs: <Object>[novelId, _contentType],
      );
    });

    final total = await getEpisodes(novelId: novelId);
    return NovelEpisodeRefreshResult(
      insertedCount: inserted,
      updatedCount: updated,
      totalCount: total.length,
    );
  }

  /// 决定增量刷新的起点 / 锚点 orderIndex；返回 null 表示需要降级为 full。
  ///
  /// 降级条件保持最小化 —— 仅在「真的没起点」时降级：
  ///   1) 本地零章节 —— 没有 MAX(source_page) 可用
  ///   2) MAX(source_page) <= 1 —— 单页内增量与全量等价
  ///
  /// 早期版本曾用 `page=1 上 >= 2 章节` 作为 catalog 模式启发式来再次降级，但这条
  /// 在 ppp=200 的多页小说上几乎总命中（page=1 自然就有几十章），把所有正常增量
  /// 刷新都打回了全量。又因为 `_refreshEpisodesIncremental` 已经显式保留既有章节
  /// 的 episode_title（避免 rule 链覆盖 catalog 抽出的更可信标题），catalog → rule
  /// 切换不再造成标题漂移，这条启发式的防御价值就消失了。
  Future<_IncrementalRefreshContext?> _resolveIncrementalContext({
    required String novelId,
  }) async {
    final db = await _dbFuture;
    final rows = await db.rawQuery(
      '''
      SELECT
        MAX(source_page) AS max_page,
        MAX(order_index) AS max_order,
        COUNT(*) AS total_count
      FROM ${ComicLocalDb.workEpisodesTable}
      WHERE work_id = ? AND content_type = ?
      ''',
      <Object>[novelId, _contentType],
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    final totalCount = (row['total_count'] as int?) ?? 0;
    if (totalCount == 0) {
      return null;
    }
    final maxPage = (row['max_page'] as int?) ?? 0;
    if (maxPage <= 1) {
      return null;
    }
    final maxOrder = (row['max_order'] as int?) ?? -1;
    return _IncrementalRefreshContext(
      startPage: maxPage,
      nextOrderIndex: maxOrder + 1,
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
    int? pageCount,
    String? anchorNodeId,
    int anchorTextOffset = 0,
    String? paginationKey,
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
      ComicLocalDb.novelReadingProgressTable,
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
      ComicLocalDb.readerBookmarksTable,
      where: 'novel_id = ?',
      whereArgs: <Object>[novelId],
      orderBy: 'created_at ASC',
    );
    final episodeRows = await db.rawQuery(
      '''
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
      ComicLocalDb.readerBookmarksTable,
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
      ComicLocalDb.novelCategoriesTable,
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
      'SELECT COUNT(*) AS count FROM ${ComicLocalDb.novelShelfItemsTable} WHERE category_id = ?',
      <Object>[categoryId],
    );
    return (countResult.first['count'] as int?) ?? 0;
  }

  Future<List<ThreadDetailData>> _fetchPages({
    required String tid,
    int startPage = 1,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    final threadGateway = _requireLegacyThreadGateway();
    final pages = <ThreadDetailData>[];
    final endPage = startPage + _maxRefreshPages - 1;
    for (var page = startPage; page <= endPage; page++) {
      final detail = await _runThreadRequest(
        executionContext: executionContext,
        kind: FavoriteFirstSyncRequestKind.novelEpisodePage,
        action: () => threadGateway.getThreadDetail(tid: tid, page: page),
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

  String? _normalizeNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  /// 应用标题清洗，并在为空时回退到上一次的原始标题。
  ///
  /// `fallback` 用于 `refreshEpisodes` 路径 —— 解析后的 plan.subject
  /// 偶尔为空，此时不能把已存的 title 抹成空值。
  String _sanitizeTitleForStorage(String rawTitle, {String? fallback}) {
    final sanitized = (_titleSanitizer ?? const DefaultNovelTitleSanitizer())
        .sanitize(rawTitle);
    if (sanitized.isNotEmpty) {
      return sanitized;
    }
    final fallbackTrimmed = fallback?.trim();
    if (fallbackTrimmed != null && fallbackTrimmed.isNotEmpty) {
      return fallbackTrimmed;
    }
    return '';
  }

  /// 取首页第一个 OP 帖（楼层 1）的 message —— 简介解析的输入源。
  String? _findFirstOpPostHtml(List<ThreadDetailData> pages) {
    if (pages.isEmpty) {
      return null;
    }
    final firstPage = pages.first;
    if (firstPage.posts.isEmpty) {
      return null;
    }
    final opAuthorId = firstPage.posts.first.authorId;
    for (final post in firstPage.posts) {
      final isOpPost = opAuthorId.isEmpty || post.authorId == opAuthorId;
      if (isOpPost && post.message.trim().isNotEmpty) {
        return post.message;
      }
    }
    return null;
  }

  /// 解析首楼简介并写入 library_work_state.intro_text，仅当当前为空。
  ///
  /// 用户通过「编辑简介」写入的值会被保留：一旦 intro_text 非空，刷新流程
  /// 不再覆盖。首次入库或用户从未编辑过的情况下，这里的解析结果会展示。
  Future<void> _maybeWriteParsedIntro({
    required String novelId,
    required List<ThreadDetailData> pages,
  }) async {
    final firstPostHtml = _findFirstOpPostHtml(pages);
    if (firstPostHtml == null) {
      return;
    }
    final parsed =
        (_introExtractor ?? const DefaultNovelIntroSectionExtractor()).extract(
          firstPostHtml: firstPostHtml,
        );
    if (parsed == null || parsed.isEmpty) {
      return;
    }
    final existing = await _stateRepository.getWorkState(
      moduleKey: LibraryModuleKey.novel,
      workId: novelId,
    );
    final hasUserIntro = (existing?.introText?.trim().isNotEmpty ?? false);
    if (hasUserIntro) {
      return;
    }
    await _stateRepository.upsertWorkState(
      moduleKey: LibraryModuleKey.novel,
      workId: novelId,
      introText: parsed,
    );
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

  LegacyNovelThreadGateway _requireLegacyThreadGateway() {
    return _threadGateway ??
        (throw UnsupportedError('Legacy novel thread refresh is disabled.'));
  }

  NovelEpisodeDiscoveryService _requireLegacyDiscoveryService() {
    return _discoveryService ??
        (throw UnsupportedError('Legacy novel discovery is disabled.'));
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

/// 增量刷新决策结果。
///
/// `startPage` 是从哪一页开始重新拉（含），等于本地最大 `source_page`。
/// `nextOrderIndex` 是新章节起始 `order_index`，等于本地最大 `order_index + 1`。
class _IncrementalRefreshContext {
  const _IncrementalRefreshContext({
    required this.startPage,
    required this.nextOrderIndex,
  });

  final int startPage;
  final int nextOrderIndex;
}

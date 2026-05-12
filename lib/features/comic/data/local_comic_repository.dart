import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:y300/features/cache/domain/image_cache_keys.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/local/comic_local_models.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_query_utils.dart';

/// 基于 SQLite 的漫画仓库实现。
class LocalComicRepository
    implements
        ComicRepository,
        ComicShelfSnapshotRepository,
        ComicShelfStatsRepository,
        ComicCoverCacheWriter,
        ComicEpisodeImageCacheMetadataWriter {
  LocalComicRepository(
    this._dbFuture, {
    ComicSubjectParser? subjectParser,
  }) : _subjectParser = subjectParser ?? const RuleBasedComicSubjectParser();

  static const String _defaultCategoryId = 'default';

  final Future<Database> _dbFuture;
  final ComicSubjectParser _subjectParser;

  @override
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
    final categoryId = 'c$now${Random().nextInt(1000)}';

    await db.transaction((txn) async {
      final countResult = await txn.rawQuery(
        'SELECT COUNT(*) AS count FROM ${ComicLocalDb.categoriesTable}',
      );
      final sortOrder = (countResult.first['count'] as int?) ?? 0;

      await txn.insert(
        ComicLocalDb.categoriesTable,
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
      ComicLocalDb.categoriesTable,
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
          whereArgs: <Object>[_defaultCategoryId, comicId],
          limit: 1,
        );

        if (existsInDefault.isEmpty) {
          final sortOrder = await _nextSortOrder(txn, categoryId: _defaultCategoryId);
          await txn.insert(
            ComicLocalDb.shelfItemsTable,
            ShelfItemRecord(
              categoryId: _defaultCategoryId,
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

  @override
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
        final sortOrder = await _nextSortOrder(txn, categoryId: toCategoryId);
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

  @override
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
    final count = _normalizeColumnCount(parsed ?? 3);

    return ComicShelfDisplaySettings(gridColumnCount: count);
  }

  @override
  Future<void> updateGridColumnCount({required int columnCount}) async {
    final db = await _dbFuture;
    final normalized = _normalizeColumnCount(columnCount);

    await db.insert(
      ComicLocalDb.settingsTable,
      <String, Object?>{
        'key': 'grid_column_count',
        'value': normalized.toString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> updateCustomCover({
    required String comicId,
    required String? customCoverImageUrl,
  }) async {
    final db = await _dbFuture;
    await db.update(
      ComicLocalDb.comicsTable,
      <String, Object?>{
        'custom_cover_image_url': customCoverImageUrl?.trim().isEmpty ?? true
            ? null
            : customCoverImageUrl!.trim(),
        'custom_cover_local_path': null,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
  }

  @override
  Future<void> updateCoverCache({
    required String comicId,
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
      ComicLocalDb.comicsTable,
      values,
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
  }

  @override
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

  @override
  Future<void> addToShelf({
    required String comicId,
    required String tid,
    required String fid,
    String? sourceTypeId,
    String? sourceTagName,
    required String title,
    required ParsedComicPost parsedPost,
  }) async {
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      final comic = ComicRecord(
        comicId: comicId,
        sourceTid: tid,
        sourceFid: fid,
        sourceTypeId: _normalizeNullable(sourceTypeId),
        sourceTagName: _normalizeNullable(sourceTagName),
        title: _resolveComicTitle(rawTitle: title, parsedPost: parsedPost),
        author: _resolveComicAuthor(parsedPost),
        translationGroup: parsedPost.subjectMetadata?.translationGroup,
        coverImageUrl: parsedPost.imageUrls.isEmpty ? null : parsedPost.imageUrls.first,
        customCoverImageUrl: null,
        coverLocalPath: null,
        customCoverLocalPath: null,
        createdAt: now,
        updatedAt: now,
        lastReadEpisodeId: null,
      );

      await txn.insert(
        ComicLocalDb.comicsTable,
        comic.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      for (var index = 0; index < parsedPost.episodeLinks.length; index++) {
        final link = parsedPost.episodeLinks[index];
        final sourceTid = _extractTid(link.url) ?? tid;
        final episodeId = '$comicId:$sourceTid';
        final episode = EpisodeRecord(
          episodeId: episodeId,
          comicId: comicId,
          episodeTitle: link.episodeTitle ?? link.rawText,
          sourceTid: sourceTid,
          sourceUrl: link.url,
          orderIndex: index,
          publishTimeText: null,
        );

        await txn.insert(
          ComicLocalDb.episodesTable,
          episode.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      if (parsedPost.imageUrls.isNotEmpty) {
        final defaultEpisodeId = '$comicId:$tid';
        await txn.insert(
          ComicLocalDb.episodesTable,
          EpisodeRecord(
            episodeId: defaultEpisodeId,
            comicId: comicId,
            episodeTitle: '首楼',
            sourceTid: tid,
            sourceUrl: '',
            orderIndex: -1,
            publishTimeText: null,
          ).toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        for (var imageIndex = 0; imageIndex < parsedPost.imageUrls.length; imageIndex++) {
          final image = EpisodeImageRecord(
            episodeId: defaultEpisodeId,
            imageUrl: parsedPost.imageUrls[imageIndex],
            imageIndex: imageIndex,
            stableCacheKey: ImageCacheKeys.comicPage(
              comicId: comicId,
              episodeId: defaultEpisodeId,
              imageIndex: imageIndex,
            ),
            lastSourceUrl: parsedPost.imageUrls[imageIndex],
          );
          await txn.insert(
            ComicLocalDb.episodeImagesTable,
            image.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }

      final existing = await txn.query(
        ComicLocalDb.shelfItemsTable,
        columns: <String>['id'],
        where: 'category_id = ? AND comic_id = ?',
        whereArgs: <Object>[_defaultCategoryId, comicId],
        limit: 1,
      );

      if (existing.isEmpty) {
        final sortOrder = await _nextSortOrder(txn, categoryId: _defaultCategoryId);

        await txn.insert(
          ComicLocalDb.shelfItemsTable,
          ShelfItemRecord(
            categoryId: _defaultCategoryId,
            comicId: comicId,
            addedAt: now,
            sortOrder: sortOrder,
          ).toMap(),
        );
      }
    });
  }

  @override
  Future<void> removeFromShelf({required String comicId}) async {
    final db = await _dbFuture;
    await db.delete(
      ComicLocalDb.shelfItemsTable,
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
  }

  @override
  Future<List<ComicShelfItem>> getShelfItems({String categoryId = _defaultCategoryId}) async {
    final db = await _dbFuture;
    final rows = await db.rawQuery('''
      SELECT
        si.category_id,
        si.added_at,
        c.comic_id,
        c.source_typeid,
        c.source_tag_name,
        c.title,
        c.author,
        COALESCE(c.custom_cover_image_url, c.cover_image_url) AS cover_image_url,
        c.custom_cover_image_url,
        c.cover_local_path,
        c.custom_cover_local_path
      FROM ${ComicLocalDb.shelfItemsTable} si
      INNER JOIN ${ComicLocalDb.comicsTable} c
        ON si.comic_id = c.comic_id
      WHERE si.category_id = ?
      ORDER BY si.sort_order ASC, si.added_at DESC
    ''', <Object>[categoryId]);

    return rows
        .map(
          (row) => ComicShelfItem(
            comicId: row['comic_id'] as String,
            sourceTypeId: row['source_typeid'] as String?,
            sourceTagName: row['source_tag_name'] as String?,
            title: row['title'] as String,
            author: row['author'] as String?,
            coverImageUrl: row['cover_image_url'] as String?,
            customCoverImageUrl: row['custom_cover_image_url'] as String?,
            coverLocalPath: row['cover_local_path'] as String?,
            customCoverLocalPath: row['custom_cover_local_path'] as String?,
            categoryId: row['category_id'] as String,
            addedAt: DateTime.fromMillisecondsSinceEpoch(row['added_at'] as int),
          ),
        )
        .toList(growable: false);
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
        c.author,
        COALESCE(c.custom_cover_image_url, c.cover_image_url) AS cover_image_url,
        c.custom_cover_image_url,
        c.cover_local_path,
        c.custom_cover_local_path,
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
  Future<ComicShelfWorkStats> getShelfWorkStats({
    required String comicId,
  }) async {
    final db = await _dbFuture;
    final rows = await db.rawQuery('''
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
    ''', <Object>[comicId]);

    final row = rows.isEmpty ? null : rows.first;
    return ComicShelfWorkStats(
      totalCount: row?['total_count'] as int? ?? 0,
      unreadCount: row?['unread_count'] as int? ?? 0,
      readCount: row?['read_count'] as int? ?? 0,
      downloadedCount: row?['downloaded_count'] as int? ?? 0,
    );
  }

  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async {
    final db = await _dbFuture;
    final rows = await db.rawQuery('''
      SELECT
        c.comic_id,
        c.source_tid,
        c.source_fid,
        c.source_typeid,
        c.source_tag_name,
        c.title,
        c.author,
        c.translation_group,
        COALESCE(c.custom_cover_image_url, c.cover_image_url) AS cover_image_url,
        c.custom_cover_image_url,
        c.cover_local_path,
        c.custom_cover_local_path,
        c.updated_at,
        COUNT(e.episode_id) AS episode_count
      FROM ${ComicLocalDb.comicsTable} c
      LEFT JOIN ${ComicLocalDb.episodesTable} e
        ON c.comic_id = e.comic_id
      WHERE c.comic_id = ?
      GROUP BY c.comic_id
      LIMIT 1
    ''', <Object>[comicId]);

    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    return ComicDetail(
      comicId: row['comic_id'] as String,
      sourceTid: row['source_tid'] as String,
      sourceFid: row['source_fid'] as String,
      sourceTypeId: row['source_typeid'] as String?,
      sourceTagName: row['source_tag_name'] as String?,
      title: row['title'] as String,
      author: row['author'] as String?,
      translationGroup: row['translation_group'] as String?,
      coverImageUrl: row['cover_image_url'] as String?,
      customCoverImageUrl: row['custom_cover_image_url'] as String?,
      coverLocalPath: row['cover_local_path'] as String?,
      customCoverLocalPath: row['custom_cover_local_path'] as String?,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      episodeCount: row['episode_count'] as int? ?? 0,
    );
  }

  @override
  Future<List<ComicEpisodeItem>> getComicEpisodes({
    required String comicId,
    bool descending = true,
  }) async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.episodesTable,
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
      orderBy: 'order_index ${descending ? 'DESC' : 'ASC'}',
    );

    return rows
        .map(
          (row) => ComicEpisodeItem(
            episodeId: row['episode_id'] as String,
            comicId: row['comic_id'] as String,
            episodeTitle: row['episode_title'] as String?,
            sourceTid: row['source_tid'] as String,
            sourceUrl: row['source_url'] as String,
            orderIndex: row['order_index'] as int,
            publishTimeText: row['publish_time_text'] as String?,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<ComicEpisodeImageItem>> getEpisodeImages({
    required String episodeId,
  }) async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.episodeImagesTable,
      where: 'episode_id = ?',
      whereArgs: <Object>[episodeId],
      orderBy: 'image_index ASC',
    );

    return rows
        .map(
          (row) => ComicEpisodeImageItem(
            episodeId: row['episode_id'] as String,
            imageUrl: row['image_url'] as String,
            imageIndex: row['image_index'] as int,
            cacheStatus: row['cache_status'] as String,
            stableCacheKey: row['stable_cache_key'] as String?,
            lastSourceUrl: row['last_source_url'] as String?,
            localPath: row['local_path'] as String?,
            bytes: row['bytes'] as int? ?? 0,
            mimeType: row['mime_type'] as String?,
            lastAccessedAt: _toDateTime(row['last_accessed_at']),
            protected: (row['protected'] as int? ?? 0) == 1,
            cacheLocalPath: row['cache_local_path'] as String?,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> saveEpisodeImages({
    required String episodeId,
    required List<String> imageUrls,
  }) async {
    final db = await _dbFuture;
    await db.transaction((txn) async {
      await txn.delete(
        ComicLocalDb.episodeImagesTable,
        where: 'episode_id = ?',
        whereArgs: <Object>[episodeId],
      );
      for (var index = 0; index < imageUrls.length; index++) {
        await txn.insert(
          ComicLocalDb.episodeImagesTable,
          EpisodeImageRecord(
            episodeId: episodeId,
            imageUrl: imageUrls[index],
            imageIndex: index,
            stableCacheKey: _buildEpisodeImageCacheKey(
              episodeId: episodeId,
              imageIndex: index,
            ),
            lastSourceUrl: imageUrls[index],
          ).toMap(),
        );
      }
      await _promoteFirstEpisodeCoverIfNeeded(
        txn,
        episodeId: episodeId,
        imageUrls: imageUrls,
      );
    });
  }

  @override
  Future<void> updateEpisodeImageCacheStatus({
    required String episodeId,
    required String imageUrl,
    required String cacheStatus,
    String? cacheLocalPath,
  }) async {
    final db = await _dbFuture;
    await db.update(
      ComicLocalDb.episodeImagesTable,
      <String, Object?>{
        'cache_status': cacheStatus,
        'cache_local_path': cacheLocalPath,
      },
      where: 'episode_id = ? AND image_url = ?',
      whereArgs: <Object>[episodeId, imageUrl],
    );
  }

  @override
  Future<void> clearEpisodeImageCache({
    required String episodeId,
  }) async {
    final db = await _dbFuture;
    await db.update(
      ComicLocalDb.episodeImagesTable,
      <String, Object?>{
        'cache_status': 'none',
        'cache_local_path': null,
        'local_path': null,
        'bytes': 0,
        'last_accessed_at': null,
        'protected': 0,
      },
      where: 'episode_id = ? AND protected = 0',
      whereArgs: <Object>[episodeId],
    );
  }

  @override
  Future<void> updateEpisodeImageCacheMetadata({
    required String episodeId,
    required String imageUrl,
    String? stableCacheKey,
    String? lastSourceUrl,
    String? localPath,
    int? bytes,
    String? mimeType,
    DateTime? lastAccessedAt,
    bool? protected,
  }) async {
    final db = await _dbFuture;
    final values = <String, Object?>{};
    if (stableCacheKey != null) {
      values['stable_cache_key'] = _normalizeNullable(stableCacheKey);
    }
    if (lastSourceUrl != null) {
      values['last_source_url'] = _normalizeNullable(lastSourceUrl);
    }
    if (localPath != null) {
      values['local_path'] = _normalizeNullable(localPath);
      values['cache_local_path'] = _normalizeNullable(localPath);
    }
    if (bytes != null) {
      values['bytes'] = bytes;
    }
    if (mimeType != null) {
      values['mime_type'] = _normalizeNullable(mimeType);
    }
    if (lastAccessedAt != null) {
      values['last_accessed_at'] = lastAccessedAt.millisecondsSinceEpoch;
    }
    if (protected != null) {
      values['protected'] = protected ? 1 : 0;
    }
    if (values.isEmpty) {
      return;
    }
    await db.update(
      ComicLocalDb.episodeImagesTable,
      values,
      where: 'episode_id = ? AND image_url = ?',
      whereArgs: <Object>[episodeId, imageUrl],
    );
  }

  @override
  Future<void> updateLastReadProgress({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
  }) async {
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.insert(
        ComicLocalDb.readingProgressTable,
        <String, Object?>{
          'comic_id': comicId,
          'episode_id': episodeId,
          'image_index': imageIndex,
          'scroll_offset': scrollOffset,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.update(
        ComicLocalDb.comicsTable,
        <String, Object?>{
          'last_read_episode_id': episodeId,
          'updated_at': now,
        },
        where: 'comic_id = ?',
        whereArgs: <Object>[comicId],
      );
    });
  }

  @override
  Future<ComicReadingProgress?> getLastReadProgress({
    required String comicId,
  }) async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.readingProgressTable,
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }

    final row = rows.first;
    return ComicReadingProgress(
      comicId: row['comic_id'] as String,
      episodeId: row['episode_id'] as String,
      imageIndex: row['image_index'] as int,
      scrollOffset: (row['scroll_offset'] as num).toDouble(),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  @override
  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  }) async {
    final db = await _dbFuture;
    var inserted = 0;
    var updated = 0;

    await db.transaction((txn) async {
      for (var index = 0; index < episodeLinks.length; index++) {
        final link = episodeLinks[index];
        final sourceTid = _extractTid(link.url) ?? fallbackSourceTid;
        final episodeId = '$comicId:$sourceTid';

        final existing = await txn.query(
          ComicLocalDb.episodesTable,
          columns: <String>['episode_id'],
          where: 'episode_id = ?',
          whereArgs: <Object>[episodeId],
          limit: 1,
        );

        final record = EpisodeRecord(
          episodeId: episodeId,
          comicId: comicId,
          episodeTitle: _resolveEpisodeTitle(link),
          sourceTid: sourceTid,
          sourceUrl: link.url,
          orderIndex: index,
          publishTimeText: null,
        );

        await txn.insert(
          ComicLocalDb.episodesTable,
          record.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        if (existing.isEmpty) {
          inserted++;
        } else {
          updated++;
        }
      }

      await txn.update(
        ComicLocalDb.comicsTable,
        <String, Object?>{
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'comic_id = ?',
        whereArgs: <Object>[comicId],
      );
    });

    final totalEpisodes = await getComicEpisodes(comicId: comicId, descending: false);
    return ComicEpisodeRefreshResult(
      insertedCount: inserted,
      updatedCount: updated,
      totalCount: totalEpisodes.length,
    );
  }

  Future<int> _nextSortOrder(Transaction txn, {required String categoryId}) async {
    final countResult = await txn.rawQuery(
      'SELECT COUNT(*) AS count FROM ${ComicLocalDb.shelfItemsTable} WHERE category_id = ?',
      <Object>[categoryId],
    );
    return (countResult.first['count'] as int?) ?? 0;
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
            createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
          ),
        )
        .toList(growable: false);
  }

  LibraryWorkItem _rowToLibraryWorkItem(Map<String, Object?> row) {
    final customSource = _normalizeNullable(row['custom_cover_image_url'] as String?);
    final customLocal = _normalizeNullable(row['custom_cover_local_path'] as String?);
    final hasPendingCustomCover = customSource != null && customLocal == null;
    final unreadCount = row['unread_count'] as int? ?? 0;
    final readCount = row['read_count'] as int? ?? 0;
    return LibraryWorkItem(
      workId: row['comic_id'] as String,
      categoryId: row['category_id'] as String,
      title: row['title'] as String,
      secondaryName: row['author'] as String?,
      coverImageUrl: row['cover_image_url'] as String?,
      customCoverImageUrl: customSource,
      // 自定义封面有远程源但还没缓存时，不暴露旧普通本地封面，避免 UI 闪回旧图。
      coverLocalPath: hasPendingCustomCover ? null : row['cover_local_path'] as String?,
      customCoverLocalPath: customLocal,
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

  int _normalizeColumnCount(int value) {
    if (value < 2) {
      return 2;
    }
    if (value > 4) {
      return 4;
    }
    return value;
  }

  String? _extractTid(String url) {
    final threadMatch = RegExp(r'thread-(\d+)-\d+-\d+\.html', caseSensitive: false).firstMatch(url);
    if (threadMatch != null) {
      return threadMatch.group(1);
    }

    final viewthreadMatch = RegExp(
      r'forum\.php\?[^#]*\bmod=viewthread\b[^#]*\btid=(\d+)',
      caseSensitive: false,
    ).firstMatch(url);
    if (viewthreadMatch != null) {
      return viewthreadMatch.group(1);
    }

    final damagedTidMatch = RegExp(r'(^|[?&;])tid=(\d+)(?:[&#]|$)', caseSensitive: false).firstMatch(url);
    return damagedTidMatch?.group(2);
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

  String? _buildEpisodeImageCacheKey({
    required String episodeId,
    required int imageIndex,
  }) {
    final comicId = _extractComicIdFromEpisodeId(episodeId);
    if (comicId == null) {
      return null;
    }
    return ImageCacheKeys.comicPage(
      comicId: comicId,
      episodeId: episodeId,
      imageIndex: imageIndex,
    );
  }

  String? _extractComicIdFromEpisodeId(String episodeId) {
    final lastColon = episodeId.lastIndexOf(':');
    if (lastColon <= 0) {
      return null;
    }
    return episodeId.substring(0, lastColon);
  }

  Future<void> _promoteFirstEpisodeCoverIfNeeded(
    Transaction txn, {
    required String episodeId,
    required List<String> imageUrls,
  }) async {
    if (imageUrls.isEmpty) {
      return;
    }
    final comicId = _extractComicIdFromEpisodeId(episodeId);
    if (comicId == null) {
      return;
    }

    final comics = await txn.query(
      ComicLocalDb.comicsTable,
      columns: const <String>[
        'cover_image_url',
        'cover_local_path',
        'custom_cover_image_url',
        'custom_cover_local_path',
      ],
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
      limit: 1,
    );
    if (comics.isEmpty) {
      return;
    }
    final customCover = _normalizeNullable(comics.first['custom_cover_image_url'] as String?);
    final customCoverLocalPath = _normalizeNullable(comics.first['custom_cover_local_path'] as String?);
    if (customCover != null || customCoverLocalPath != null) {
      return;
    }

    final episodes = await txn.query(
      ComicLocalDb.episodesTable,
      columns: const <String>['episode_id', 'source_tid', 'order_index'],
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
    if (episodes.isEmpty) {
      return;
    }
    // sqflite 的查询结果在部分实现中是只读列表；排序前复制成普通 List，
    // 避免 ListBase.sort 交换元素时触发 Unsupported operation: read-only。
    final orderedEpisodes = episodes.toList(growable: true)
      ..sort(_compareEpisodeRowsByFirstTid);
    if (orderedEpisodes.first['episode_id'] != episodeId) {
      return;
    }

    final currentCover = _normalizeNullable(comics.first['cover_image_url'] as String?);
    if (currentCover == imageUrls.first) {
      return;
    }

    // 允许“首楼图片”纠正为真实首话首图；但用户自定义封面拥有最高优先级，
    // 读图流程不应覆盖 custom_cover_* 字段。
    await txn.update(
      ComicLocalDb.comicsTable,
      <String, Object?>{
        'cover_image_url': imageUrls.first,
        'cover_local_path': null,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
  }

  int _compareEpisodeRowsByFirstTid(Map<String, Object?> a, Map<String, Object?> b) {
    final aTid = int.tryParse((a['source_tid'] as String? ?? '').trim());
    final bTid = int.tryParse((b['source_tid'] as String? ?? '').trim());
    if (aTid != null && bTid != null && aTid != bTid) {
      return aTid.compareTo(bTid);
    }
    if (aTid != null && bTid == null) {
      return -1;
    }
    if (aTid == null && bTid != null) {
      return 1;
    }
    final order = (a['order_index'] as int? ?? 0).compareTo(b['order_index'] as int? ?? 0);
    if (order != 0) {
      return order;
    }
    return (a['episode_id'] as String? ?? '').compareTo(b['episode_id'] as String? ?? '');
  }

  String _resolveComicTitle({
    required String rawTitle,
    required ParsedComicPost parsedPost,
  }) {
    final normalized = parsedPost.subjectMetadata?.normalizedTitle.trim();
    if (normalized != null && normalized.isNotEmpty) {
      return normalized;
    }
    final fallback = rawTitle.trim();
    return fallback.isEmpty ? '未命名漫画' : fallback;
  }

  String? _resolveComicAuthor(ParsedComicPost parsedPost) {
    final fromSubject = parsedPost.subjectMetadata?.inferredAuthor?.trim();
    if (fromSubject != null && fromSubject.isNotEmpty) {
      return fromSubject;
    }
    final fromContent = parsedPost.inferredAuthor?.trim();
    if (fromContent != null && fromContent.isNotEmpty) {
      return fromContent;
    }
    return null;
  }

  String _resolveEpisodeTitle(ComicEpisodeLink link) {
    final preferred = (link.episodeTitle ?? link.rawText).trim();
    if (preferred.isEmpty) {
      return link.rawText.trim();
    }

    // Keep explicit short labels from parser/rules untouched.
    if (!_shouldNormalizeBySubjectParsing(preferred)) {
      return preferred;
    }

    final parsed = _subjectParser.parse(preferred);
    final episodeLabel = parsed.episodeLabel?.trim();
    if (episodeLabel != null && episodeLabel.isNotEmpty) {
      return episodeLabel;
    }
    return preferred;
  }

  bool _shouldNormalizeBySubjectParsing(String text) {
    if (text.length < 16) {
      return false;
    }
    final hasBracketGroup = (text.contains('【') && text.contains('】')) || (text.contains('[') && text.contains(']'));
    final hasEpisodeHint = text.contains('第') && text.contains('话');
    return hasBracketGroup || hasEpisodeHint;
  }
}


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
        ComicFirstEpisodeCoverWriter,
        ComicDuplicateMergeRepository,
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
        'custom_cover_source_episode_id': null,
        'custom_cover_source_image_index': null,
        'custom_cover_source_image_url': null,
        'metadata_updated_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
  }

  @override
  Future<void> updateCustomCoverFromLocalFile({
    required String comicId,
    required String localCoverPath,
    String? sourceEpisodeId,
    int? sourceImageIndex,
    String? sourceImageUrl,
  }) async {
    final normalizedPath = _normalizeNullable(localCoverPath);
    if (normalizedPath == null) {
      throw ArgumentError('自定义封面本地路径不能为空');
    }

    final db = await _dbFuture;
    await db.update(
      ComicLocalDb.comicsTable,
      <String, Object?>{
        // custom_cover_image_url 只作为来源追踪/远程兜底；主展示路径是本地保护封面。
        'custom_cover_image_url': _normalizeNullable(sourceImageUrl),
        'custom_cover_local_path': normalizedPath,
        'custom_cover_source_episode_id': _normalizeNullable(sourceEpisodeId),
        'custom_cover_source_image_index': sourceImageIndex,
        'custom_cover_source_image_url': _normalizeNullable(sourceImageUrl),
        'metadata_updated_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
  }

  @override
  Future<void> updateCustomMetadata({
    required String comicId,
    String? customTitle,
    String? customAuthor,
    String? customTranslationGroup,
    String? customSearchTitle,
  }) async {
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final rows = await txn.query(
        ComicLocalDb.comicsTable,
        columns: const <String>[
          'source_title',
          'title',
          'source_author',
          'author',
          'source_translation_group',
          'translation_group',
        ],
        where: 'comic_id = ?',
        whereArgs: <Object>[comicId],
        limit: 1,
      );
      if (rows.isEmpty) {
        return;
      }
      final row = rows.first;
      final normalizedTitle = _normalizeNullable(customTitle);
      final normalizedAuthor = _normalizeNullable(customAuthor);
      final normalizedGroup = _normalizeNullable(customTranslationGroup);
      await txn.update(
        ComicLocalDb.comicsTable,
        <String, Object?>{
          'custom_title': normalizedTitle,
          'custom_author': normalizedAuthor,
          'custom_translation_group': normalizedGroup,
          'custom_search_title': _normalizeNullable(customSearchTitle),
          'title': _displayString(
            customValue: normalizedTitle,
            sourceValue: row['source_title'] as String?,
            fallbackValue: row['title'] as String?,
            emptyFallback: '未命名漫画',
          ),
          'author': _displayNullable(
            customValue: normalizedAuthor,
            sourceValue: row['source_author'] as String?,
            fallbackValue: row['author'] as String?,
          ),
          'translation_group': _displayNullable(
            customValue: normalizedGroup,
            sourceValue: row['source_translation_group'] as String?,
            fallbackValue: row['translation_group'] as String?,
          ),
          'metadata_updated_at': now,
          'updated_at': now,
        },
        where: 'comic_id = ?',
        whereArgs: <Object>[comicId],
      );
    });
  }

  @override
  Future<void> clearCustomMetadata({
    required String comicId,
    bool title = false,
    bool author = false,
    bool translationGroup = false,
    bool searchTitle = false,
  }) async {
    if (!title && !author && !translationGroup && !searchTitle) {
      return;
    }

    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final rows = await txn.query(
        ComicLocalDb.comicsTable,
        columns: const <String>[
          'source_title',
          'title',
          'custom_title',
          'source_author',
          'author',
          'custom_author',
          'source_translation_group',
          'translation_group',
          'custom_translation_group',
        ],
        where: 'comic_id = ?',
        whereArgs: <Object>[comicId],
        limit: 1,
      );
      if (rows.isEmpty) {
        return;
      }
      final row = rows.first;
      final nextCustomTitle = title ? null : _normalizeNullable(row['custom_title'] as String?);
      final nextCustomAuthor = author ? null : _normalizeNullable(row['custom_author'] as String?);
      final nextCustomGroup = translationGroup
          ? null
          : _normalizeNullable(row['custom_translation_group'] as String?);
      final values = <String, Object?>{
        if (title) 'custom_title': null,
        if (author) 'custom_author': null,
        if (translationGroup) 'custom_translation_group': null,
        if (searchTitle) 'custom_search_title': null,
        'title': _displayString(
          customValue: nextCustomTitle,
          sourceValue: row['source_title'] as String?,
          fallbackValue: row['title'] as String?,
          emptyFallback: '未命名漫画',
        ),
        'author': _displayNullable(
          customValue: nextCustomAuthor,
          sourceValue: row['source_author'] as String?,
          fallbackValue: row['author'] as String?,
        ),
        'translation_group': _displayNullable(
          customValue: nextCustomGroup,
          sourceValue: row['source_translation_group'] as String?,
          fallbackValue: row['translation_group'] as String?,
        ),
        'metadata_updated_at': now,
        'updated_at': now,
      };
      await txn.update(
        ComicLocalDb.comicsTable,
        values,
        where: 'comic_id = ?',
        whereArgs: <Object>[comicId],
      );
    });
  }

  @override
  Future<void> updateCoverCache({
    required String comicId,
    String? coverImageUrl,
    String? coverLocalPath,
    String? customCoverLocalPath,
  }) async {
    final db = await _dbFuture;
    final now = DateTime.now().millisecondsSinceEpoch;
    final values = <String, Object?>{
      'updated_at': now,
    };
    if (coverImageUrl != null) {
      values['cover_image_url'] = _normalizeNullable(coverImageUrl);
    }
    if (coverLocalPath != null) {
      values['cover_local_path'] = _normalizeNullable(coverLocalPath);
    }
    if (customCoverLocalPath != null) {
      values['custom_cover_local_path'] = _normalizeNullable(customCoverLocalPath);
      values['metadata_updated_at'] = now;
    }
    await db.update(
      ComicLocalDb.comicsTable,
      values,
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
  }

  @override
  Future<bool> promoteFirstEpisodeCover({
    required String comicId,
    required String episodeId,
    required String imageUrl,
  }) async {
    final db = await _dbFuture;
    return db.transaction<bool>((txn) {
      return _promoteFirstEpisodeCoverInTransaction(
        txn,
        comicId: comicId,
        episodeId: episodeId,
        imageUrl: imageUrl,
      );
    });
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
      final existingRows = await txn.query(
        ComicLocalDb.comicsTable,
        where: 'comic_id = ?',
        whereArgs: <Object>[comicId],
        limit: 1,
      );
      final existing = existingRows.isEmpty ? null : ComicRecord.fromMap(existingRows.first);
      final sourceTitle = _resolveComicTitle(rawTitle: title, parsedPost: parsedPost);
      final sourceAuthor = _resolveComicAuthor(parsedPost);
      final sourceGroup = _normalizeNullable(parsedPost.subjectMetadata?.translationGroup);
      final customTitle = _normalizeNullable(existing?.customTitle);
      final customAuthor = _normalizeNullable(existing?.customAuthor);
      final customGroup = _normalizeNullable(existing?.customTranslationGroup);
      final comic = ComicRecord(
        comicId: comicId,
        sourceTid: tid,
        sourceFid: fid,
        sourceTypeId: _normalizeNullable(sourceTypeId),
        sourceTagName: _normalizeNullable(sourceTagName),
        title: _displayString(
          customValue: customTitle,
          sourceValue: sourceTitle,
          fallbackValue: existing?.title,
          emptyFallback: '未命名漫画',
        ),
        sourceTitle: sourceTitle,
        customTitle: customTitle,
        author: _displayNullable(
          customValue: customAuthor,
          sourceValue: sourceAuthor,
          fallbackValue: existing?.author,
        ),
        sourceAuthor: sourceAuthor,
        customAuthor: customAuthor,
        translationGroup: _displayNullable(
          customValue: customGroup,
          sourceValue: sourceGroup,
          fallbackValue: existing?.translationGroup,
        ),
        sourceTranslationGroup: sourceGroup,
        customTranslationGroup: customGroup,
        customSearchTitle: _normalizeNullable(existing?.customSearchTitle),
        coverImageUrl: parsedPost.imageUrls.isEmpty ? existing?.coverImageUrl : parsedPost.imageUrls.first,
        customCoverImageUrl: existing?.customCoverImageUrl,
        coverLocalPath: parsedPost.imageUrls.isEmpty ? existing?.coverLocalPath : null,
        customCoverLocalPath: existing?.customCoverLocalPath,
        customCoverSourceEpisodeId: existing?.customCoverSourceEpisodeId,
        customCoverSourceImageIndex: existing?.customCoverSourceImageIndex,
        customCoverSourceImageUrl: existing?.customCoverSourceImageUrl,
        metadataUpdatedAt: existing?.metadataUpdatedAt,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        lastReadEpisodeId: existing?.lastReadEpisodeId,
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

      final existingShelfRows = await txn.query(
        ComicLocalDb.shelfItemsTable,
        columns: <String>['id'],
        where: 'category_id = ? AND comic_id = ?',
        whereArgs: <Object>[_defaultCategoryId, comicId],
        limit: 1,
      );

      if (existingShelfRows.isEmpty) {
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
        c.custom_cover_source_episode_id,
        c.custom_cover_source_image_index,
        c.custom_cover_source_image_url,
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
      customCoverSourceEpisodeId: row['custom_cover_source_episode_id'] as String?,
      customCoverSourceImageIndex: row['custom_cover_source_image_index'] as int?,
      customCoverSourceImageUrl: row['custom_cover_source_image_url'] as String?,
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
            width: row['width'] as int?,
            height: row['height'] as int?,
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
        if (cacheStatus == 'failed' && cacheLocalPath == null) 'local_path': null,
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
    int? width,
    int? height,
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
    if (width != null && width > 0) {
      values['width'] = width;
    }
    if (height != null && height > 0) {
      values['height'] = height;
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

  @override
  Future<List<ComicDuplicateGroup>> findDuplicateGroups({
    String? comicId,
  }) async {
    final db = await _dbFuture;
    final normalizedComicId = _normalizeNullable(comicId);
    final rows = await db.rawQuery(
      '''
      SELECT comic_id, source_tid
      FROM ${ComicLocalDb.episodesTable}
      UNION ALL
      SELECT comic_id, source_tid
      FROM ${ComicLocalDb.comicsTable}
      ''',
    );
    if (rows.isEmpty) {
      return const <ComicDuplicateGroup>[];
    }

    final comicIdsByTid = <String, Set<String>>{};
    final tidsByComicId = <String, Set<String>>{};
    for (final row in rows) {
      final rowComicId = _normalizeNullable(row['comic_id'] as String?);
      final sourceTid = _normalizeNullable(row['source_tid'] as String?);
      if (rowComicId == null || sourceTid == null) {
        continue;
      }
      comicIdsByTid.putIfAbsent(sourceTid, () => <String>{}).add(rowComicId);
      tidsByComicId.putIfAbsent(rowComicId, () => <String>{}).add(sourceTid);
    }

    final candidateComicIds =
        normalizedComicId == null ? tidsByComicId.keys.toSet() : <String>{normalizedComicId};
    final visited = <String>{};
    final groups = <ComicDuplicateGroup>[];
    for (final startComicId in candidateComicIds) {
      if (!tidsByComicId.containsKey(startComicId) || visited.contains(startComicId)) {
        continue;
      }
      final groupComicIds = <String>{};
      final groupTids = <String>{};
      final queue = <String>[startComicId];
      visited.add(startComicId);
      while (queue.isNotEmpty) {
        final current = queue.removeLast();
        groupComicIds.add(current);
        for (final tid in tidsByComicId[current] ?? const <String>{}) {
          groupTids.add(tid);
          for (final neighbor in comicIdsByTid[tid] ?? const <String>{}) {
            if (visited.add(neighbor)) {
              queue.add(neighbor);
            }
          }
        }
      }
      if (groupComicIds.length > 1) {
        groups.add(
          ComicDuplicateGroup(
            comicIds: Set<String>.unmodifiable(groupComicIds),
            sharedTids: Set<String>.unmodifiable(
              groupTids.where((tid) => (comicIdsByTid[tid]?.length ?? 0) > 1),
            ),
          ),
        );
      }
    }
    return groups;
  }

  @override
  Future<ComicDuplicateMergeResult> mergeDuplicateGroup({
    required Set<String> comicIds,
  }) async {
    final normalizedIds = comicIds
        .map(_normalizeNullable)
        .whereType<String>()
        .toSet();
    if (normalizedIds.length <= 1) {
      return ComicDuplicateMergeResult.unchanged(
        targetComicId: normalizedIds.isEmpty ? '' : normalizedIds.first,
      );
    }

    final db = await _dbFuture;
    return db.transaction<ComicDuplicateMergeResult>((txn) async {
      final comics = await _loadComicRecords(txn, normalizedIds);
      if (comics.length <= 1) {
        return ComicDuplicateMergeResult.unchanged(
          targetComicId: comics.isEmpty ? normalizedIds.first : comics.first.comicId,
        );
      }

      final target = _chooseDuplicateMergeTarget(comics);
      final sourceIds = comics
          .map((comic) => comic.comicId)
          .where((id) => id != target.comicId)
          .toSet();
      var movedEpisodeCount = 0;
      for (final sourceComicId in sourceIds) {
        movedEpisodeCount += await _mergeSourceComicIntoTarget(
          txn,
          sourceComicId: sourceComicId,
          targetComicId: target.comicId,
        );
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      await _updateMergedComicMetadata(
        txn,
        target: target,
        sources: comics.where((comic) => sourceIds.contains(comic.comicId)).toList(growable: false),
        now: now,
      );
      await _updateMergedComicEpisodeOrder(txn, comicId: target.comicId);
      await _moveShelfRowsToTarget(
        txn,
        sourceComicIds: sourceIds,
        targetComicId: target.comicId,
      );
      await _moveExternalComicReferencesToTarget(
        txn,
        sourceComicIds: sourceIds,
        targetComicId: target.comicId,
      );
      await txn.delete(
        ComicLocalDb.comicsTable,
        where: _whereIn('comic_id', sourceIds.length),
        whereArgs: sourceIds.toList(growable: false),
      );

      return ComicDuplicateMergeResult(
        targetComicId: target.comicId,
        targetTitle: _shortestDisplayTitle(comics),
        mergedComicIds: Set<String>.unmodifiable(sourceIds),
        replacements: Map<String, String>.unmodifiable({
          for (final sourceComicId in sourceIds) sourceComicId: target.comicId,
        }),
        movedEpisodeCount: movedEpisodeCount,
      );
    });
  }

  Future<int> _nextSortOrder(Transaction txn, {required String categoryId}) async {
    final countResult = await txn.rawQuery(
      'SELECT COUNT(*) AS count FROM ${ComicLocalDb.shelfItemsTable} WHERE category_id = ?',
      <Object>[categoryId],
    );
    return (countResult.first['count'] as int?) ?? 0;
  }

  Future<List<ComicRecord>> _loadComicRecords(
    Transaction txn,
    Set<String> comicIds,
  ) async {
    if (comicIds.isEmpty) {
      return const <ComicRecord>[];
    }
    final rows = await txn.query(
      ComicLocalDb.comicsTable,
      where: _whereIn('comic_id', comicIds.length),
      whereArgs: comicIds.toList(growable: false),
    );
    return rows.map(ComicRecord.fromMap).toList(growable: false);
  }

  ComicRecord _chooseDuplicateMergeTarget(List<ComicRecord> comics) {
    final sorted = comics.toList(growable: false)
      ..sort((a, b) {
        final titleOrder = _titleLength(a.title).compareTo(_titleLength(b.title));
        if (titleOrder != 0) {
          return titleOrder;
        }
        final createdOrder = a.createdAt.compareTo(b.createdAt);
        if (createdOrder != 0) {
          return createdOrder;
        }
        return a.comicId.compareTo(b.comicId);
      });
    return sorted.first;
  }

  String _shortestDisplayTitle(List<ComicRecord> comics) {
    return _chooseDuplicateMergeTarget(comics).title;
  }

  int _titleLength(String title) {
    final trimmed = title.trim();
    return trimmed.isEmpty ? 1 << 30 : trimmed.runes.length;
  }

  Future<int> _mergeSourceComicIntoTarget(
    Transaction txn, {
    required String sourceComicId,
    required String targetComicId,
  }) async {
    final sourceEpisodes = await txn.query(
      ComicLocalDb.episodesTable,
      where: 'comic_id = ?',
      whereArgs: <Object>[sourceComicId],
      orderBy: 'order_index ASC, episode_id ASC',
    );
    var moved = 0;
    for (final row in sourceEpisodes) {
      final sourceEpisodeId = row['episode_id'] as String;
      final sourceTid = row['source_tid'] as String;
      final targetEpisodeId = '$targetComicId:$sourceTid';
      final existingRows = await txn.query(
        ComicLocalDb.episodesTable,
        where: 'episode_id = ?',
        whereArgs: <Object>[targetEpisodeId],
        limit: 1,
      );

      if (existingRows.isEmpty) {
        await txn.insert(
          ComicLocalDb.episodesTable,
          <String, Object?>{
            ...row,
            'episode_id': targetEpisodeId,
            'comic_id': targetComicId,
          },
        );
        await _mergeEpisodeStateIntoTarget(
          txn,
          sourceEpisodeId: sourceEpisodeId,
          targetEpisodeId: targetEpisodeId,
          targetComicId: targetComicId,
        );
        await _moveEpisodeChildrenToTarget(
          txn,
          sourceEpisodeId: sourceEpisodeId,
          targetEpisodeId: targetEpisodeId,
          targetComicId: targetComicId,
          moveEpisodeState: false,
        );
        await txn.delete(
          ComicLocalDb.episodesTable,
          where: 'episode_id = ?',
          whereArgs: <Object>[sourceEpisodeId],
        );
        moved++;
      } else {
        await _preferEpisodeMetadata(
          txn,
          existing: existingRows.first,
          incoming: row,
        );
        await _mergeEpisodeStateIntoTarget(
          txn,
          sourceEpisodeId: sourceEpisodeId,
          targetEpisodeId: targetEpisodeId,
          targetComicId: targetComicId,
        );
        await _moveEpisodeChildrenToTarget(
          txn,
          sourceEpisodeId: sourceEpisodeId,
          targetEpisodeId: targetEpisodeId,
          targetComicId: targetComicId,
          moveEpisodeState: false,
        );
        await txn.delete(
          ComicLocalDb.episodesTable,
          where: 'episode_id = ?',
          whereArgs: <Object>[sourceEpisodeId],
        );
      }
    }
    return moved;
  }

  Future<void> _preferEpisodeMetadata(
    Transaction txn, {
    required Map<String, Object?> existing,
    required Map<String, Object?> incoming,
  }) async {
    final existingTitle = _normalizeNullable(existing['episode_title'] as String?);
    final incomingTitle = _normalizeNullable(incoming['episode_title'] as String?);
    final existingUrl = _normalizeNullable(existing['source_url'] as String?);
    final incomingUrl = _normalizeNullable(incoming['source_url'] as String?);
    final update = <String, Object?>{};
    if (incomingTitle != null &&
        (existingTitle == null || incomingTitle.length > existingTitle.length)) {
      update['episode_title'] = incomingTitle;
    }
    if (incomingUrl != null && (existingUrl == null || existingUrl.isEmpty)) {
      update['source_url'] = incomingUrl;
    }
    final publishTimeText = _normalizeNullable(existing['publish_time_text'] as String?) ??
        _normalizeNullable(incoming['publish_time_text'] as String?);
    if (publishTimeText != null) {
      update['publish_time_text'] = publishTimeText;
    }
    if (update.isEmpty) {
      return;
    }
    await txn.update(
      ComicLocalDb.episodesTable,
      update,
      where: 'episode_id = ?',
      whereArgs: <Object>[existing['episode_id'] as String],
    );
  }

  Future<void> _moveEpisodeChildrenToTarget(
    Transaction txn, {
    required String sourceEpisodeId,
    required String targetEpisodeId,
    required String targetComicId,
    bool moveEpisodeState = true,
  }) async {
    await txn.update(
      ComicLocalDb.episodeImagesTable,
      <String, Object?>{
        'episode_id': targetEpisodeId,
        // Keep logical cache keys aligned with the surviving comic id so future
        // cache writes do not fork metadata under the removed source comic.
        'stable_cache_key': null,
      },
      where: 'episode_id = ?',
      whereArgs: <Object>[sourceEpisodeId],
    );
    await txn.update(
      ComicLocalDb.readingProgressTable,
      <String, Object?>{'episode_id': targetEpisodeId},
      where: 'episode_id = ?',
      whereArgs: <Object>[sourceEpisodeId],
    );
    await txn.update(
      ComicLocalDb.comicsTable,
      <String, Object?>{'last_read_episode_id': targetEpisodeId},
      where: 'last_read_episode_id = ?',
      whereArgs: <Object>[sourceEpisodeId],
    );
    await txn.update(
      ComicLocalDb.libraryWorkStateTable,
      <String, Object?>{'last_read_episode_id': targetEpisodeId},
      where: 'content_type = ? AND last_read_episode_id = ?',
      whereArgs: <Object>['comic', sourceEpisodeId],
    );
    if (!moveEpisodeState) {
      return;
    }
    await txn.update(
      ComicLocalDb.libraryEpisodeStateTable,
      <String, Object?>{
        'episode_id': targetEpisodeId,
        'work_id': targetComicId,
      },
      where: 'content_type = ? AND episode_id = ?',
      whereArgs: <Object>['comic', sourceEpisodeId],
    );
  }

  Future<void> _mergeEpisodeStateIntoTarget(
    Transaction txn, {
    required String sourceEpisodeId,
    required String targetEpisodeId,
    required String targetComicId,
  }) async {
    final sourceRows = await txn.query(
      ComicLocalDb.libraryEpisodeStateTable,
      where: 'content_type = ? AND episode_id = ?',
      whereArgs: <Object>['comic', sourceEpisodeId],
      limit: 1,
    );
    if (sourceRows.isEmpty) {
      return;
    }
    final source = sourceRows.first;
    final targetRows = await txn.query(
      ComicLocalDb.libraryEpisodeStateTable,
      where: 'content_type = ? AND episode_id = ?',
      whereArgs: <Object>['comic', targetEpisodeId],
      limit: 1,
    );
    if (targetRows.isEmpty) {
      await txn.update(
        ComicLocalDb.libraryEpisodeStateTable,
        <String, Object?>{
          'episode_id': targetEpisodeId,
          'work_id': targetComicId,
        },
        where: 'content_type = ? AND episode_id = ?',
        whereArgs: <Object>['comic', sourceEpisodeId],
      );
      return;
    }

    final target = targetRows.first;
    await txn.update(
      ComicLocalDb.libraryEpisodeStateTable,
      <String, Object?>{
        'work_id': targetComicId,
        'is_read': _maxInt(target['is_read'], source['is_read']),
        'is_downloaded': _maxInt(target['is_downloaded'], source['is_downloaded']),
        'is_bookmarked': _maxInt(target['is_bookmarked'], source['is_bookmarked']),
        'read_at': _maxNullableInt(target['read_at'], source['read_at']),
        'downloaded_at': _maxNullableInt(
          target['downloaded_at'],
          source['downloaded_at'],
        ),
      },
      where: 'content_type = ? AND episode_id = ?',
      whereArgs: <Object>['comic', targetEpisodeId],
    );
    await txn.delete(
      ComicLocalDb.libraryEpisodeStateTable,
      where: 'content_type = ? AND episode_id = ?',
      whereArgs: <Object>['comic', sourceEpisodeId],
    );
  }

  Future<void> _updateMergedComicMetadata(
    Transaction txn, {
    required ComicRecord target,
    required List<ComicRecord> sources,
    required int now,
  }) async {
    final all = <ComicRecord>[target, ...sources];
    final shortestTitle = _shortestDisplayTitle(all);
    await txn.update(
      ComicLocalDb.comicsTable,
      <String, Object?>{
        'title': shortestTitle,
        'source_title': _firstNormalized(<String?>[
          shortestTitle,
          target.sourceTitle,
          for (final source in sources) source.sourceTitle,
        ]),
        'custom_title': null,
        'custom_search_title': _firstNormalized(<String?>[
          target.customSearchTitle,
          for (final source in sources) source.customSearchTitle,
        ]),
        'author': _firstNormalized(<String?>[
          target.author,
          for (final source in sources) source.author,
        ]),
        'source_author': _firstNormalized(<String?>[
          target.sourceAuthor,
          for (final source in sources) source.sourceAuthor,
        ]),
        'translation_group': _firstNormalized(<String?>[
          target.translationGroup,
          for (final source in sources) source.translationGroup,
        ]),
        'source_translation_group': _firstNormalized(<String?>[
          target.sourceTranslationGroup,
          for (final source in sources) source.sourceTranslationGroup,
        ]),
        'cover_image_url': _firstNormalized(<String?>[
          target.coverImageUrl,
          for (final source in sources) source.coverImageUrl,
        ]),
        'custom_cover_image_url': _firstNormalized(<String?>[
          target.customCoverImageUrl,
          for (final source in sources) source.customCoverImageUrl,
        ]),
        'cover_local_path': _firstNormalized(<String?>[
          target.coverLocalPath,
          for (final source in sources) source.coverLocalPath,
        ]),
        'custom_cover_local_path': _firstNormalized(<String?>[
          target.customCoverLocalPath,
          for (final source in sources) source.customCoverLocalPath,
        ]),
        'custom_cover_source_episode_id': _remapMergedEpisodeId(
          _firstNormalized(<String?>[
            target.customCoverSourceEpisodeId,
            for (final source in sources) source.customCoverSourceEpisodeId,
          ]),
          targetComicId: target.comicId,
        ),
        'custom_cover_source_image_index': _firstInt(<int?>[
          target.customCoverSourceImageIndex,
          for (final source in sources) source.customCoverSourceImageIndex,
        ]),
        'custom_cover_source_image_url': _firstNormalized(<String?>[
          target.customCoverSourceImageUrl,
          for (final source in sources) source.customCoverSourceImageUrl,
        ]),
        'metadata_updated_at': now,
        'updated_at': now,
      },
      where: 'comic_id = ?',
      whereArgs: <Object>[target.comicId],
    );
  }

  String? _remapMergedEpisodeId(
    String? episodeId, {
    required String targetComicId,
  }) {
    final normalized = _normalizeNullable(episodeId);
    if (normalized == null) {
      return null;
    }
    final lastColon = normalized.lastIndexOf(':');
    if (lastColon <= 0 || lastColon == normalized.length - 1) {
      return normalized;
    }
    final sourceTid = normalized.substring(lastColon + 1);
    return '$targetComicId:$sourceTid';
  }

  Future<void> _updateMergedComicEpisodeOrder(
    Transaction txn, {
    required String comicId,
  }) async {
    final rows = await txn.query(
      ComicLocalDb.episodesTable,
      columns: const <String>['episode_id', 'source_tid', 'order_index'],
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
    final ordered = rows.toList(growable: true)
      ..sort(_compareEpisodeRowsByFirstTid);
    for (var index = 0; index < ordered.length; index++) {
      await txn.update(
        ComicLocalDb.episodesTable,
        <String, Object?>{'order_index': index},
        where: 'episode_id = ?',
        whereArgs: <Object>[ordered[index]['episode_id'] as String],
      );
    }
  }

  Future<void> _moveShelfRowsToTarget(
    Transaction txn, {
    required Set<String> sourceComicIds,
    required String targetComicId,
  }) async {
    if (sourceComicIds.isEmpty) {
      return;
    }
    final rows = await txn.query(
      ComicLocalDb.shelfItemsTable,
      where: _whereIn('comic_id', sourceComicIds.length),
      whereArgs: sourceComicIds.toList(growable: false),
      orderBy: 'added_at ASC, sort_order ASC',
    );
    for (final row in rows) {
      final categoryId = row['category_id'] as String;
      final existing = await txn.query(
        ComicLocalDb.shelfItemsTable,
        columns: const <String>['id'],
        where: 'category_id = ? AND comic_id = ?',
        whereArgs: <Object>[categoryId, targetComicId],
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert(
          ComicLocalDb.shelfItemsTable,
          <String, Object?>{
            'category_id': categoryId,
            'comic_id': targetComicId,
            'added_at': row['added_at'],
            'sort_order': row['sort_order'],
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }
    await txn.delete(
      ComicLocalDb.shelfItemsTable,
      where: _whereIn('comic_id', sourceComicIds.length),
      whereArgs: sourceComicIds.toList(growable: false),
    );
  }

  Future<void> _moveExternalComicReferencesToTarget(
    Transaction txn, {
    required Set<String> sourceComicIds,
    required String targetComicId,
  }) async {
    if (sourceComicIds.isEmpty) {
      return;
    }
    final args = sourceComicIds.toList(growable: false);
    final where = _whereIn('work_id', sourceComicIds.length);
    await _mergeWorkStateRowsToTarget(
      txn,
      sourceComicIds: sourceComicIds,
      targetComicId: targetComicId,
    );
    await _mergeWorkTagsToTarget(
      txn,
      sourceComicIds: sourceComicIds,
      targetComicId: targetComicId,
    );
    await txn.update(
      ComicLocalDb.favoriteThreadsTable,
      <String, Object?>{'work_id': targetComicId},
      where: where,
      whereArgs: args,
    );
    await _mergeCachedImagesToTarget(
      txn,
      sourceComicIds: sourceComicIds,
      targetComicId: targetComicId,
    );
    await txn.update(
      ComicLocalDb.comicSearchRefreshQueueTable,
      <String, Object?>{'comic_id': targetComicId},
      where: _whereIn('comic_id', sourceComicIds.length),
      whereArgs: args,
    );
    await _mergeReadingProgressToTarget(
      txn,
      sourceComicIds: sourceComicIds,
      targetComicId: targetComicId,
    );
  }

  Future<void> _mergeCachedImagesToTarget(
    Transaction txn, {
    required Set<String> sourceComicIds,
    required String targetComicId,
  }) async {
    final args = sourceComicIds.toList(growable: false);
    await txn.update(
      ComicLocalDb.cachedImagesTable,
      <String, Object?>{'owner_id': targetComicId},
      where: 'owner_type = ? AND ${_whereIn('owner_id', args.length)}',
      whereArgs: <Object>['comic', ...args],
    );
  }

  Future<void> _mergeWorkStateRowsToTarget(
    Transaction txn, {
    required Set<String> sourceComicIds,
    required String targetComicId,
  }) async {
    final args = sourceComicIds.toList(growable: false);
    final rows = await txn.query(
      ComicLocalDb.libraryWorkStateTable,
      where: 'content_type = ? AND ${_whereIn('work_id', args.length + 1)}',
      whereArgs: <Object>['comic', targetComicId, ...args],
    );
    if (rows.isEmpty) {
      return;
    }

    Map<String, Object?>? target;
    for (final row in rows) {
      if (row['work_id'] == targetComicId) {
        target = row;
        break;
      }
    }
    target ??= <String, Object?>{
      'content_type': 'comic',
      'work_id': targetComicId,
      'created_at': rows.map((row) => row['created_at']).whereType<int>().fold<int>(
            DateTime.now().millisecondsSinceEpoch,
            (minValue, value) => value < minValue ? value : minValue,
          ),
      'updated_at': 0,
    };
    final Map<String, Object?> targetRow = target;

    String? pickFirst(String column) {
      final value = _firstObject(<Object?>[
        targetRow[column],
        for (final row in rows)
          if (row['work_id'] != targetComicId) row[column],
      ]);
      return value is String ? _normalizeNullable(value) : null;
    }

    int? pickLatest(String column) {
      Object? latest = targetRow[column];
      for (final row in rows) {
        if (row['work_id'] == targetComicId) {
          continue;
        }
        latest = _maxNullableInt(latest, row[column]);
      }
      return latest is int ? latest : null;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await txn.insert(
      ComicLocalDb.libraryWorkStateTable,
      <String, Object?>{
        'content_type': 'comic',
        'work_id': targetComicId,
        'last_read_episode_id': pickFirst('last_read_episode_id'),
        'last_read_at': pickLatest('last_read_at'),
        'check_updated_at': pickLatest('check_updated_at'),
        'fetched_updated_at': pickLatest('fetched_updated_at'),
        'intro_text': pickFirst('intro_text'),
        'created_at': targetRow['created_at'] as int? ?? now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await txn.delete(
      ComicLocalDb.libraryWorkStateTable,
      where: 'content_type = ? AND ${_whereIn('work_id', args.length)}',
      whereArgs: <Object>['comic', ...args],
    );
  }

  Future<void> _mergeWorkTagsToTarget(
    Transaction txn, {
    required Set<String> sourceComicIds,
    required String targetComicId,
  }) async {
    final args = sourceComicIds.toList(growable: false);
    final tagRows = await txn.query(
      ComicLocalDb.libraryWorkTagsTable,
      columns: const <String>['tag_id'],
      where: 'content_type = ? AND ${_whereIn('work_id', args.length)}',
      whereArgs: <Object>['comic', ...args],
    );
    for (final row in tagRows) {
      final tagId = row['tag_id'] as String?;
      if (tagId == null || tagId.trim().isEmpty) {
        continue;
      }
      await txn.insert(
        ComicLocalDb.libraryWorkTagsTable,
        <String, Object?>{
          'content_type': 'comic',
          'work_id': targetComicId,
          'tag_id': tagId,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await txn.delete(
      ComicLocalDb.libraryWorkTagsTable,
      where: 'content_type = ? AND ${_whereIn('work_id', args.length)}',
      whereArgs: <Object>['comic', ...args],
    );
  }

  Future<void> _mergeReadingProgressToTarget(
    Transaction txn, {
    required Set<String> sourceComicIds,
    required String targetComicId,
  }) async {
    final args = sourceComicIds.toList(growable: false);
    final rows = await txn.query(
      ComicLocalDb.readingProgressTable,
      where: _whereIn('comic_id', args.length + 1),
      whereArgs: <Object>[targetComicId, ...args],
      orderBy: 'updated_at DESC',
    );
    if (rows.isEmpty) {
      return;
    }
    final winner = rows.first;
    await txn.insert(
      ComicLocalDb.readingProgressTable,
      <String, Object?>{
        ...winner,
        'comic_id': targetComicId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await txn.delete(
      ComicLocalDb.readingProgressTable,
      where: _whereIn('comic_id', args.length),
      whereArgs: args,
    );
  }

  Object? _firstObject(Iterable<Object?> values) {
    for (final value in values) {
      if (value is String && value.trim().isEmpty) {
        continue;
      }
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  int? _firstInt(Iterable<int?> values) {
    for (final value in values) {
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  int _maxInt(Object? a, Object? b) {
    final left = a is int ? a : 0;
    final right = b is int ? b : 0;
    return left > right ? left : right;
  }

  int? _maxNullableInt(Object? a, Object? b) {
    final left = a is int ? a : null;
    final right = b is int ? b : null;
    if (left == null) {
      return right;
    }
    if (right == null) {
      return left;
    }
    return left > right ? left : right;
  }

  String _whereIn(String column, int count) {
    if (count <= 0) {
      throw ArgumentError('IN condition requires at least one value');
    }
    return '$column IN (${List<String>.filled(count, '?').join(', ')})';
  }

  String? _firstNormalized(Iterable<String?> values) {
    for (final value in values) {
      final normalized = _normalizeNullable(value);
      if (normalized != null) {
        return normalized;
      }
    }
    return null;
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
      secondaryName: _shelfSecondaryName(
        author: row['author'] as String?,
        translationGroup: row['translation_group'] as String?,
      ),
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

  String _displayString({
    required String? customValue,
    required String? sourceValue,
    required String? fallbackValue,
    required String emptyFallback,
  }) {
    return _normalizeNullable(customValue) ??
        _normalizeNullable(sourceValue) ??
        _normalizeNullable(fallbackValue) ??
        emptyFallback;
  }

  String? _displayNullable({
    required String? customValue,
    required String? sourceValue,
    required String? fallbackValue,
  }) {
    return _normalizeNullable(customValue) ??
        _normalizeNullable(sourceValue) ??
        _normalizeNullable(fallbackValue);
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
    await _promoteFirstEpisodeCoverInTransaction(
      txn,
      comicId: comicId,
      episodeId: episodeId,
      imageUrl: imageUrls.first,
    );
  }

  Future<bool> _promoteFirstEpisodeCoverInTransaction(
    Transaction txn, {
    required String comicId,
    required String episodeId,
    required String imageUrl,
  }) async {
    final normalizedImageUrl = _normalizeNullable(imageUrl);
    if (normalizedImageUrl == null) {
      return false;
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
      return false;
    }
    final customCover = _normalizeNullable(comics.first['custom_cover_image_url'] as String?);
    final customCoverLocalPath = _normalizeNullable(comics.first['custom_cover_local_path'] as String?);
    if (customCover != null || customCoverLocalPath != null) {
      return false;
    }

    final episodes = await txn.query(
      ComicLocalDb.episodesTable,
      columns: const <String>['episode_id', 'source_tid', 'order_index'],
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
    if (episodes.isEmpty) {
      return false;
    }
    // sqflite 的查询结果在部分实现中是只读列表；排序前复制成普通 List，
    // 避免 ListBase.sort 交换元素时触发 Unsupported operation: read-only。
    final orderedEpisodes = episodes.toList(growable: true)
      ..sort(_compareEpisodeRowsByFirstTid);
    if (orderedEpisodes.first['episode_id'] != episodeId) {
      return false;
    }

    final currentCover = _normalizeNullable(comics.first['cover_image_url'] as String?);
    final currentLocalPath = _normalizeNullable(comics.first['cover_local_path'] as String?);
    if (currentCover == normalizedImageUrl && currentLocalPath == null) {
      return false;
    }

    // 允许“首楼图片”纠正为真实首话首图；但用户自定义封面拥有最高优先级，
    // 读图流程不应覆盖 custom_cover_* 字段。
    await txn.update(
      ComicLocalDb.comicsTable,
      <String, Object?>{
        'cover_image_url': normalizedImageUrl,
        'cover_local_path': null,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
    return true;
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


import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/local/comic_local_models.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';

/// 基于 SQLite 的漫画仓库实现。
class LocalComicRepository implements ComicRepository {
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
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
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
        COALESCE(c.custom_cover_image_url, c.cover_image_url) AS cover_image_url
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
            categoryId: row['category_id'] as String,
            addedAt: DateTime.fromMillisecondsSinceEpoch(row['added_at'] as int),
          ),
        )
        .toList(growable: false);
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
          ).toMap(),
        );
      }
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


import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/local/comic_local_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';

/// 基于 SQLite 的漫画仓库实现。
class LocalComicRepository implements ComicRepository {
  LocalComicRepository(this._dbFuture);

  static const String _defaultCategoryId = 'default';

  final Future<Database> _dbFuture;

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
        title: title,
        author: parsedPost.inferredAuthor,
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
            title: row['title'] as String,
            author: row['author'] as String?,
            coverImageUrl: row['cover_image_url'] as String?,
            categoryId: row['category_id'] as String,
            addedAt: DateTime.fromMillisecondsSinceEpoch(row['added_at'] as int),
          ),
        )
        .toList(growable: false);
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
    final match = RegExp(r'thread-(\d+)-\d+-\d+\.html', caseSensitive: false).firstMatch(url);
    return match?.group(1);
  }
}


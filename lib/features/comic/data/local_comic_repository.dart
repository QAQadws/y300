import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/local/comic_local_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';

/// 基于 SQLite 的漫画仓库实现。
class LocalComicRepository implements ComicRepository {
  LocalComicRepository(this._dbFuture);

  final Future<Database> _dbFuture;

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
        whereArgs: <Object>['default', comicId],
        limit: 1,
      );

      if (existing.isEmpty) {
        final countResult = await txn.rawQuery(
          'SELECT COUNT(*) AS count FROM ${ComicLocalDb.shelfItemsTable} WHERE category_id = ?',
          <Object>['default'],
        );
        final sortOrder = (countResult.first['count'] as int?) ?? 0;

        await txn.insert(
          ComicLocalDb.shelfItemsTable,
          ShelfItemRecord(
            categoryId: 'default',
            comicId: comicId,
            addedAt: now,
            sortOrder: sortOrder,
          ).toMap(),
        );
      }
    });
  }

  @override
  Future<List<ComicShelfItem>> getShelfItems({String categoryId = 'default'}) async {
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

  String? _extractTid(String url) {
    final match = RegExp(r'thread-(\d+)-\d+-\d+\.html', caseSensitive: false).firstMatch(url);
    return match?.group(1);
  }
}

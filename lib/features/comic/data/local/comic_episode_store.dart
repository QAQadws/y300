import 'package:sqflite/sqflite.dart';
import 'package:y300/features/cache/domain/image_cache_keys.dart';
import 'package:y300/features/comic/data/local/comic_cover_store.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/local/comic_local_models.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';

class ComicEpisodeStore {
  ComicEpisodeStore(
    this._dbFuture, {
    required ComicCoverStore coverStore,
    ComicSubjectParser? subjectParser,
  })  : _coverStore = coverStore,
        _subjectParser = subjectParser ?? const RuleBasedComicSubjectParser();

  final Future<Database> _dbFuture;
  final ComicCoverStore _coverStore;
  final ComicSubjectParser _subjectParser;

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
            stableCacheKey: buildEpisodeImageCacheKey(
              episodeId: episodeId,
              imageIndex: index,
            ),
            lastSourceUrl: imageUrls[index],
          ).toMap(),
        );
      }
      final comicId = extractComicIdFromEpisodeId(episodeId);
      if (comicId != null) {
        await _coverStore.promoteFirstEpisodeCoverIfNeededInTxn(
          txn,
          comicId: comicId,
          episodeId: episodeId,
          imageUrls: imageUrls,
        );
      }
    });
  }

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
        if (cacheStatus == 'failed' && cacheLocalPath == null)
          'local_path': null,
      },
      where: 'episode_id = ? AND image_url = ?',
      whereArgs: <Object>[episodeId, imageUrl],
    );
  }

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
        final sourceTid = extractTid(link.url) ?? fallbackSourceTid;
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
          episodeTitle: resolveEpisodeTitle(link),
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

    final totalEpisodes = await getComicEpisodes(
      comicId: comicId,
      descending: false,
    );
    return ComicEpisodeRefreshResult(
      insertedCount: inserted,
      updatedCount: updated,
      totalCount: totalEpisodes.length,
    );
  }

  Future<void> upsertParsedEpisodeLinksInTxn(
    DatabaseExecutor executor, {
    required String comicId,
    required String fallbackSourceTid,
    required List<ComicEpisodeLink> episodeLinks,
  }) async {
    for (var index = 0; index < episodeLinks.length; index++) {
      final link = episodeLinks[index];
      final sourceTid = extractTid(link.url) ?? fallbackSourceTid;
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

      await executor.insert(
        ComicLocalDb.episodesTable,
        episode.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> seedFirstFloorImagesInTxn(
    DatabaseExecutor executor, {
    required String comicId,
    required String sourceTid,
    required List<String> imageUrls,
  }) async {
    if (imageUrls.isEmpty) {
      return;
    }

    final defaultEpisodeId = '$comicId:$sourceTid';
    await executor.insert(
      ComicLocalDb.episodesTable,
      EpisodeRecord(
        episodeId: defaultEpisodeId,
        comicId: comicId,
        episodeTitle: '首楼',
        sourceTid: sourceTid,
        sourceUrl: '',
        orderIndex: -1,
        publishTimeText: null,
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    for (var imageIndex = 0; imageIndex < imageUrls.length; imageIndex++) {
      final image = EpisodeImageRecord(
        episodeId: defaultEpisodeId,
        imageUrl: imageUrls[imageIndex],
        imageIndex: imageIndex,
        stableCacheKey: buildEpisodeImageCacheKey(
          episodeId: defaultEpisodeId,
          imageIndex: imageIndex,
        ),
        lastSourceUrl: imageUrls[imageIndex],
      );
      await executor.insert(
        ComicLocalDb.episodeImagesTable,
        image.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  String? extractTid(String url) {
    final threadMatch = RegExp(
      r'thread-(\d+)-\d+-\d+\.html',
      caseSensitive: false,
    ).firstMatch(url);
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

    final damagedTidMatch = RegExp(
      r'(^|[?&;])tid=(\d+)(?:[&#]|$)',
      caseSensitive: false,
    ).firstMatch(url);
    return damagedTidMatch?.group(2);
  }

  String _resolveEpisodeTitleRaw(ComicEpisodeLink link) {
    final preferred = (link.episodeTitle ?? link.rawText).trim();
    if (preferred.isEmpty) {
      return link.rawText.trim();
    }
    return preferred;
  }

  String resolveEpisodeTitle(ComicEpisodeLink link) {
    final preferred = _resolveEpisodeTitleRaw(link);
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
    final hasBracketGroup = (text.contains('【') && text.contains('】')) ||
        (text.contains('[') && text.contains(']'));
    final hasEpisodeHint = text.contains('第') && text.contains('话');
    return hasBracketGroup || hasEpisodeHint;
  }

  String? buildEpisodeImageCacheKey({
    required String episodeId,
    required int imageIndex,
  }) {
    final comicId = extractComicIdFromEpisodeId(episodeId);
    if (comicId == null) {
      return null;
    }
    return ImageCacheKeys.comicPage(
      comicId: comicId,
      episodeId: episodeId,
      imageIndex: imageIndex,
    );
  }

  String? extractComicIdFromEpisodeId(String episodeId) {
    final lastColon = episodeId.lastIndexOf(':');
    if (lastColon <= 0) {
      return null;
    }
    return episodeId.substring(0, lastColon);
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

import 'package:sqflite/sqflite.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/comic/data/local/comic_cover_store.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/local/comic_local_models.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

class ComicEpisodeStore {
  ComicEpisodeStore(
    this._dbFuture, {
    required ComicCoverStore coverStore,
    ComicSubjectParser? subjectParser,
    ForumReferenceResolver? threadUrlParser,
  }) : _coverStore = coverStore,
       _subjectParser = subjectParser ?? const RuleBasedComicSubjectParser(),
       _threadUrlParser = threadUrlParser ?? const ForumReferenceResolver();

  final Future<Database> _dbFuture;
  final ComicCoverStore _coverStore;
  final ComicSubjectParser _subjectParser;
  final ForumReferenceResolver _threadUrlParser;

  /// 读取章节列表。
  ///
  /// 默认过滤隐藏章节：隐藏语义是“对所有阅读路径都不出现”，在存储层统一
  /// 兜底比让详情页、阅读器、下载各自记得过滤更可靠。章节管理面板显式传
  /// [includeHidden] 才能看到全部章节。
  Future<List<ComicEpisodeItem>> getComicEpisodes({
    required String comicId,
    bool descending = true,
    bool includeHidden = false,
  }) async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.episodesTable,
      where: includeHidden ? 'comic_id = ?' : 'comic_id = ? AND is_hidden = 0',
      whereArgs: <Object>[comicId],
      orderBy: 'order_index ${descending ? 'DESC' : 'ASC'}',
    );

    return rows.map(_mapEpisodeRow).toList(growable: false);
  }

  ComicEpisodeItem _mapEpisodeRow(Map<String, Object?> row) {
    return ComicEpisodeItem(
      episodeId: row['episode_id'] as String,
      comicId: row['comic_id'] as String,
      episodeTitle: row['episode_title'] as String?,
      sourceEpisodeTitle: row['source_episode_title'] as String?,
      customEpisodeTitle: row['custom_episode_title'] as String?,
      sourceTid: row['source_tid'] as String,
      sourceUrl: row['source_url'] as String,
      orderIndex: row['order_index'] as int,
      publishTimeText: row['publish_time_text'] as String?,
      isManual: (row['is_manual'] as int? ?? 0) == 1,
      isHidden: (row['is_hidden'] as int? ?? 0) == 1,
    );
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

  Future<void> replaceEpisodeImages({
    required String episodeId,
    required List<String> imageUrls,
  }) async {
    final normalizedUrls = imageUrls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    final db = await _dbFuture;
    await db.transaction((txn) async {
      final existingRows = await txn.query(
        ComicLocalDb.episodeImagesTable,
        where: 'episode_id = ?',
        whereArgs: <Object>[episodeId],
        orderBy: 'image_index ASC',
      );
      final existingByIndex = <int, Map<String, Object?>>{
        for (final row in existingRows) row['image_index'] as int: row,
      };
      await txn.delete(
        ComicLocalDb.episodeImagesTable,
        where: 'episode_id = ?',
        whereArgs: <Object>[episodeId],
      );
      for (var index = 0; index < normalizedUrls.length; index++) {
        final imageUrl = normalizedUrls[index];
        final existing = existingByIndex[index];
        final sourceUnchanged =
            (existing?['image_url'] as String?)?.trim() == imageUrl;
        final preserveCacheMetadata =
            sourceUnchanged && existing?['cache_status'] != 'failed';
        final record = EpisodeImageRecord(
          episodeId: episodeId,
          imageUrl: imageUrl,
          imageIndex: index,
          stableCacheKey:
              (existing?['stable_cache_key'] as String?) ??
              buildEpisodeImageCacheKey(
                episodeId: episodeId,
                imageIndex: index,
              ),
          lastSourceUrl: preserveCacheMetadata
              ? (existing?['last_source_url'] as String? ?? imageUrl)
              : imageUrl,
          localPath: preserveCacheMetadata
              ? (existing?['local_path'] as String?)
              : null,
          width: preserveCacheMetadata ? (existing?['width'] as int?) : null,
          height: preserveCacheMetadata ? (existing?['height'] as int?) : null,
          bytes: preserveCacheMetadata ? (existing?['bytes'] as int? ?? 0) : 0,
          mimeType: preserveCacheMetadata
              ? (existing?['mime_type'] as String?)
              : null,
          lastAccessedAt: preserveCacheMetadata
              ? (existing?['last_accessed_at'] as int?)
              : null,
          protected: preserveCacheMetadata
              ? (existing?['protected'] as int? ?? 0) == 1
              : false,
          cacheLocalPath: preserveCacheMetadata
              ? (existing?['cache_local_path'] as String?)
              : null,
          cacheStatus: preserveCacheMetadata
              ? (existing?['cache_status'] as String? ?? 'none')
              : 'none',
        );
        await txn.insert(ComicLocalDb.episodeImagesTable, record.toMap());
      }
      final comicId = extractComicIdFromEpisodeId(episodeId);
      if (comicId != null) {
        await _coverStore.promoteFirstEpisodeCoverIfNeededInTxn(
          txn,
          comicId: comicId,
          episodeId: episodeId,
          imageUrls: normalizedUrls,
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

  Future<void> clearEpisodeImageCache({required String episodeId}) async {
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
      final overrides = await _loadEpisodeUserOverrides(txn, comicId);
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

        final override = overrides[episodeId];
        final record = EpisodeRecord.resolved(
          episodeId: episodeId,
          comicId: comicId,
          sourceEpisodeTitle: resolveEpisodeTitle(link),
          customEpisodeTitle: override?.customEpisodeTitle,
          sourceTid: sourceTid,
          sourceUrl: link.url,
          orderIndex: index,
          publishTimeText: null,
          // 解析命中的章节按来源归属重写为解析章节：这条链接以后每次刷新都会
          // 回来，再显示成“可移除的手动章节”只会给出移除不掉的假承诺。
          isManual: false,
          isHidden: override?.isHidden ?? false,
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
        <String, Object?>{'updated_at': DateTime.now().millisecondsSinceEpoch},
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
    final overrides = await _loadEpisodeUserOverrides(executor, comicId);
    for (var index = 0; index < episodeLinks.length; index++) {
      final link = episodeLinks[index];
      final sourceTid = extractTid(link.url) ?? fallbackSourceTid;
      final episodeId = '$comicId:$sourceTid';
      final override = overrides[episodeId];
      final episode = EpisodeRecord.resolved(
        episodeId: episodeId,
        comicId: comicId,
        sourceEpisodeTitle: link.episodeTitle ?? link.rawText,
        customEpisodeTitle: override?.customEpisodeTitle,
        sourceTid: sourceTid,
        sourceUrl: link.url,
        orderIndex: index,
        publishTimeText: null,
        isManual: false,
        isHidden: override?.isHidden ?? false,
      );

      await executor.insert(
        ComicLocalDb.episodesTable,
        episode.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// 把单帖漫画的内容图片落地到唯一一话上。
  ///
  /// 使用约束：仅在调用方已确认该帖**不存在 catalog 章节链接**时才能进入；
  /// 否则会与 [upsertParsedEpisodeLinksInTxn] 产生 orderIndex=-1 的孤儿记录。
  /// 命名策略不属于存储层职责，由调用方通过 [episodeTitle] 注入
  /// （参见 `ComicSingleThreadEpisodeNamer`）。
  Future<void> seedSingleThreadEpisodeInTxn(
    DatabaseExecutor executor, {
    required String comicId,
    required String sourceTid,
    required String episodeTitle,
    required List<String> imageUrls,
  }) async {
    if (imageUrls.isEmpty) {
      return;
    }

    final defaultEpisodeId = '$comicId:$sourceTid';
    await executor.insert(
      ComicLocalDb.episodesTable,
      EpisodeRecord.resolved(
        episodeId: defaultEpisodeId,
        comicId: comicId,
        sourceEpisodeTitle: episodeTitle,
        sourceTid: sourceTid,
        sourceUrl: '',
        orderIndex: 0,
        publishTimeText: null,
      ).toMap(),
      // 只在缺行时插入，既有行上的自定义名与隐藏状态因此不会被这里覆盖。
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

  /// 读取章节上属于用户的状态：隐藏标记与自定义章节名。
  ///
  /// 解析 upsert 用 `ConflictAlgorithm.replace` 整行覆盖，这些列会被解析结果
  /// 冲掉；刷新不应该把用户隐藏过的章节重新显示出来，也不应该把重命名改回
  /// 来源名，所以写入前先取回来再一起写进新行。
  Future<Map<String, _EpisodeUserOverrides>> _loadEpisodeUserOverrides(
    DatabaseExecutor executor,
    String comicId,
  ) async {
    final rows = await executor.query(
      ComicLocalDb.episodesTable,
      columns: <String>['episode_id', 'is_hidden', 'custom_episode_title'],
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
    return <String, _EpisodeUserOverrides>{
      for (final row in rows)
        row['episode_id'] as String: _EpisodeUserOverrides(
          isHidden: (row['is_hidden'] as int? ?? 0) == 1,
          customEpisodeTitle: row['custom_episode_title'] as String?,
        ),
    };
  }

  String? extractTid(String url) {
    final normalized = _threadUrlParser.normalizeHref(url);
    return _threadUrlParser.extractTid(normalized ?? url);
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
    final hasBracketGroup =
        (text.contains('【') && text.contains('】')) ||
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

/// 章节行上属于用户的状态，解析刷新整行覆盖时必须原样带回。
class _EpisodeUserOverrides {
  const _EpisodeUserOverrides({
    required this.isHidden,
    this.customEpisodeTitle,
  });

  final bool isHidden;
  final String? customEpisodeTitle;
}

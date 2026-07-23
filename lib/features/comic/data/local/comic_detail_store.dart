import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/local/comic_local_models.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';

class ComicDetailStore {
  ComicDetailStore(this._dbFuture, {ComicSubjectParser? subjectParser});

  final Future<Database> _dbFuture;

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
        'custom_cover_focus_x': null,
        'custom_cover_focus_y': null,
        'metadata_updated_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
  }

  Future<void> updateCustomCoverFromLocalFile({
    required String comicId,
    required String localCoverPath,
    String? sourceEpisodeId,
    int? sourceImageIndex,
    String? sourceImageUrl,
    double? focusX,
    double? focusY,
  }) async {
    final normalizedPath = normalizeNullable(localCoverPath);
    if (normalizedPath == null) {
      throw ArgumentError('自定义封面本地路径不能为空');
    }

    final db = await _dbFuture;
    await db.update(
      ComicLocalDb.comicsTable,
      <String, Object?>{
        'custom_cover_image_url': normalizeNullable(sourceImageUrl),
        'custom_cover_local_path': normalizedPath,
        'custom_cover_source_episode_id': normalizeNullable(sourceEpisodeId),
        'custom_cover_source_image_index': sourceImageIndex,
        'custom_cover_source_image_url': normalizeNullable(sourceImageUrl),
        'custom_cover_focus_x': focusX,
        'custom_cover_focus_y': focusY,
        'metadata_updated_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
  }

  /// 仅更新已有自定义封面的焦点（不改封面文件），用于详情页“调整封面焦点”。
  Future<void> updateCustomCoverFocus({
    required String comicId,
    required double? focusX,
    required double? focusY,
  }) async {
    final db = await _dbFuture;
    await db.update(
      ComicLocalDb.comicsTable,
      <String, Object?>{
        'custom_cover_focus_x': focusX,
        'custom_cover_focus_y': focusY,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
  }

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
      final normalizedTitle = normalizeNullable(customTitle);
      final normalizedAuthor = normalizeNullable(customAuthor);
      final normalizedGroup = normalizeNullable(customTranslationGroup);
      await txn.update(
        ComicLocalDb.comicsTable,
        <String, Object?>{
          'custom_title': normalizedTitle,
          'custom_author': normalizedAuthor,
          'custom_translation_group': normalizedGroup,
          'custom_search_title': normalizeNullable(customSearchTitle),
          'title': displayString(
            customValue: normalizedTitle,
            sourceValue: row['source_title'] as String?,
            fallbackValue: row['title'] as String?,
            emptyFallback: '未命名漫画',
          ),
          'author': displayNullable(
            customValue: normalizedAuthor,
            sourceValue: row['source_author'] as String?,
            fallbackValue: row['author'] as String?,
          ),
          'translation_group': displayNullable(
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
      final nextCustomTitle = title
          ? null
          : normalizeNullable(row['custom_title'] as String?);
      final nextCustomAuthor = author
          ? null
          : normalizeNullable(row['custom_author'] as String?);
      final nextCustomGroup = translationGroup
          ? null
          : normalizeNullable(row['custom_translation_group'] as String?);
      final values = <String, Object?>{
        if (title) 'custom_title': null,
        if (author) 'custom_author': null,
        if (translationGroup) 'custom_translation_group': null,
        if (searchTitle) 'custom_search_title': null,
        'title': displayString(
          customValue: nextCustomTitle,
          sourceValue: row['source_title'] as String?,
          fallbackValue: row['title'] as String?,
          emptyFallback: '未命名漫画',
        ),
        'author': displayNullable(
          customValue: nextCustomAuthor,
          sourceValue: row['source_author'] as String?,
          fallbackValue: row['author'] as String?,
        ),
        'translation_group': displayNullable(
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

  Future<ComicDetail?> getComicDetail({required String comicId}) async {
    final db = await _dbFuture;
    final rows = await db.rawQuery(
      '''
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
        c.custom_cover_focus_x,
        c.custom_cover_focus_y,
        c.catalog_url,
        c.custom_catalog_url,
        c.updated_at,
        COUNT(e.episode_id) AS episode_count
      FROM ${ComicLocalDb.comicsTable} c
      LEFT JOIN ${ComicLocalDb.episodesTable} e
        ON c.comic_id = e.comic_id
      WHERE c.comic_id = ?
      GROUP BY c.comic_id
      LIMIT 1
    ''',
      <Object>[comicId],
    );

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
      customCoverSourceEpisodeId:
          row['custom_cover_source_episode_id'] as String?,
      customCoverSourceImageIndex:
          row['custom_cover_source_image_index'] as int?,
      customCoverSourceImageUrl:
          row['custom_cover_source_image_url'] as String?,
      customCoverFocusX: (row['custom_cover_focus_x'] as num?)?.toDouble(),
      customCoverFocusY: (row['custom_cover_focus_y'] as num?)?.toDouble(),
      catalogUrl: row['catalog_url'] as String?,
      customCatalogUrl: row['custom_catalog_url'] as String?,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      episodeCount: row['episode_count'] as int? ?? 0,
    );
  }

  Future<void> upsertComicFromParsedPostInTxn(
    DatabaseExecutor executor, {
    required String comicId,
    required String tid,
    required String fid,
    String? sourceTypeId,
    String? sourceTagName,
    required String rawTitle,
    required ParsedComicPost parsedPost,
    required int now,
  }) async {
    final existingRows = await executor.query(
      ComicLocalDb.comicsTable,
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
      limit: 1,
    );
    final existing = existingRows.isEmpty
        ? null
        : ComicRecord.fromMap(existingRows.first);
    final sourceTitle = resolveComicTitle(
      rawTitle: rawTitle,
      parsedPost: parsedPost,
    );
    final sourceAuthor = resolveComicAuthor(parsedPost);
    final sourceGroup = normalizeNullable(
      parsedPost.subjectMetadata?.translationGroup,
    );
    final customTitle = normalizeNullable(existing?.customTitle);
    final customAuthor = normalizeNullable(existing?.customAuthor);
    final customGroup = normalizeNullable(existing?.customTranslationGroup);
    final comic = ComicRecord(
      comicId: comicId,
      sourceTid: tid,
      sourceFid: fid,
      sourceTypeId: normalizeNullable(sourceTypeId),
      sourceTagName: normalizeNullable(sourceTagName),
      title: displayString(
        customValue: customTitle,
        sourceValue: sourceTitle,
        fallbackValue: existing?.title,
        emptyFallback: '未命名漫画',
      ),
      sourceTitle: sourceTitle,
      customTitle: customTitle,
      author: displayNullable(
        customValue: customAuthor,
        sourceValue: sourceAuthor,
        fallbackValue: existing?.author,
      ),
      sourceAuthor: sourceAuthor,
      customAuthor: customAuthor,
      translationGroup: displayNullable(
        customValue: customGroup,
        sourceValue: sourceGroup,
        fallbackValue: existing?.translationGroup,
      ),
      sourceTranslationGroup: sourceGroup,
      customTranslationGroup: customGroup,
      customSearchTitle: normalizeNullable(existing?.customSearchTitle),
      coverImageUrl: parsedPost.imageUrls.isEmpty
          ? existing?.coverImageUrl
          : parsedPost.imageUrls.first,
      customCoverImageUrl: existing?.customCoverImageUrl,
      coverLocalPath: parsedPost.imageUrls.isEmpty
          ? existing?.coverLocalPath
          : null,
      customCoverLocalPath: existing?.customCoverLocalPath,
      customCoverSourceEpisodeId: existing?.customCoverSourceEpisodeId,
      customCoverSourceImageIndex: existing?.customCoverSourceImageIndex,
      customCoverSourceImageUrl: existing?.customCoverSourceImageUrl,
      metadataUpdatedAt: existing?.metadataUpdatedAt,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      lastReadEpisodeId: existing?.lastReadEpisodeId,
      catalogUrl: parsedPost.catalogUrl ?? existing?.catalogUrl,
      customCatalogUrl: existing?.customCatalogUrl,
    );

    if (existing == null) {
      await executor.insert(ComicLocalDb.comicsTable, comic.toMap());
      return;
    }

    final values = comic.toMap()..remove('comic_id');
    await executor.update(
      ComicLocalDb.comicsTable,
      values,
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
  }

  String? normalizeNullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String displayString({
    required String? customValue,
    required String? sourceValue,
    required String? fallbackValue,
    required String emptyFallback,
  }) {
    return normalizeNullable(customValue) ??
        normalizeNullable(sourceValue) ??
        normalizeNullable(fallbackValue) ??
        emptyFallback;
  }

  String? displayNullable({
    required String? customValue,
    required String? sourceValue,
    required String? fallbackValue,
  }) {
    return normalizeNullable(customValue) ??
        normalizeNullable(sourceValue) ??
        normalizeNullable(fallbackValue);
  }

  String resolveComicTitle({
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

  String? resolveComicAuthor(ParsedComicPost parsedPost) {
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

  /// 更新漫画的 catalogUrl（发现或更新时调用）。
  Future<void> updateCatalogUrl({
    required String comicId,
    required String catalogUrl,
  }) async {
    final db = await _dbFuture;
    await db.update(
      ComicLocalDb.comicsTable,
      <String, Object?>{
        'catalog_url': catalogUrl,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
  }

  Future<void> updateCustomCatalogUrl({
    required String comicId,
    required String? catalogUrl,
  }) async {
    final db = await _dbFuture;
    await db.update(
      ComicLocalDb.comicsTable,
      <String, Object?>{
        'custom_catalog_url': normalizeNullable(catalogUrl),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'comic_id = ?',
      whereArgs: <Object>[comicId],
    );
  }
}

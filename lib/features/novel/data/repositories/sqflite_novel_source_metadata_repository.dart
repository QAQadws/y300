import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/novel/data/models/novel_source_catalog_json_codec.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_source_metadata_repository.dart';
import 'package:y300/features/novel/domain/services/novel_title_sanitizer.dart';

class SqfliteNovelSourceMetadataRepository
    implements NovelSourceMetadataRepository {
  const SqfliteNovelSourceMetadataRepository(
    this._dbFuture, {
    NovelTitleSanitizer titleSanitizer = const DefaultNovelTitleSanitizer(),
    NovelSourceCatalogJsonCodec catalogCodec =
        const NovelSourceCatalogJsonCodec(),
  }) : _titleSanitizer = titleSanitizer,
       _catalogCodec = catalogCodec;

  static const String _contentType = 'novel';
  static const String _defaultCategoryId = 'default';

  final Future<Database> _dbFuture;
  final NovelTitleSanitizer _titleSanitizer;
  final NovelSourceCatalogJsonCodec _catalogCodec;

  @override
  Future<void> saveFromFavoriteDetail({
    required NovelSourceSeed seed,
    required NovelSourceMetadata metadata,
  }) async {
    final novelId = _requireText(metadata.novelId, 'metadata.novelId');
    final tid = _requireText(metadata.tid, 'metadata.tid');
    final fid = _requireText(metadata.fid, 'metadata.fid');
    final publisherId = _requireText(
      metadata.publisherId,
      'metadata.publisherId',
    );
    final firstPostPid = _requireText(
      metadata.firstPostPid,
      'metadata.firstPostPid',
    );
    final expectedNovelId = 'novel:$fid:$tid';
    if (novelId != expectedNovelId) {
      throw StateError(
        'Novel source metadata id mismatch: $novelId != $expectedNovelId',
      );
    }

    final title = _normalizedTitle(metadata.subject, fallback: tid);
    final catalogJson = _catalogCodec.encode(metadata.catalogEntries);
    final ingestedAt = metadata.ingestedAt.millisecondsSinceEpoch;
    final db = await _dbFuture;

    await db.transaction((txn) async {
      await txn.rawInsert(
        '''
        INSERT INTO ${ComicLocalDb.worksTable} (
          work_id,
          content_type,
          source_tid,
          source_fid,
          source_typeid,
          source_tag_name,
          title,
          author,
          cover_image_url,
          updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(work_id) DO UPDATE SET
          content_type = excluded.content_type,
          source_tid = excluded.source_tid,
          source_fid = excluded.source_fid,
          source_typeid = COALESCE(
            excluded.source_typeid,
            ${ComicLocalDb.worksTable}.source_typeid
          ),
          source_tag_name = COALESCE(
            excluded.source_tag_name,
            ${ComicLocalDb.worksTable}.source_tag_name
          ),
          title = CASE
            WHEN ? IS NOT NULL THEN excluded.title
            ELSE ${ComicLocalDb.worksTable}.title
          END,
          author = COALESCE(excluded.author, ${ComicLocalDb.worksTable}.author),
          cover_image_url = COALESCE(
            excluded.cover_image_url,
            ${ComicLocalDb.worksTable}.cover_image_url
          ),
          updated_at = excluded.updated_at
        ''',
        <Object?>[
          novelId,
          _contentType,
          tid,
          fid,
          _trimToNull(seed.typeid),
          _trimToNull(seed.tagName),
          title,
          _trimToNull(metadata.publisherName),
          _trimToNull(metadata.coverImageUrl),
          ingestedAt,
          _trimToNull(metadata.subject),
        ],
      );

      final existingShelfRows = await txn.query(
        ComicLocalDb.novelShelfItemsTable,
        columns: const <String>['id'],
        where: 'category_id = ? AND novel_id = ?',
        whereArgs: <Object?>[_defaultCategoryId, novelId],
        limit: 1,
      );
      if (existingShelfRows.isEmpty) {
        final orderRows = await txn.rawQuery(
          '''
          SELECT COALESCE(MAX(sort_order), -1) + 1 AS next_order
          FROM ${ComicLocalDb.novelShelfItemsTable}
          WHERE category_id = ?
          ''',
          <Object?>[_defaultCategoryId],
        );
        final sortOrder = orderRows.isEmpty
            ? 0
            : (orderRows.first['next_order'] as num?)?.toInt() ?? 0;
        await txn.insert(ComicLocalDb.novelShelfItemsTable, <String, Object?>{
          'category_id': _defaultCategoryId,
          'novel_id': novelId,
          'added_at': ingestedAt,
          'sort_order': sortOrder,
        });
      }

      await txn.rawInsert(
        '''
        INSERT INTO ${ComicLocalDb.novelSourceStateTable} (
          novel_id,
          publisher_id,
          publisher_name,
          first_post_pid,
          source_intro,
          source_catalog_json,
          metadata_source_version,
          hydration_state,
          metadata_ingested_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(novel_id) DO UPDATE SET
          publisher_id = excluded.publisher_id,
          publisher_name = COALESCE(
            excluded.publisher_name,
            ${ComicLocalDb.novelSourceStateTable}.publisher_name
          ),
          first_post_pid = excluded.first_post_pid,
          source_intro = COALESCE(
            excluded.source_intro,
            ${ComicLocalDb.novelSourceStateTable}.source_intro
          ),
          source_catalog_json = CASE
            WHEN excluded.source_catalog_json <> '[]'
              THEN excluded.source_catalog_json
            ELSE ${ComicLocalDb.novelSourceStateTable}.source_catalog_json
          END,
          metadata_source_version = excluded.metadata_source_version,
          metadata_ingested_at = excluded.metadata_ingested_at
        ''',
        <Object?>[
          novelId,
          publisherId,
          _trimToNull(metadata.publisherName),
          firstPostPid,
          _trimToNull(metadata.sourceIntro),
          catalogJson,
          metadata.sourceApiVersion,
          NovelChapterHydrationState.metadataOnly.storageValue,
          ingestedAt,
        ],
      );
    });
  }

  String _normalizedTitle(String source, {required String fallback}) {
    final sanitized = _titleSanitizer.sanitize(source);
    if (sanitized.isNotEmpty) {
      return sanitized;
    }
    final normalizedSource = source.trim();
    return normalizedSource.isEmpty ? fallback : normalizedSource;
  }

  String _requireText(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
    return normalized;
  }

  String? _trimToNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

import 'package:sqflite/sqflite.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/novel/data/models/novel_source_catalog_json_codec.dart';
import 'package:y300/features/novel/data/repositories/local/novel_source_metadata_writer.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_source_metadata_repository.dart';
import 'package:content_title_core/content_title_core.dart';

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
    required DateTime favoriteAddedAt,
  }) async {
    final novelId = _requireText(metadata.novelId, 'metadata.novelId');
    final tid = _requireText(metadata.tid, 'metadata.tid');
    final fid = _requireText(metadata.fid, 'metadata.fid');
    final publisherId = _requireText(
      metadata.publisherId,
      'metadata.publisherId',
    );
    _requireText(metadata.firstPostPid, 'metadata.firstPostPid');
    final expectedNovelId = 'novel:$fid:$tid';
    if (novelId != expectedNovelId) {
      throw StateError(
        'Novel source metadata id mismatch: $novelId != $expectedNovelId',
      );
    }

    final title = _normalizedTitle(metadata.subject, fallback: tid);
    final ingestedAt = metadata.ingestedAt.millisecondsSinceEpoch;
    final db = await _dbFuture;

    await db.transaction((txn) async {
      final workValues = <String, Object?>{
        'work_id': novelId,
        'content_type': _contentType,
        'source_tid': tid,
        'source_fid': fid,
        'source_typeid': _trimToNull(seed.typeid),
        'source_tag_name': _trimToNull(seed.tagName),
        'title': title,
        'author': _trimToNull(metadata.publisherName),
        'cover_image_url': _trimToNull(metadata.coverImageUrl),
        'updated_at': ingestedAt,
      };
      final updated = await txn.rawUpdate(
        '''
        UPDATE ${AppDatabase.worksTable}
        SET content_type = ?,
          source_tid = ?,
          source_fid = ?,
          source_typeid = COALESCE(?, source_typeid),
          source_tag_name = COALESCE(?, source_tag_name),
          title = CASE
            WHEN ? IS NOT NULL THEN ? ELSE title
          END,
          author = COALESCE(?, author),
          cover_image_url = COALESCE(?, cover_image_url),
          updated_at = ?
        WHERE work_id = ?
        ''',
        <Object?>[
          _contentType,
          tid,
          fid,
          workValues['source_typeid'],
          workValues['source_tag_name'],
          _trimToNull(metadata.subject),
          title,
          workValues['author'],
          workValues['cover_image_url'],
          ingestedAt,
          novelId,
        ],
      );
      if (updated == 0) {
        await txn.insert(AppDatabase.worksTable, workValues);
      }

      final existingShelfRows = await txn.query(
        AppDatabase.novelShelfItemsTable,
        columns: const <String>['id'],
        where: 'novel_id = ?',
        whereArgs: <Object?>[novelId],
        limit: 1,
      );
      if (existingShelfRows.isEmpty) {
        final orderRows = await txn.rawQuery(
          '''
          SELECT COALESCE(MAX(sort_order), -1) + 1 AS next_order
          FROM ${AppDatabase.novelShelfItemsTable}
          WHERE category_id = ?
          ''',
          <Object?>[_defaultCategoryId],
        );
        final sortOrder = orderRows.isEmpty
            ? 0
            : (orderRows.first['next_order'] as num?)?.toInt() ?? 0;
        await txn.insert(AppDatabase.novelShelfItemsTable, <String, Object?>{
          'category_id': _defaultCategoryId,
          'novel_id': novelId,
          'added_at': favoriteAddedAt.millisecondsSinceEpoch,
          'sort_order': sortOrder,
        });
      }

      await writeNovelSourceMetadata(
        txn,
        metadata: metadata,
        novelId: novelId,
        publisherId: publisherId,
        catalogCodec: _catalogCodec,
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

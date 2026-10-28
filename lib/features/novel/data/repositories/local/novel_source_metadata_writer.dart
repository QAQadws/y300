import 'package:sqflite/sqflite.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/novel/data/models/novel_source_catalog_json_codec.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';

/// Shares metadata merge rules without resetting hydration or its checkpoint.
Future<void> writeNovelSourceMetadata(
  Transaction txn, {
  required NovelSourceMetadata metadata,
  required String novelId,
  required String publisherId,
  required NovelSourceCatalogJsonCodec catalogCodec,
}) async {
  String? optionalText(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  final publisherName = optionalText(metadata.publisherName);
  final firstPostPid = optionalText(metadata.firstPostPid);
  final intro = optionalText(metadata.sourceIntro);
  final catalog = catalogCodec.encode(metadata.catalogEntries);
  final ingestedAt = metadata.ingestedAt.millisecondsSinceEpoch;

  // Android's older SQLite engines do not support INSERT ... DO UPDATE.
  // Keep both statements in the caller's transaction and update in place.
  final updated = await txn.rawUpdate(
    '''
    UPDATE ${AppDatabase.novelSourceStateTable}
    SET publisher_id = ?,
        publisher_name = COALESCE(?, publisher_name),
        first_post_pid = ?,
        source_intro = COALESCE(?, source_intro),
        source_catalog_json = CASE
          WHEN ? <> '[]' THEN ? ELSE source_catalog_json END,
        metadata_source_version = ?,
        metadata_ingested_at = ?
    WHERE novel_id = ?
    ''',
    <Object?>[
      publisherId,
      publisherName,
      firstPostPid,
      intro,
      catalog,
      catalog,
      metadata.sourceApiVersion,
      ingestedAt,
      novelId,
    ],
  );
  if (updated == 0) {
    await txn.insert(AppDatabase.novelSourceStateTable, <String, Object?>{
      'novel_id': novelId,
      'publisher_id': publisherId,
      'publisher_name': publisherName,
      'first_post_pid': firstPostPid,
      'source_intro': intro,
      'source_catalog_json': catalog,
      'metadata_source_version': metadata.sourceApiVersion,
      'hydration_state': NovelChapterHydrationState.metadataOnly.storageValue,
      'metadata_ingested_at': ingestedAt,
    });
  }
}

import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_source_state_repository.dart';

class SqfliteNovelSourceStateRepository implements NovelSourceStateRepository {
  const SqfliteNovelSourceStateRepository(this._dbFuture);

  final Future<Database> _dbFuture;

  @override
  Future<NovelSourceState?> getSourceState({required String novelId}) async {
    final db = await _dbFuture;
    final rows = await db.query(
      ComicLocalDb.novelSourceStateTable,
      where: 'novel_id = ?',
      whereArgs: <Object?>[novelId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _mapState(rows.single);
  }

  @override
  Future<void> saveMetadata(NovelSourceMetadata metadata) async {
    final novelId = _requireText(metadata.novelId, 'metadata.novelId');
    final publisherId = _requireText(
      metadata.publisherId,
      'metadata.publisherId',
    );
    final db = await _dbFuture;
    await db.rawInsert(
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
        publisher_name = excluded.publisher_name,
        first_post_pid = excluded.first_post_pid,
        source_intro = excluded.source_intro,
        source_catalog_json = excluded.source_catalog_json,
        metadata_source_version = excluded.metadata_source_version,
        metadata_ingested_at = excluded.metadata_ingested_at
      ''',
      <Object?>[
        novelId,
        publisherId,
        _trimToNull(metadata.publisherName),
        _trimToNull(metadata.firstPostPid),
        _trimToNull(metadata.sourceIntro),
        _encodeCatalog(metadata.catalogEntries),
        metadata.sourceApiVersion,
        NovelChapterHydrationState.metadataOnly.storageValue,
        metadata.ingestedAt.millisecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<void> setHydrationState({
    required String novelId,
    required NovelChapterHydrationState state,
    String? lastError,
    DateTime? chaptersHydratedAt,
  }) async {
    final db = await _dbFuture;
    final values = <String, Object?>{
      'hydration_state': state.storageValue,
      'last_error': _trimToNull(lastError),
      if (chaptersHydratedAt != null)
        'chapters_hydrated_at': chaptersHydratedAt.millisecondsSinceEpoch,
    };
    final updated = await db.update(
      ComicLocalDb.novelSourceStateTable,
      values,
      where: 'novel_id = ?',
      whereArgs: <Object?>[novelId],
    );
    if (updated != 1) {
      throw StateError('Novel source state does not exist: $novelId');
    }
  }

  @override
  Future<void> saveCheckpoint(NovelChapterSyncCheckpoint checkpoint) async {
    final publisherId = _requireText(
      checkpoint.publisherId,
      'checkpoint.publisherId',
    );
    if (checkpoint.lastCompletedAuthorPage < 1) {
      throw RangeError.range(
        checkpoint.lastCompletedAuthorPage,
        1,
        null,
        'checkpoint.lastCompletedAuthorPage',
      );
    }
    final completedAt = checkpoint.completedAt.millisecondsSinceEpoch;
    final db = await _dbFuture;
    final updated = await db.rawUpdate(
      '''
      UPDATE ${ComicLocalDb.novelSourceStateTable}
      SET publisher_id = COALESCE(publisher_id, ?),
          hydration_state = ?,
          chapters_hydrated_at = COALESCE(chapters_hydrated_at, ?),
          last_completed_author_page = ?,
          last_seen_pid = ?,
          last_sync_at = ?,
          last_error = NULL
      WHERE novel_id = ?
        AND (publisher_id IS NULL OR publisher_id = ?)
      ''',
      <Object?>[
        publisherId,
        NovelChapterHydrationState.ready.storageValue,
        completedAt,
        checkpoint.lastCompletedAuthorPage,
        _trimToNull(checkpoint.lastSeenPid),
        completedAt,
        checkpoint.novelId,
        publisherId,
      ],
    );
    if (updated != 1) {
      throw StateError(
        'Novel source state is missing or publisher identity changed: '
        '${checkpoint.novelId}',
      );
    }
  }

  NovelSourceState _mapState(Map<String, Object?> row) {
    return NovelSourceState(
      novelId: row['novel_id'] as String,
      publisherId: _trimToNull(row['publisher_id'] as String?),
      publisherName: _trimToNull(row['publisher_name'] as String?),
      firstPostPid: _trimToNull(row['first_post_pid'] as String?),
      sourceIntro: _trimToNull(row['source_intro'] as String?),
      catalogEntries: _decodeCatalog(row['source_catalog_json'] as String),
      metadataSourceVersion: (row['metadata_source_version'] as num?)?.toInt(),
      hydrationState: NovelChapterHydrationStateCodec.fromStorage(
        row['hydration_state'] as String,
      ),
      metadataIngestedAt: _dateFromEpoch(row['metadata_ingested_at']),
      chaptersHydratedAt: _dateFromEpoch(row['chapters_hydrated_at']),
      lastCompletedAuthorPage:
          (row['last_completed_author_page'] as num?)?.toInt() ?? 0,
      lastSeenPid: _trimToNull(row['last_seen_pid'] as String?),
      lastSyncAt: _dateFromEpoch(row['last_sync_at']),
      lastError: _trimToNull(row['last_error'] as String?),
    );
  }

  String _encodeCatalog(List<NovelSourceCatalogEntry> entries) {
    return jsonEncode(
      entries
          .map(
            (entry) => <String, Object?>{
              'position': entry.position,
              'pid': entry.pid,
              'title': entry.title,
              'url': entry.url,
            },
          )
          .toList(growable: false),
    );
  }

  List<NovelSourceCatalogEntry> _decodeCatalog(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! List) {
      throw const FormatException('Novel source catalog must be a JSON list.');
    }
    return decoded
        .map((value) {
          if (value is! Map) {
            throw const FormatException(
              'Novel source catalog entry must be a map.',
            );
          }
          return NovelSourceCatalogEntry(
            position: (value['position'] as num?)?.toInt() ?? 0,
            pid: value['pid']?.toString() ?? '',
            title: value['title']?.toString() ?? '',
            url: value['url']?.toString() ?? '',
          );
        })
        .toList(growable: false);
  }

  DateTime? _dateFromEpoch(Object? value) {
    final epoch = (value as num?)?.toInt();
    return epoch == null ? null : DateTime.fromMillisecondsSinceEpoch(epoch);
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

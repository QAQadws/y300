import 'package:sqflite/sqflite.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_source_metadata_repository.dart';
import 'package:y300/features/novel/domain/services/novel_source_metadata_parser.dart';
import 'package:y300/features/novel/domain/services/novel_source_metadata_recovery_service.dart';

class DefaultNovelSourceMetadataRecoveryService
    implements NovelSourceMetadataRecoveryService {
  DefaultNovelSourceMetadataRecoveryService({
    required Future<Database> database,
    required NovelSourceMetadataRecoveryGateway gateway,
    required NovelSourceMetadataParser parser,
    required NovelSourceMetadataRepository repository,
    DateTime Function()? clock,
  }) : _database = database,
       _gateway = gateway,
       _parser = parser,
       _repository = repository,
       _clock = clock ?? DateTime.now;

  static const String _contentType = 'novel';

  final Future<Database> _database;
  final NovelSourceMetadataRecoveryGateway _gateway;
  final NovelSourceMetadataParser _parser;
  final NovelSourceMetadataRepository _repository;
  final DateTime Function() _clock;

  @override
  Future<NovelSourceMetadata> recover(String novelId) async {
    final normalizedNovelId = novelId.trim();
    final db = await _database;
    final rows = await db.query(
      ComicLocalDb.worksTable,
      columns: const <String>[
        'source_tid',
        'source_fid',
        'source_typeid',
        'source_tag_name',
      ],
      where: 'work_id = ? AND content_type = ?',
      whereArgs: <Object?>[normalizedNovelId, _contentType],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Novel does not exist: $normalizedNovelId');
    }
    final row = rows.single;
    final seed = NovelSourceSeed(
      tid: (row['source_tid'] as String).trim(),
      fid: (row['source_fid'] as String).trim(),
      typeid: (row['source_typeid'] as String?)?.trim(),
      tagName: (row['source_tag_name'] as String?)?.trim(),
    );
    final detail = await _gateway.loadFirstPage(tid: seed.tid);
    final metadata = _parser.parseFirstPost(
      seed: seed,
      detail: detail,
      ingestedAt: _clock(),
    );
    await _repository.saveFromFavoriteDetail(
      seed: seed,
      metadata: metadata,
      favoriteAddedAt: metadata.ingestedAt,
    );
    return metadata;
  }
}

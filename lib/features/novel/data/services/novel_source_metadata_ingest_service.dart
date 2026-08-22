import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_source_metadata_repository.dart';
import 'package:y300/features/novel/domain/services/novel_source_metadata_parser.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';

typedef NovelMetadataClock = DateTime Function();

abstract interface class NovelSourceMetadataIngestService {
  Future<NovelSourceMetadata> ingestFromFavoriteDetail({
    required NovelSourceSeed seed,
    required ThreadDetailData detail,
    required DateTime favoriteAddedAt,
  });
}

class DefaultNovelSourceMetadataIngestService
    implements NovelSourceMetadataIngestService {
  DefaultNovelSourceMetadataIngestService({
    required NovelSourceMetadataParser parser,
    required NovelSourceMetadataRepository repository,
    NovelMetadataClock? clock,
  }) : _parser = parser,
       _repository = repository,
       _clock = clock ?? DateTime.now;

  final NovelSourceMetadataParser _parser;
  final NovelSourceMetadataRepository _repository;
  final NovelMetadataClock _clock;

  @override
  Future<NovelSourceMetadata> ingestFromFavoriteDetail({
    required NovelSourceSeed seed,
    required ThreadDetailData detail,
    required DateTime favoriteAddedAt,
  }) async {
    final metadata = _parser.parseFirstPost(
      seed: seed,
      detail: detail,
      ingestedAt: _clock(),
    );
    await _repository.saveFromFavoriteDetail(
      seed: seed,
      metadata: metadata,
      favoriteAddedAt: favoriteAddedAt,
    );
    return metadata;
  }
}

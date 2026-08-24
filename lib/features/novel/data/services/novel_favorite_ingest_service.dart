import 'package:y300/features/novel/data/services/novel_source_metadata_ingest_service.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

typedef NovelFavoriteShelfRemover =
    Future<void> Function({required String workId});

abstract class NovelFavoriteIngestService {
  Future<String> upsertFromThreadDetail({
    required ThreadDetailData detail,
    required DateTime favoriteAddedAt,
    String? sourceTagName,
  });

  Future<void> removeFromShelf({required String workId});
}

class RepositoryNovelFavoriteIngestService
    implements NovelFavoriteIngestService {
  const RepositoryNovelFavoriteIngestService({
    required NovelSourceMetadataIngestService metadataIngestService,
    required NovelFavoriteShelfRemover removeFromShelf,
  }) : _metadataIngestService = metadataIngestService,
       _removeFromShelf = removeFromShelf;

  final NovelSourceMetadataIngestService _metadataIngestService;
  final NovelFavoriteShelfRemover _removeFromShelf;

  @override
  Future<String> upsertFromThreadDetail({
    required ThreadDetailData detail,
    required DateTime favoriteAddedAt,
    String? sourceTagName,
  }) async {
    final metadata = await _metadataIngestService.ingestFromFavoriteDetail(
      seed: NovelSourceSeed(
        fid: detail.fid,
        tid: detail.tid,
        typeid: detail.typeid,
        tagName: sourceTagName,
      ),
      detail: detail,
      favoriteAddedAt: favoriteAddedAt,
    );
    return metadata.novelId;
  }

  @override
  Future<void> removeFromShelf({required String workId}) {
    return _removeFromShelf(workId: workId);
  }
}

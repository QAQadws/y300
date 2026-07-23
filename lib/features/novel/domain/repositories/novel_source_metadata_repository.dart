import 'package:y300/features/novel/domain/models/novel_source_models.dart';

/// Atomic write port for metadata-only favorite ingest.
abstract interface class NovelSourceMetadataRepository {
  Future<void> saveFromFavoriteDetail({
    required NovelSourceSeed seed,
    required NovelSourceMetadata metadata,
    required DateTime favoriteAddedAt,
  });
}

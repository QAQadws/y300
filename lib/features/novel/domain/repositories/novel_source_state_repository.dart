import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';

abstract interface class NovelSourceStateRepository {
  Future<NovelSourceState?> getSourceState({required String novelId});

  Future<void> saveMetadata(NovelSourceMetadata metadata);

  Future<void> setHydrationState({
    required String novelId,
    required NovelChapterHydrationState state,
    String? lastError,
    DateTime? chaptersHydratedAt,
  });

  Future<void> saveCheckpoint(NovelChapterSyncCheckpoint checkpoint);
}

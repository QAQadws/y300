import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';

abstract interface class NovelChapterSyncRepository {
  Future<void> beginRun({
    required String runId,
    required String novelId,
    required NovelChapterSyncMode mode,
  });

  Future<void> stageEpisodes({
    required String runId,
    required List<NovelEpisodeDraft> episodes,
  });

  Future<NovelChapterSyncResult> promote({
    required String runId,
    required NovelChapterSyncRequest request,
    required NovelChapterSyncCheckpoint checkpoint,
    required int fetchedPages,
    String? sourceTitle,
  });

  Future<void> discardRun(String runId);
}

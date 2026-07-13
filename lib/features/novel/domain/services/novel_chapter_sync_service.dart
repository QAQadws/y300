import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';

abstract interface class NovelChapterSyncService {
  Stream<NovelChapterSyncProgress> watchProgress(String novelId);

  bool hasActiveRun(String novelId);

  Future<NovelChapterSyncResult> synchronize(NovelChapterSyncRequest request);
}

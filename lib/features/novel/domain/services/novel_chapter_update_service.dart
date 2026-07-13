import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';

abstract interface class NovelChapterUpdateService {
  Future<NovelChapterSyncResult> update(String novelId);
}

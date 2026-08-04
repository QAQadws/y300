import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';

enum NovelChapterUpdateIntent { normal, full }

abstract interface class NovelChapterUpdateService {
  Future<NovelChapterSyncResult> update(
    String novelId, {
    NovelChapterUpdateIntent intent = NovelChapterUpdateIntent.normal,
  });
}

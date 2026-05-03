import 'package:y300/features/novel/data/models/novel_models.dart';

/// 小说仓储：封装小说书架、章节、正文、阅读偏好与阅读进度。
abstract class NovelRepository {
  Future<List<NovelItem>> getShelfItems({String? sourceFid});

  Future<NovelItem?> getDetail({required String novelId});

  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  });

  Future<NovelChapterContent?> getChapterContent({required String episodeId});

  Future<void> upsertReaderPreferences(NovelReaderPreferences preferences);

  Future<NovelReaderPreferences> getReaderPreferences();

  Future<void> upsertNovelBySeed({required NovelRefreshSeed seed});

  Future<NovelEpisodeRefreshResult> refreshEpisodes({required String novelId});

  Future<void> saveReadingProgress({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
  });

  Future<NovelReadingProgress?> getReadingProgress({required String novelId});
}

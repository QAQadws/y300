import 'package:y300/features/novel/data/models/novel_models.dart';

/// 小说仓储抽象。
///
/// 阶段0只定义接口，后续阶段再接入真实网络解析与本地持久化实现。
abstract class NovelRepository {
  Future<List<NovelItem>> getShelfItems();

  Future<NovelItem?> getDetail({required String novelId});

  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  });

  Future<NovelChapterContent?> getChapterContent({required String episodeId});

  Future<void> upsertReaderPreferences(NovelReaderPreferences preferences);

  Future<NovelReaderPreferences?> getReaderPreferences();
}

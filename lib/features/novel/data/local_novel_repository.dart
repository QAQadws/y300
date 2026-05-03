import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_repository.dart';

/// 小说本地仓储占位实现。
///
/// 阶段0只保证接口有默认实现，避免上层在依赖注入时出现空洞。
class LocalNovelRepository implements NovelRepository {
  const LocalNovelRepository();

  @override
  Future<NovelChapterContent?> getChapterContent({required String episodeId}) async => null;

  @override
  Future<NovelItem?> getDetail({required String novelId}) async => null;

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({required String novelId, bool descending = false}) async {
    return const <NovelEpisodeItem>[];
  }

  @override
  Future<NovelReaderPreferences?> getReaderPreferences() async => null;

  @override
  Future<List<NovelItem>> getShelfItems() async => const <NovelItem>[];

  @override
  Future<void> upsertReaderPreferences(NovelReaderPreferences preferences) async {}
}

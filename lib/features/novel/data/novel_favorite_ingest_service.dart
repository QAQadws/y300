import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

abstract class NovelFavoriteIngestService {
  /// 完整摄入：创建作品并立即拉取全部章节。
  Future<String> upsertFromThreadDetail({
    required ThreadDetailData detail,
    String? sourceTagName,
  });

  /// 轻量摄入：只创建书架条目，不拉取章节内容。
  ///
  /// 在收藏管道的第一阶段，小说不需要逐章解析正文内容；
  /// 仅记录作品种子元数据，章节内容在用户实际打开小说时按需加载。
  Future<String> lightUpsertFromThreadDetail({
    required ThreadDetailData detail,
    String? sourceTagName,
  });

  Future<void> removeFromShelf({required String workId});
}

class RepositoryNovelFavoriteIngestService implements NovelFavoriteIngestService {
  const RepositoryNovelFavoriteIngestService(this._repository);

  final NovelRepository _repository;

  @override
  Future<String> upsertFromThreadDetail({
    required ThreadDetailData detail,
    String? sourceTagName,
  }) async {
    final novelId = buildNovelWorkId(fid: detail.fid, tid: detail.tid);
    await _repository.upsertNovelBySeed(
      seed: NovelRefreshSeed(
        fid: detail.fid,
        tid: detail.tid,
        typeid: detail.typeid,
        tagName: sourceTagName,
      ),
    );
    await _repository.refreshEpisodes(novelId: novelId);
    return novelId;
  }

  @override
  Future<String> lightUpsertFromThreadDetail({
    required ThreadDetailData detail,
    String? sourceTagName,
  }) async {
    final novelId = buildNovelWorkId(fid: detail.fid, tid: detail.tid);
    // 只创建书架条目和作品种子，不拉取章节正文。
    // 章节内容在用户首次打开小说详情时按需加载。
    await _repository.upsertNovelBySeed(
      seed: NovelRefreshSeed(
        fid: detail.fid,
        tid: detail.tid,
        typeid: detail.typeid,
        tagName: sourceTagName,
      ),
    );
    return novelId;
  }

  @override
  Future<void> removeFromShelf({required String workId}) {
    return _repository.removeFromShelf(novelId: workId);
  }

  static String buildNovelWorkId({
    required String fid,
    required String tid,
  }) {
    return 'novel:${fid.trim()}:${tid.trim()}';
  }
}

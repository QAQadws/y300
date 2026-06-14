import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/favorites/data/favorite_first_sync_request_governor.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

abstract class NovelFavoriteIngestService {
  Future<String> upsertFromThreadDetail({
    required ThreadDetailData detail,
    String? sourceTagName,
    FavoriteSyncExecutionContext? executionContext,
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
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    final novelId = buildNovelWorkId(fid: detail.fid, tid: detail.tid);
    await _repository.upsertNovelBySeed(
      seed: NovelRefreshSeed(
        fid: detail.fid,
        tid: detail.tid,
        typeid: detail.typeid,
        tagName: sourceTagName,
      ),
      executionContext: executionContext,
    );
    await _repository.refreshEpisodes(
      novelId: novelId,
      executionContext: executionContext,
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

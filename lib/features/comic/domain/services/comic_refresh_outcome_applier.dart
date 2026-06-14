import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_first_episode_cover_service.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';

enum ComicRefreshApplyStatus {
  applied,
  skipped,
}

class ComicRefreshApplyRequest {
  const ComicRefreshApplyRequest({
    required this.comicId,
    required this.sourceTid,
    required this.links,
    required this.source,
    required this.mutationSource,
    required this.reason,
    this.catalogUrl,
  });

  final String comicId;
  final String sourceTid;
  final List<ComicEpisodeLink> links;
  final ComicEpisodeRefreshSource source;
  final LibraryMutationSource mutationSource;
  final String reason;
  /// 本次刷新发现或使用的 catalogUrl。非空时持久化到本地，
  /// 以便下次刷新可直接走 catalog 快速路径。
  final String? catalogUrl;
}

class ComicRefreshApplyResult {
  const ComicRefreshApplyResult({
    required this.status,
    required this.insertedCount,
    required this.updatedCount,
    required this.totalCount,
    required this.coverPromoted,
  });

  const ComicRefreshApplyResult.skipped()
      : status = ComicRefreshApplyStatus.skipped,
        insertedCount = 0,
        updatedCount = 0,
        totalCount = 0,
        coverPromoted = false;

  final ComicRefreshApplyStatus status;
  final int insertedCount;
  final int updatedCount;
  final int totalCount;
  final bool coverPromoted;
}

abstract class ComicRefreshOutcomeApplier {
  Future<ComicRefreshApplyResult> apply(ComicRefreshApplyRequest request);
}

class DefaultComicRefreshOutcomeApplier
    implements ComicRefreshOutcomeApplier {
  const DefaultComicRefreshOutcomeApplier({
    required ComicRepository repository,
    required ComicFirstEpisodeCoverPromoter firstEpisodeCoverPromoter,
    required LibraryShelfRefreshBus shelfRefreshBus,
  }) : _repository = repository,
       _firstEpisodeCoverPromoter = firstEpisodeCoverPromoter,
       _shelfRefreshBus = shelfRefreshBus;

  final ComicRepository _repository;
  final ComicFirstEpisodeCoverPromoter _firstEpisodeCoverPromoter;
  final LibraryShelfRefreshBus _shelfRefreshBus;

  @override
  Future<ComicRefreshApplyResult> apply(
    ComicRefreshApplyRequest request,
  ) async {
    if (request.links.isEmpty) {
      return const ComicRefreshApplyResult.skipped();
    }

    // 持久化 catalogUrl（发现或更新时写入，以便下次走 catalog 快速路径）
    final catalogUrl = request.catalogUrl;
    if (catalogUrl != null && catalogUrl.isNotEmpty) {
      await _repository.updateCatalogUrl(
        comicId: request.comicId,
        catalogUrl: catalogUrl,
      );
    }

    final mergeResult = await _repository.mergeEpisodesFromLinks(
      comicId: request.comicId,
      episodeLinks: request.links,
      fallbackSourceTid: request.sourceTid,
    );
    final coverPromoted = await _firstEpisodeCoverPromoter.promoteIfPossible(
      comicId: request.comicId,
    );
    _shelfRefreshBus.notify(
      modules: const <LibraryModuleKey>{
        LibraryModuleKey.comic,
        LibraryModuleKey.favorite,
      },
      reason: request.reason,
      source: request.mutationSource,
      workId: request.comicId,
      tid: request.sourceTid,
      payload: <String, Object?>{
        'episodeSource': request.source.name,
        'insertedCount': mergeResult.insertedCount,
        'updatedCount': mergeResult.updatedCount,
        'totalCount': mergeResult.totalCount,
        'coverPromoted': coverPromoted,
      },
    );
    return ComicRefreshApplyResult(
      status: ComicRefreshApplyStatus.applied,
      insertedCount: mergeResult.insertedCount,
      updatedCount: mergeResult.updatedCount,
      totalCount: mergeResult.totalCount,
      coverPromoted: coverPromoted,
    );
  }
}

import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/comic/domain/services/comic_episode_images_fetch_result.dart';
import 'package:y300/features/comic/domain/services/comic_thread_discovery_cache.dart';
import 'package:y300/features/favorites/data/services/favorite_sync_request_governor.dart';

typedef ComicEpisodeImageFetcher =
    Future<ComicEpisodeImagesFetchResult> Function(String tid);

abstract class ComicFirstEpisodeCoverPromoter {
  Future<bool> promoteIfPossible({
    required String comicId,
    ComicThreadDiscoveryCache? threadCache,
    FavoriteSyncRequestGovernor? governor,
  });
}

/// Promotes the first image of the lowest-tid episode to the normal comic
/// cover. The service stays storage-agnostic: SQLite-specific write details
/// remain behind [ComicFirstEpisodeCoverWriter] or [ComicRepository].
class ComicFirstEpisodeCoverService implements ComicFirstEpisodeCoverPromoter {
  ComicFirstEpisodeCoverService({
    required ComicRepository repository,
    ComicEpisodeImageFetcher? fetchEpisodeImages,
  }) : _repository = repository,
       _fetchEpisodeImages = fetchEpisodeImages;

  final ComicRepository _repository;
  final ComicEpisodeImageFetcher? _fetchEpisodeImages;

  @override
  Future<bool> promoteIfPossible({
    required String comicId,
    ComicThreadDiscoveryCache? threadCache,
    FavoriteSyncRequestGovernor? governor,
  }) async {
    final detail = await _repository.getComicDetail(comicId: comicId);
    if (detail == null || _hasCustomCover(detail)) {
      return false;
    }

    final episode = await _firstEpisodeByTid(comicId);
    if (episode == null) {
      return false;
    }

    final existingImages = await _repository.getEpisodeImages(
      episodeId: episode.episodeId,
    );
    if (existingImages.isNotEmpty) {
      return _promoteKnownImage(
        comicId: comicId,
        episodeId: episode.episodeId,
        imageUrl: existingImages.first.imageUrl,
        fallbackImageUrls: existingImages.map((image) => image.imageUrl),
      );
    }

    // 1) 优先复用 discovery 阶段已抓取的 thread 详情，避免再发一次 viewthread。
    final cached = threadCache?.get(episode.sourceTid);
    if (cached != null) {
      final cachedImages = _dedupeNonEmpty(_extractFirstPostImages(cached));
      if (cachedImages.isNotEmpty) {
        await _repository.saveEpisodeImages(
          episodeId: episode.episodeId,
          imageUrls: cachedImages,
        );
        return true;
      }
    }

    // 2) discovery 没碰过这一话；走 governor 拉取（首同步内不会越过 cooldown）。
    final fetcher = _fetchEpisodeImages;
    if (fetcher == null) {
      return false;
    }
    final fetchResult = await _runFetch(
      governor,
      () => fetcher(episode.sourceTid),
    );
    final fetched = switch (fetchResult) {
      ComicEpisodeImagesFetched(:final imageUrls) => _dedupeNonEmpty(imageUrls),
      ComicEpisodeImagesFetchFailed() => const <String>[],
    };
    if (fetched.isEmpty) {
      return false;
    }

    // saveEpisodeImages already owns image-row replacement and the local
    // repository's first-episode cover promotion hook.
    await _repository.saveEpisodeImages(
      episodeId: episode.episodeId,
      imageUrls: fetched,
    );
    return true;
  }

  Future<ComicEpisodeImagesFetchResult> _runFetch(
    FavoriteSyncRequestGovernor? governor,
    Future<ComicEpisodeImagesFetchResult> Function() action,
  ) {
    if (governor == null) {
      return action();
    }
    return governor.run(
      kind: FavoriteSyncRequestKind.comicThreadDetail,
      action: action,
    );
  }

  List<String> _extractFirstPostImages(ComicThreadDiscoveryDocument detail) {
    final firstPost = detail.posts
        .where((post) => post.isFirst || post.floorNumber == 1)
        .firstOrNull;
    if (firstPost == null) {
      return const <String>[];
    }
    return firstPost.imageReferences
        .map((source) => source.url)
        .toList(growable: false);
  }

  Future<bool> _promoteKnownImage({
    required String comicId,
    required String episodeId,
    required String imageUrl,
    required Iterable<String> fallbackImageUrls,
  }) async {
    final writer = _repository is ComicFirstEpisodeCoverWriter
        ? _repository as ComicFirstEpisodeCoverWriter
        : null;
    if (writer != null) {
      return writer.promoteFirstEpisodeCover(
        comicId: comicId,
        episodeId: episodeId,
        imageUrl: imageUrl,
      );
    }

    final imageUrls = _dedupeNonEmpty(fallbackImageUrls);
    if (imageUrls.isEmpty) {
      return false;
    }
    await _repository.saveEpisodeImages(
      episodeId: episodeId,
      imageUrls: imageUrls,
    );
    return true;
  }

  Future<ComicEpisodeItem?> _firstEpisodeByTid(String comicId) async {
    final episodes = await _repository.getComicEpisodes(
      comicId: comicId,
      descending: false,
    );
    if (episodes.isEmpty) {
      return null;
    }
    final ordered = episodes.toList(growable: false)
      ..sort(_compareEpisodesByFirstTid);
    return ordered.first;
  }

  int _compareEpisodesByFirstTid(ComicEpisodeItem a, ComicEpisodeItem b) {
    final aTid = int.tryParse(a.sourceTid.trim());
    final bTid = int.tryParse(b.sourceTid.trim());
    if (aTid != null && bTid != null && aTid != bTid) {
      return aTid.compareTo(bTid);
    }
    if (aTid != null && bTid == null) {
      return -1;
    }
    if (aTid == null && bTid != null) {
      return 1;
    }
    final order = a.orderIndex.compareTo(b.orderIndex);
    if (order != 0) {
      return order;
    }
    return a.episodeId.compareTo(b.episodeId);
  }

  bool _hasCustomCover(ComicDetail detail) {
    final customSource = detail.customCoverImageUrl?.trim();
    if (customSource != null && customSource.isNotEmpty) {
      return true;
    }
    final customLocal = detail.customCoverLocalPath?.trim();
    return customLocal != null && customLocal.isNotEmpty;
  }

  List<String> _dedupeNonEmpty(Iterable<String> source) {
    final output = <String>[];
    final seen = <String>{};
    for (final item in source) {
      final trimmed = item.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed)) {
        output.add(trimmed);
      }
    }
    return output;
  }
}

extension _FirstOrNullThreadPostExt<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

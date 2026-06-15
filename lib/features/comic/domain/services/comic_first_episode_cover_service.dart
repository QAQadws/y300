import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/services/comic_thread_detail_cache.dart';
import 'package:y300/features/favorites/data/favorite_first_sync_request_governor.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/services/forum_image_source_pipeline.dart';

typedef ComicEpisodeImageFetcher = Future<List<String>> Function(String tid);

abstract class ComicFirstEpisodeCoverPromoter {
  Future<bool> promoteIfPossible({
    required String comicId,
    ComicThreadDetailCache? threadCache,
    FavoriteFirstSyncRequestGovernor? governor,
  });
}

/// Promotes the first image of the lowest-tid episode to the normal comic
/// cover. The service stays storage-agnostic: SQLite-specific write details
/// remain behind [ComicFirstEpisodeCoverWriter] or [ComicRepository].
class ComicFirstEpisodeCoverService implements ComicFirstEpisodeCoverPromoter {
  ComicFirstEpisodeCoverService({
    required ComicRepository repository,
    ComicEpisodeImageFetcher? fetchEpisodeImagesByTid,
    ForumImageSourcePipeline? imageSourcePipeline,
  })  : _repository = repository,
        _fetchEpisodeImagesByTid = fetchEpisodeImagesByTid,
        _imageSourcePipeline =
            imageSourcePipeline ?? const DefaultForumImageSourcePipeline();

  final ComicRepository _repository;
  final ComicEpisodeImageFetcher? _fetchEpisodeImagesByTid;
  final ForumImageSourcePipeline _imageSourcePipeline;

  @override
  Future<bool> promoteIfPossible({
    required String comicId,
    ComicThreadDetailCache? threadCache,
    FavoriteFirstSyncRequestGovernor? governor,
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
    final fetcher = _fetchEpisodeImagesByTid;
    if (fetcher == null) {
      return false;
    }
    final fetched = _dedupeNonEmpty(
      await _runFetch(governor, () => fetcher(episode.sourceTid)),
    );
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

  Future<List<String>> _runFetch(
    FavoriteFirstSyncRequestGovernor? governor,
    Future<List<String>> Function() action,
  ) {
    if (governor == null) {
      return action();
    }
    return governor.run(
      kind: FavoriteFirstSyncRequestKind.comicThreadDetail,
      action: action,
    );
  }

  List<String> _extractFirstPostImages(ThreadDetailData detail) {
    final firstPost = detail.posts
        .where((post) => post.isFirst || post.number == 1)
        .firstOrNull;
    if (firstPost == null) {
      return const <String>[];
    }
    return _imageSourcePipeline
        .collectFromPost(firstPost)
        .map((source) => source.normalizedUrl)
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

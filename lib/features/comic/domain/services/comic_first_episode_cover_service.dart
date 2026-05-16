import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';

typedef ComicEpisodeImageFetcher = Future<List<String>> Function(String tid);

/// Promotes the first image of the lowest-tid episode to the normal comic
/// cover. The service stays storage-agnostic: SQLite-specific write details
/// remain behind [ComicFirstEpisodeCoverWriter] or [ComicRepository].
class ComicFirstEpisodeCoverService {
  const ComicFirstEpisodeCoverService({
    required ComicRepository repository,
    ComicEpisodeImageFetcher? fetchEpisodeImagesByTid,
  })  : _repository = repository,
        _fetchEpisodeImagesByTid = fetchEpisodeImagesByTid;

  final ComicRepository _repository;
  final ComicEpisodeImageFetcher? _fetchEpisodeImagesByTid;

  Future<bool> promoteIfPossible({
    required String comicId,
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

    final fetcher = _fetchEpisodeImagesByTid;
    if (fetcher == null) {
      return false;
    }
    final fetched = _dedupeNonEmpty(await fetcher(episode.sourceTid));
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

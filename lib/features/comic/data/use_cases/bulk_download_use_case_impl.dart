import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_download_queue_models.dart';
import 'package:y300/features/comic/domain/services/bulk_download_use_case.dart';
import 'package:y300/features/comic/domain/services/comic_download_queue.dart';

class DefaultBulkDownloadUseCase implements BulkDownloadUseCase {
  DefaultBulkDownloadUseCase({
    required ComicRepository comicRepository,
    required ComicDownloadQueue downloadQueue,
  }) : _comicRepository = comicRepository,
       _downloadQueue = downloadQueue;

  final ComicRepository _comicRepository;
  final ComicDownloadQueue _downloadQueue;

  @override
  Future<BulkDownloadResult> downloadComics(Set<String> comicIds) async {
    final requestedComicIds = comicIds
        .map((comicId) => comicId.trim())
        .where((comicId) => comicId.isNotEmpty)
        .toList(growable: false);
    final targets = <ComicDownloadTarget>[];
    for (final comicId in requestedComicIds) {
      final detail = await _comicRepository.getComicDetail(comicId: comicId);
      final comicTitle = _titleOrFallback(detail?.title, comicId);
      final episodes = await _comicRepository.getComicEpisodes(
        comicId: comicId,
        descending: false,
      );
      for (final episode in episodes) {
        targets.add(
          ComicDownloadTarget(
            comicId: comicId,
            episodeId: episode.episodeId,
            comicTitle: comicTitle,
            episodeTitle: _titleOrFallback(
              episode.episodeTitle,
              episode.sourceTid,
            ),
          ),
        );
      }
    }
    final result = await _downloadQueue.enqueueTargets(targets);
    return BulkDownloadResult(
      requestedCount: result.requestedCount,
      enqueuedCount: result.enqueuedCount,
      deduplicatedCount: result.deduplicatedCount,
      skippedDownloadedCount: result.skippedDownloadedCount,
    );
  }

  String _titleOrFallback(String? value, String fallback) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? fallback : normalized;
  }
}

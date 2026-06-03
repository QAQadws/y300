import 'package:flutter/foundation.dart';
import 'package:y300/features/comic/data/comic_download_service.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/services/bulk_download_use_case.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/library_task_progress_hub.dart';

class DefaultBulkDownloadUseCase implements BulkDownloadUseCase {
  DefaultBulkDownloadUseCase({
    required ComicRepository comicRepository,
    required ComicDownloadService downloadService,
    required LibraryStateRepository libraryStateRepository,
    required LibraryTaskProgressHub taskProgressHub,
    required LibraryShelfRefreshBus shelfRefreshBus,
  }) : _comicRepository = comicRepository,
       _downloadService = downloadService,
       _libraryStateRepository = libraryStateRepository,
       _taskProgressHub = taskProgressHub,
       _shelfRefreshBus = shelfRefreshBus;

  final ComicRepository _comicRepository;
  final ComicDownloadService _downloadService;
  final LibraryStateRepository _libraryStateRepository;
  final LibraryTaskProgressHub _taskProgressHub;
  final LibraryShelfRefreshBus _shelfRefreshBus;

  bool _running = false;

  @override
  Future<BulkDownloadResult> downloadComics(Set<String> comicIds) async {
    if (_running) {
      throw StateError('已有批量下载任务进行中');
    }
    final requestedComicIds = comicIds
        .map((comicId) => comicId.trim())
        .where((comicId) => comicId.isNotEmpty)
        .toList(growable: false);
    if (requestedComicIds.isEmpty) {
      return const BulkDownloadResult(
        requestedComicIds: <String>[],
        completedComicIds: <String>[],
        failedComicIds: <String>[],
        downloadedEpisodeCount: 0,
      );
    }

    _running = true;
    final progress = ValueNotifier<LibraryShelfTaskProgress?>(null);
    final registration = _taskProgressHub.registerSource(
      modules: const <LibraryModuleKey>{LibraryModuleKey.comic},
      progress: progress,
      priority: LibraryTaskProgressPriority.high,
    );

    try {
      var totalEpisodes = 0;
      final episodesByComic = <String, List<ComicEpisodeItem>>{};
      final titlesByComic = <String, String>{};
      for (final comicId in requestedComicIds) {
        final detail = await _comicRepository.getComicDetail(comicId: comicId);
        final detailTitle = detail?.title.trim();
        titlesByComic[comicId] =
            detailTitle != null && detailTitle.isNotEmpty ? detailTitle : comicId;
        final episodes = await _comicRepository.getComicEpisodes(
          comicId: comicId,
          descending: false,
        );
        episodesByComic[comicId] = episodes;
        totalEpisodes += episodes.length;
      }

      final completedComicIds = <String>[];
      final failedComicIds = <String>[];
      var downloadedEpisodeCount = 0;
      var processedEpisodeCount = 0;

      for (final comicId in requestedComicIds) {
        progress.value = LibraryShelfTaskProgress(
          message: '正在下载漫画：${titlesByComic[comicId] ?? comicId}',
          current: processedEpisodeCount,
          total: totalEpisodes,
          source: LibraryMutationSource.bulkDownload,
          visible: true,
          reloadOnCompletion: true,
        );

        final episodes = episodesByComic[comicId] ?? const <ComicEpisodeItem>[];
        if (episodes.isEmpty) {
          failedComicIds.add(comicId);
          continue;
        }

        var comicHasFailure = false;
        for (final episode in episodes) {
          try {
            await _downloadService.downloadEpisode(
              comicId: comicId,
              episodeId: episode.episodeId,
            );
            await _libraryStateRepository.upsertEpisodeState(
              moduleKey: LibraryModuleKey.comic,
              episodeId: episode.episodeId,
              workId: comicId,
              isDownloaded: true,
              downloadedAt: DateTime.now(),
            );
            downloadedEpisodeCount += 1;
          } catch (_) {
            comicHasFailure = true;
          } finally {
            processedEpisodeCount += 1;
            progress.value = LibraryShelfTaskProgress(
              message: '正在下载漫画：${titlesByComic[comicId] ?? comicId}',
              current: processedEpisodeCount,
              total: totalEpisodes,
              source: LibraryMutationSource.bulkDownload,
              visible: true,
              reloadOnCompletion: true,
            );
          }
        }

        if (comicHasFailure) {
          failedComicIds.add(comicId);
        } else {
          completedComicIds.add(comicId);
        }
      }

      if (downloadedEpisodeCount > 0) {
        _shelfRefreshBus.notify(
          modules: const <LibraryModuleKey>{LibraryModuleKey.comic},
          reason: failedComicIds.isEmpty
              ? 'comic_bulk_download_completed'
              : 'comic_bulk_download_partially_completed',
          source: LibraryMutationSource.bulkDownload,
          payload: <String, Object?>{
            'requestedComicCount': requestedComicIds.length,
            'completedComicCount': completedComicIds.length,
            'failedComicCount': failedComicIds.length,
            'downloadedEpisodeCount': downloadedEpisodeCount,
          },
        );
      }

      return BulkDownloadResult(
        requestedComicIds: requestedComicIds,
        completedComicIds: completedComicIds,
        failedComicIds: failedComicIds,
        downloadedEpisodeCount: downloadedEpisodeCount,
      );
    } finally {
      progress.value = null;
      registration.dispose();
      progress.dispose();
      _running = false;
    }
  }
}

import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/services/novel_download_service.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';

typedef NovelReaderCacheProgressChanged = void Function(int current, int total);

class NovelReaderCacheResult {
  const NovelReaderCacheResult({
    required this.totalCount,
    required this.successCount,
    required this.failureCount,
    this.failedEpisodeIds = const <String>[],
    this.errorMessage,
  });

  const NovelReaderCacheResult.empty()
      : totalCount = 0,
        successCount = 0,
        failureCount = 0,
        failedEpisodeIds = const <String>[],
        errorMessage = null;

  final int totalCount;
  final int successCount;
  final int failureCount;
  final List<String> failedEpisodeIds;
  final String? errorMessage;

  bool get hasFailures => failureCount > 0;
  bool get didAnySucceed => successCount > 0;
}

abstract class NovelReaderCacheService {
  Future<NovelReaderCacheResult> cacheCurrentEpisode({
    required String novelId,
    required String episodeId,
    NovelReaderCacheProgressChanged? onProgress,
  });

  Future<NovelReaderCacheResult> cacheFollowingEpisodes({
    required String novelId,
    required String episodeId,
    required int count,
    NovelReaderCacheProgressChanged? onProgress,
  });

  Future<NovelReaderCacheResult> deleteCurrentEpisodeCache({
    required String novelId,
    required String episodeId,
    NovelReaderCacheProgressChanged? onProgress,
  });

  Future<Set<String>> getDownloadedEpisodeIds({
    required String novelId,
    required Iterable<String> episodeIds,
  });
}

class DefaultNovelReaderCacheService implements NovelReaderCacheService {
  DefaultNovelReaderCacheService({
    required NovelDownloadService downloadService,
    required NovelRepository repository,
    required LibraryStateRepository stateRepository,
  })  : _downloadService = downloadService,
        _repository = repository,
        _stateRepository = stateRepository;

  final NovelDownloadService _downloadService;
  final NovelRepository _repository;
  final LibraryStateRepository _stateRepository;

  @override
  Future<NovelReaderCacheResult> cacheCurrentEpisode({
    required String novelId,
    required String episodeId,
    NovelReaderCacheProgressChanged? onProgress,
  }) async {
    final episode = await _findEpisode(novelId: novelId, episodeId: episodeId);
    if (episode == null) {
      return const NovelReaderCacheResult(
        totalCount: 1,
        successCount: 0,
        failureCount: 1,
        errorMessage: '章节不存在',
      );
    }
    return _cacheEpisodes(
      novelId: novelId,
      episodes: <NovelEpisodeItem>[episode],
      onProgress: onProgress,
    );
  }

  @override
  Future<NovelReaderCacheResult> cacheFollowingEpisodes({
    required String novelId,
    required String episodeId,
    required int count,
    NovelReaderCacheProgressChanged? onProgress,
  }) async {
    if (count <= 0) {
      return const NovelReaderCacheResult.empty();
    }
    final episodes = await _repository.getEpisodes(
      novelId: novelId,
      descending: false,
    );
    final currentIndex = episodes.indexWhere(
      (episode) => episode.episodeId == episodeId,
    );
    if (currentIndex < 0) {
      return const NovelReaderCacheResult(
        totalCount: 0,
        successCount: 0,
        failureCount: 1,
        errorMessage: '章节不存在',
      );
    }
    final targets = episodes
        .skip(currentIndex + 1)
        .take(count)
        .toList(growable: false);
    if (targets.isEmpty) {
      return const NovelReaderCacheResult.empty();
    }
    return _cacheEpisodes(
      novelId: novelId,
      episodes: targets,
      onProgress: onProgress,
    );
  }

  @override
  Future<NovelReaderCacheResult> deleteCurrentEpisodeCache({
    required String novelId,
    required String episodeId,
    NovelReaderCacheProgressChanged? onProgress,
  }) async {
    final episode = await _findEpisode(novelId: novelId, episodeId: episodeId);
    if (episode == null) {
      return const NovelReaderCacheResult(
        totalCount: 1,
        successCount: 0,
        failureCount: 1,
        errorMessage: '章节不存在',
      );
    }
    onProgress?.call(0, 1);
    try {
      await _downloadService.deleteChapterDownload(
        novelId: novelId,
        episodeId: episode.episodeId,
      );
      await _stateRepository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.novel,
        episodeId: episode.episodeId,
        workId: novelId,
        isDownloaded: false,
        downloadedAt: null,
      );
      onProgress?.call(1, 1);
      return const NovelReaderCacheResult(
        totalCount: 1,
        successCount: 1,
        failureCount: 0,
      );
    } catch (error) {
      onProgress?.call(1, 1);
      return NovelReaderCacheResult(
        totalCount: 1,
        successCount: 0,
        failureCount: 1,
        failedEpisodeIds: <String>[episode.episodeId],
        errorMessage: _errorMessage(error),
      );
    }
  }

  @override
  Future<Set<String>> getDownloadedEpisodeIds({
    required String novelId,
    required Iterable<String> episodeIds,
  }) async {
    final downloaded = <String>{};
    for (final episodeId in episodeIds) {
      final state = await _stateRepository.getEpisodeState(
        moduleKey: LibraryModuleKey.novel,
        episodeId: episodeId,
      );
      if (state?.workId == novelId && (state?.isDownloaded ?? false)) {
        downloaded.add(episodeId);
      }
    }
    return downloaded;
  }

  Future<NovelReaderCacheResult> _cacheEpisodes({
    required String novelId,
    required List<NovelEpisodeItem> episodes,
    NovelReaderCacheProgressChanged? onProgress,
  }) async {
    if (episodes.isEmpty) {
      return const NovelReaderCacheResult.empty();
    }
    var successCount = 0;
    final failedEpisodeIds = <String>[];
    Object? firstError;
    onProgress?.call(0, episodes.length);
    for (var index = 0; index < episodes.length; index += 1) {
      final episode = episodes[index];
      try {
        await _downloadService.downloadChapter(
          novelId: novelId,
          episodeId: episode.episodeId,
        );
        await _stateRepository.upsertEpisodeState(
          moduleKey: LibraryModuleKey.novel,
          episodeId: episode.episodeId,
          workId: novelId,
          isDownloaded: true,
          downloadedAt: DateTime.now(),
        );
        successCount += 1;
      } catch (error) {
        firstError ??= error;
        failedEpisodeIds.add(episode.episodeId);
      } finally {
        onProgress?.call(index + 1, episodes.length);
      }
    }
    return NovelReaderCacheResult(
      totalCount: episodes.length,
      successCount: successCount,
      failureCount: failedEpisodeIds.length,
      failedEpisodeIds: failedEpisodeIds,
      errorMessage: firstError == null ? null : _errorMessage(firstError),
    );
  }

  Future<NovelEpisodeItem?> _findEpisode({
    required String novelId,
    required String episodeId,
  }) async {
    final episodes = await _repository.getEpisodes(
      novelId: novelId,
      descending: false,
    );
    for (final episode in episodes) {
      if (episode.episodeId == episodeId) {
        return episode;
      }
    }
    return null;
  }

  String _errorMessage(Object? error) {
    if (error == null) {
      return '操作失败';
    }
    final message = error.toString().trim();
    return message.isEmpty ? '操作失败' : message;
  }
}

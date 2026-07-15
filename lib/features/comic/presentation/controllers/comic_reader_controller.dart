import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/comic/data/services/comic_download_service.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/services/comic_episode_images_fetch_result.dart';
import 'package:y300/features/comic/domain/services/comic_episode_images_unavailable.dart';
import 'package:y300/features/comic/domain/services/comic_reader_chapter_preload.dart';
import 'package:y300/features/comic/domain/services/comic_reader_events.dart';
import 'package:y300/features/comic/domain/services/comic_reader_feature_flags.dart';
import 'package:y300/features/comic/domain/services/comic_reader_preload_queue.dart';
import 'package:y300/features/comic/domain/services/comic_reading_state_writer.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/domain/image_session/reader_image_session.dart';

class ComicReaderArgs {
  const ComicReaderArgs({required this.comicId, required this.episodeId});

  final String comicId;
  final String episodeId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ComicReaderArgs &&
        other.comicId == comicId &&
        other.episodeId == episodeId;
  }

  @override
  int get hashCode => Object.hash(comicId, episodeId);
}

class ComicReaderImageState {
  const ComicReaderImageState({
    required this.imageUrl,
    required this.imageIndex,
    required this.cacheStatus,
    this.cacheKey,
    this.localPath,
    this.cacheLocalPath,
    this.width,
    this.height,
    this.failed = false,
  });

  final String imageUrl;
  final int imageIndex;
  final String cacheStatus;
  final String? cacheKey;
  final String? localPath;
  final String? cacheLocalPath;
  final int? width;
  final int? height;
  final bool failed;

  String? get effectiveLocalPath {
    final local = localPath?.trim();
    if (local != null && local.isNotEmpty) {
      return local;
    }
    final legacy = cacheLocalPath?.trim();
    return legacy == null || legacy.isEmpty ? null : legacy;
  }

  bool get hasCachedLocalFile {
    return cacheStatus == 'done' && effectiveLocalPath != null;
  }

  ComicReaderImageState copyWith({
    String? cacheStatus,
    String? cacheKey,
    String? localPath,
    String? cacheLocalPath,
    int? width,
    int? height,
    bool? failed,
    bool clearLocalPath = false,
    bool clearCacheLocalPath = false,
  }) {
    return ComicReaderImageState(
      imageUrl: imageUrl,
      imageIndex: imageIndex,
      cacheStatus: cacheStatus ?? this.cacheStatus,
      cacheKey: cacheKey ?? this.cacheKey,
      localPath: clearLocalPath ? null : (localPath ?? this.localPath),
      cacheLocalPath: clearCacheLocalPath
          ? null
          : (cacheLocalPath ?? this.cacheLocalPath),
      width: width ?? this.width,
      height: height ?? this.height,
      failed: failed ?? this.failed,
    );
  }
}

class ComicReaderCacheSummary {
  const ComicReaderCacheSummary({
    required this.totalCount,
    required this.doneCount,
    required this.downloadedCount,
    required this.failedCount,
  });

  final int totalCount;
  final int doneCount;
  final int downloadedCount;
  final int failedCount;

  int get cachedCount => doneCount + downloadedCount;
}

class ComicReaderChapterEntry {
  const ComicReaderChapterEntry({
    required this.episodeId,
    required this.title,
    required this.orderIndex,
    required this.sourceTid,
    required this.isCurrent,
    required this.isRead,
  });

  final String episodeId;
  final String title;
  final int orderIndex;
  final String sourceTid;
  final bool isCurrent;
  final bool isRead;
}

class ComicReaderViewState {
  const ComicReaderViewState({
    required this.comicId,
    required this.episodeId,
    required this.comicTitle,
    required this.episodeTitle,
    required this.sourceTid,
    required this.images,
    required this.chapters,
    required this.currentImageIndex,
    required this.lastScrollOffset,
    required this.hasPreviousEpisode,
    required this.hasNextEpisode,
    this.isCurrentEpisodeRead = false,
    this.isBookmarked = false,
    this.failedImageCount = 0,
    this.cacheSummary = const ComicReaderCacheSummary(
      totalCount: 0,
      doneCount: 0,
      downloadedCount: 0,
      failedCount: 0,
    ),
    this.nextChapterPreload = const ComicReaderChapterPreloadState(
      status: ComicReaderChapterPreloadStatus.unavailable,
    ),
    this.isSwitchingEpisode = false,
    this.hint,
  });

  final String comicId;
  final String episodeId;
  final String comicTitle;
  final String episodeTitle;
  final String sourceTid;
  final List<ComicReaderImageState> images;
  final List<ComicReaderChapterEntry> chapters;
  final int currentImageIndex;
  final double lastScrollOffset;
  final bool hasPreviousEpisode;
  final bool hasNextEpisode;
  final bool isCurrentEpisodeRead;
  final bool isBookmarked;
  final int failedImageCount;
  final ComicReaderCacheSummary cacheSummary;
  final ComicReaderChapterPreloadState nextChapterPreload;
  final bool isSwitchingEpisode;
  final String? hint;

  ComicReaderImageState? get currentImage {
    if (images.isEmpty) {
      return null;
    }
    return images[currentImageIndex.clamp(0, images.length - 1).toInt()];
  }

  ComicReaderViewState copyWith({
    List<ComicReaderImageState>? images,
    List<ComicReaderChapterEntry>? chapters,
    int? currentImageIndex,
    double? lastScrollOffset,
    bool? hasPreviousEpisode,
    bool? hasNextEpisode,
    bool? isCurrentEpisodeRead,
    bool? isBookmarked,
    int? failedImageCount,
    ComicReaderCacheSummary? cacheSummary,
    ComicReaderChapterPreloadState? nextChapterPreload,
    bool? isSwitchingEpisode,
    String? hint,
    bool clearHint = false,
  }) {
    return ComicReaderViewState(
      comicId: comicId,
      episodeId: episodeId,
      comicTitle: comicTitle,
      episodeTitle: episodeTitle,
      sourceTid: sourceTid,
      images: images ?? this.images,
      chapters: chapters ?? this.chapters,
      currentImageIndex: currentImageIndex ?? this.currentImageIndex,
      lastScrollOffset: lastScrollOffset ?? this.lastScrollOffset,
      hasPreviousEpisode: hasPreviousEpisode ?? this.hasPreviousEpisode,
      hasNextEpisode: hasNextEpisode ?? this.hasNextEpisode,
      isCurrentEpisodeRead: isCurrentEpisodeRead ?? this.isCurrentEpisodeRead,
      isBookmarked: isBookmarked ?? this.isBookmarked,
      failedImageCount: failedImageCount ?? this.failedImageCount,
      cacheSummary: cacheSummary ?? this.cacheSummary,
      nextChapterPreload: nextChapterPreload ?? this.nextChapterPreload,
      isSwitchingEpisode: isSwitchingEpisode ?? this.isSwitchingEpisode,
      hint: clearHint ? null : (hint ?? this.hint),
    );
  }
}

final comicReaderControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ComicReaderController, ComicReaderViewState, ComicReaderArgs>(
      (args) => ComicReaderController(args),
    );

class ComicReaderController extends AsyncNotifier<ComicReaderViewState> {
  ComicReaderController(this._args);

  final ComicReaderArgs _args;
  static const ComicReaderChapterPreloadPolicy _chapterPreloadPolicy =
      ComicReaderChapterPreloadPolicy();
  static const ContinuousImagePrefetchCoordinator _prefetchCoordinator =
      ContinuousImagePrefetchCoordinator();
  late ComicRepository _repository;
  late ComicReaderService _readerService;
  late ComicDownloadService _downloadService;
  late ComicReadingStateWriter _readingStateWriter;
  late ImageCacheService _imageCacheService;
  late ComicReaderEventLogger _eventLogger;
  late ComicReaderFeatureFlags _featureFlags;
  late ComicReaderPreloadQueue _preloadQueue;
  Timer? _progressPersistDebounceTimer;
  int _persistVersion = 0;
  final Set<String> _completedEpisodeIds = <String>{};
  final Set<String> _completingEpisodeIds = <String>{};
  final Set<int> _visibleImageIndexes = <int>{};
  final Set<int> _resolvedImageIndexes = <int>{};
  int _lastPreloadCenterIndex = 0;
  late String _currentEpisodeId;
  Future<void>? _nextChapterPreloadFuture;
  DateTime? _openedAt;
  bool _firstImageVisibleLogged = false;

  String get _activeEpisodeId => _currentEpisodeId;

  /// Persists shared-session cache metadata without changing explicit
  /// download state or rebuilding the reader view.
  Future<void> recordPreparedReaderImage(
    ReaderImagePreparationRecord record,
  ) async {
    if (!ref.mounted || record.readerOwnerId != _activeEpisodeId) {
      return;
    }
    await _updateImageCacheMetadata(
      episodeId: record.readerOwnerId,
      imageUrl: record.sourceUrl,
      stableCacheKey: record.cacheKey,
      lastSourceUrl: record.sourceUrl,
      localPath: record.localPath,
      lastAccessedAt: DateTime.now(),
    );
  }

  @override
  FutureOr<ComicReaderViewState> build() async {
    // Read dependencies once during build to avoid accessing `ref` from
    // async continuations after provider disposal.
    _repository = ref.read(comicRepositoryProvider);
    _readerService = await ref.read(comicReaderServiceProvider.future);
    _downloadService = ref.read(comicDownloadServiceProvider);
    _readingStateWriter = ref.read(comicReadingStateWriterProvider);
    _imageCacheService = ref.read(imageCacheServiceProvider);
    _eventLogger = ref.read(comicReaderEventLoggerProvider);
    _featureFlags = ref.read(comicReaderFeatureFlagsProvider);
    _preloadQueue = ComicReaderPreloadQueue(
      runner: _runPreloadTask,
      onStart: _handlePreloadStart,
      onResult: _handlePreloadResult,
      onSnapshot: _logPreloadSnapshot,
    );
    _openedAt = DateTime.now();
    _currentEpisodeId = _args.episodeId;
    ref.onDispose(() {
      _progressPersistDebounceTimer?.cancel();
      _preloadQueue.dispose();
    });
    final viewState = await _loadState(episodeId: _currentEpisodeId);
    scheduleMicrotask(() {
      if (!ref.mounted) {
        return;
      }
      _enqueueInitialWindow(viewState.currentImageIndex, viewState.images);
    });
    return viewState;
  }

  Future<void> retryImage(String imageUrl) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final idx = current.images.indexWhere(
      (element) => element.imageUrl == imageUrl,
    );
    if (idx < 0) {
      return;
    }
    final task = _readerTaskForImage(
      current.images[idx],
      priority: ComicReaderPreloadPriority.retry,
      force: true,
    );
    if (task == null) {
      return;
    }
    await _enqueuePreloadTasks(
      <ComicReaderPreloadTask>[task],
      cancelOldWindow: false,
      hint: '图片已加入重试队列',
    );
  }

  Future<void> cacheCurrentEpisode() async {
    final current = state.value;
    if (current == null || current.images.isEmpty) {
      return;
    }
    _preloadQueue.cancelExcept(const <String>{});
    for (final image in current.images) {
      await _repository.updateEpisodeImageCacheStatus(
        episodeId: current.episodeId,
        imageUrl: image.imageUrl,
        cacheStatus: 'downloading',
      );
      final cacheResult = await _cacheReaderImage(image);
      final done = cacheResult.success;
      if (!ref.mounted) {
        return;
      }
      await _repository.updateEpisodeImageCacheStatus(
        episodeId: current.episodeId,
        imageUrl: image.imageUrl,
        cacheStatus: done ? 'done' : 'failed',
        cacheLocalPath: done ? cacheResult.localPath : null,
      );
      await _updateImageCacheMetadata(
        episodeId: current.episodeId,
        imageUrl: image.imageUrl,
        stableCacheKey: done ? cacheResult.cacheKey : image.cacheKey,
        lastSourceUrl: image.imageUrl,
        localPath: done ? cacheResult.localPath : null,
        bytes: done ? cacheResult.bytes : null,
        lastAccessedAt: done ? DateTime.now() : null,
      );
      final latest = state.value;
      if (latest != null) {
        final updatedImages = latest.images
            .map(
              (item) => item.imageUrl == image.imageUrl
                  ? item.copyWith(
                      cacheStatus: done ? 'done' : 'failed',
                      localPath: done ? cacheResult.localPath : null,
                      cacheLocalPath: done ? cacheResult.localPath : null,
                      failed: !done,
                    )
                  : item,
            )
            .toList(growable: false);
        state = AsyncData(
          latest.copyWith(
            images: updatedImages,
            failedImageCount: _countFailedImages(updatedImages),
            cacheSummary: _buildCacheSummary(updatedImages),
          ),
        );
      }
    }
    if (!ref.mounted) {
      return;
    }
    final latest = state.value ?? current;
    state = AsyncData(latest.copyWith(hint: '本话缓存完成'));
  }

  Future<void> cacheAllUnread() async {
    _preloadQueue.cancelExcept(const <String>{});
    final episodes = await _repository.getComicEpisodes(
      comicId: _args.comicId,
      descending: false,
    );
    final currentIndex = episodes.indexWhere(
      (e) => e.episodeId == _activeEpisodeId,
    );
    if (currentIndex < 0) {
      return;
    }
    final unread = episodes.skip(currentIndex).toList(growable: false);
    for (final episode in unread) {
      final images = await _ensureEpisodeImages(episode);
      if (!ref.mounted) {
        return;
      }
      for (final image in images) {
        await _repository.updateEpisodeImageCacheStatus(
          episodeId: episode.episodeId,
          imageUrl: image.imageUrl,
          cacheStatus: 'downloading',
        );
        final cacheResult = await _cacheEpisodeImage(image);
        final done = cacheResult.success;
        if (!ref.mounted) {
          return;
        }
        await _repository.updateEpisodeImageCacheStatus(
          episodeId: episode.episodeId,
          imageUrl: image.imageUrl,
          cacheStatus: done ? 'done' : 'failed',
          cacheLocalPath: done ? cacheResult.localPath : null,
        );
        await _updateImageCacheMetadata(
          episodeId: episode.episodeId,
          imageUrl: image.imageUrl,
          stableCacheKey: done ? cacheResult.cacheKey : image.stableCacheKey,
          lastSourceUrl: image.effectiveSourceUrl,
          localPath: done ? cacheResult.localPath : null,
          bytes: done ? cacheResult.bytes : null,
          lastAccessedAt: done ? DateTime.now() : null,
        );
        final latest = state.value;
        if (latest != null && latest.episodeId == episode.episodeId) {
          final updatedImages = latest.images
              .map(
                (item) => item.imageUrl == image.imageUrl
                    ? item.copyWith(
                        cacheStatus: done ? 'done' : 'failed',
                        localPath: done ? cacheResult.localPath : null,
                        cacheLocalPath: done ? cacheResult.localPath : null,
                        failed: !done,
                      )
                    : item,
              )
              .toList(growable: false);
          state = AsyncData(
            latest.copyWith(
              images: updatedImages,
              failedImageCount: _countFailedImages(updatedImages),
              cacheSummary: _buildCacheSummary(updatedImages),
            ),
          );
        }
      }
    }
    final nextState = await _loadState(episodeId: _activeEpisodeId);
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(nextState.copyWith(hint: '未读章节缓存完成'));
  }

  Future<void> retryFailedImages() async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final failedImages = current.images
        .where((image) => image.failed || image.cacheStatus == 'failed')
        .toList(growable: false);
    if (failedImages.isEmpty) {
      state = AsyncData(current.copyWith(hint: '没有需要重试的图片'));
      return;
    }
    for (final image in failedImages) {
      await retryImage(image.imageUrl);
      if (!ref.mounted) {
        return;
      }
    }
  }

  Future<void> clearCurrentEpisodeCache() async {
    final current = state.value;
    if (current == null) {
      return;
    }
    _preloadQueue.cancelExcept(const <String>{});
    await _repository.clearEpisodeImageCache(episodeId: current.episodeId);
    final clearedImages = current.images
        .map(
          (image) => image.copyWith(
            cacheStatus: 'none',
            failed: false,
            clearLocalPath: true,
            clearCacheLocalPath: true,
          ),
        )
        .toList(growable: false);
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        images: clearedImages,
        failedImageCount: 0,
        cacheSummary: _buildCacheSummary(clearedImages),
        hint: '本话缓存记录已清除',
      ),
    );
  }

  Future<void> toggleBookmark() async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final next = !current.isBookmarked;
    await _readingStateWriter.setEpisodeBookmarked(
      comicId: _args.comicId,
      episodeId: current.episodeId,
      isBookmarked: next,
    );
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(
      current.copyWith(isBookmarked: next, hint: next ? '已添加书签' : '已取消书签'),
    );
  }

  Future<void> setCurrentEpisodeRead(bool isRead) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    await _readingStateWriter.setEpisodeRead(
      comicId: _args.comicId,
      episodeId: current.episodeId,
      isRead: isRead,
    );
    if (isRead) {
      _completedEpisodeIds.add(current.episodeId);
    } else {
      _completedEpisodeIds.remove(current.episodeId);
    }
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        isCurrentEpisodeRead: isRead,
        chapters: _markChapterRead(
          current.chapters,
          episodeId: current.episodeId,
          isRead: isRead,
        ),
        hint: isRead ? '本章已标记为已读' : '本章已标记为未读',
      ),
    );
  }

  /// 为“设为封面”准备当前页的本地文件，供 UI 在焦点选区器里预览。
  ///
  /// 返回可读的本地路径（必要时先落盘缓存）；失败返回 null 并写入提示。
  /// 与 [setCurrentImageAsCover] 解耦：UI 先拿到图预览选焦点，再回调保存。
  Future<String?> prepareCurrentImageForCover() async {
    final current = state.value;
    final image = current?.currentImage;
    if (current == null || image == null) {
      return null;
    }
    final localPath = await _ensureCurrentImageLocalFile(image);
    if (localPath == null || localPath.trim().isEmpty) {
      if (!ref.mounted) {
        return null;
      }
      final latest = state.value ?? current;
      state = AsyncData(latest.copyWith(hint: '当前页图片缓存失败，无法设为封面'));
      return null;
    }
    return localPath;
  }

  Future<void> setCurrentImageAsCover({double? focusX, double? focusY}) async {
    final current = state.value;
    final image = current?.currentImage;
    if (current == null || image == null) {
      return;
    }

    state = AsyncData(current.copyWith(hint: '正在设置封面'));
    final localPath = await _ensureCurrentImageLocalFile(image);
    if (localPath == null || localPath.trim().isEmpty) {
      if (!ref.mounted) {
        return;
      }
      final latest = state.value ?? current;
      state = AsyncData(latest.copyWith(hint: '当前页图片缓存失败，无法设为封面'));
      return;
    }

    final result = await _imageCacheService.copyProtectedLocalFile(
      ImageCacheLocalCopyRequest(
        cacheKey: ImageCacheKeys.customCover(
          ownerType: ImageCacheOwnerType.comic.dbValue,
          ownerId: _args.comicId,
        ),
        sourcePath: localPath,
        ownerType: ImageCacheOwnerType.comic,
        ownerId: _args.comicId,
        role: ImageCacheRole.customCover,
        episodeId: current.episodeId,
        imageIndex: image.imageIndex,
      ),
    );
    final protectedPath = result.localPath?.trim();
    if (!result.success || protectedPath == null || protectedPath.isEmpty) {
      if (!ref.mounted) {
        return;
      }
      final latest = state.value ?? current;
      state = AsyncData(latest.copyWith(hint: '封面更新失败，请稍后重试'));
      return;
    }
    try {
      await _repository.updateCustomCoverFromLocalFile(
        comicId: _args.comicId,
        localCoverPath: protectedPath,
        sourceEpisodeId: current.episodeId,
        sourceImageIndex: image.imageIndex,
        sourceImageUrl: image.imageUrl,
        focusX: focusX,
        focusY: focusY,
      );
    } catch (_) {
      if (!ref.mounted) {
        return;
      }
      final latest = state.value ?? current;
      state = AsyncData(latest.copyWith(hint: '封面更新失败，请稍后重试'));
      return;
    }
    if (!ref.mounted) {
      return;
    }
    final latest = state.value ?? current;
    state = AsyncData(latest.copyWith(hint: '封面已更新'));
  }

  Future<void> onScrollProgress({
    required int currentIndex,
    required double scrollOffset,
  }) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    _recordVisiblePage(
      currentIndex: currentIndex,
      scrollOffset: scrollOffset,
      source: ComicReaderProgressSource.scroll,
    );
    state = AsyncData(
      current.copyWith(
        currentImageIndex: currentIndex,
        lastScrollOffset: scrollOffset,
      ),
    );
  }

  /// Phase-0 generic API for explicit index jump.
  ///
  /// UI is responsible for the actual scroll/page movement.
  /// Controller only persists and mirrors logical progress state.
  Future<void> jumpToImageIndex(int index, {double? scrollOffset}) async {
    final current = state.value;
    if (current == null || current.images.isEmpty) {
      return;
    }
    final clampedIndex = index.clamp(0, current.images.length - 1).toInt();
    final nextOffset = scrollOffset ?? current.lastScrollOffset;
    _cancelScheduledProgressPersistence();
    _visibleImageIndexes.add(clampedIndex);
    await _saveProgressNow(
      currentIndex: clampedIndex,
      scrollOffset: nextOffset,
      source: ComicReaderProgressSource.jump,
    );
    state = AsyncData(
      current.copyWith(
        currentImageIndex: clampedIndex,
        lastScrollOffset: nextOffset,
      ),
    );
    await _markEpisodeCompletedIfNeeded(
      currentIndex: clampedIndex,
      scrollOffset: nextOffset,
      source: ComicReaderProgressSource.jump,
    );
    unawaited(_enqueueJumpWindow(clampedIndex));
  }

  Future<bool> goToEpisode(String episodeId) async {
    final targetEpisodeId = episodeId.trim();
    if (targetEpisodeId.isEmpty || targetEpisodeId == _activeEpisodeId) {
      return false;
    }
    final current = state.value;
    if (current == null) {
      return false;
    }
    state = AsyncData(
      current.copyWith(
        isSwitchingEpisode: true,
        hint:
            current.nextChapterPreload.episodeId == targetEpisodeId &&
                current.nextChapterPreload.hasLoadedImageList
            ? '正在切换章节'
            : '正在加载章节',
      ),
    );
    _preloadQueue.cancelExcept(const <String>{});
    _cancelScheduledProgressPersistence();
    final previousPreloadCenterIndex = _lastPreloadCenterIndex;
    final previousVisibleImageIndexes = Set<int>.of(_visibleImageIndexes);
    final previousResolvedImageIndexes = Set<int>.of(_resolvedImageIndexes);
    final previousPreloadFuture = _nextChapterPreloadFuture;
    _currentEpisodeId = targetEpisodeId;
    _visibleImageIndexes.clear();
    _resolvedImageIndexes.clear();
    _lastPreloadCenterIndex = 0;
    _nextChapterPreloadFuture = null;
    _firstImageVisibleLogged = false;

    try {
      final nextState = await _loadState(episodeId: targetEpisodeId);
      if (!ref.mounted) {
        return false;
      }
      state = AsyncData(
        nextState.copyWith(
          isSwitchingEpisode: false,
          hint: '已切换到 ${nextState.episodeTitle}',
        ),
      );
      _logReaderEvent(
        'episode_switched',
        pageIndex: nextState.currentImageIndex,
        totalPages: nextState.images.length,
        extra: <String, Object?>{'targetEpisodeId': targetEpisodeId},
      );
      _enqueueInitialWindow(nextState.currentImageIndex, nextState.images);
      return true;
    } catch (error) {
      _currentEpisodeId = current.episodeId;
      _visibleImageIndexes
        ..clear()
        ..addAll(previousVisibleImageIndexes);
      _resolvedImageIndexes
        ..clear()
        ..addAll(previousResolvedImageIndexes);
      _lastPreloadCenterIndex = previousPreloadCenterIndex;
      _nextChapterPreloadFuture = previousPreloadFuture;
      if (!ref.mounted) {
        return false;
      }
      state = AsyncData(
        current.copyWith(isSwitchingEpisode: false, hint: '章节切换失败，请稍后重试'),
      );
      _logReaderEvent(
        'episode_switch_failed',
        extra: <String, Object?>{
          'targetEpisodeId': targetEpisodeId,
          'error': error,
        },
      );
      return false;
    }
  }

  /// Records that an image slot reached the reader viewport.
  ///
  /// This is intentionally separate from `_loadState`: single-page chapters
  /// should become read only after the page is actually visible, not merely
  /// because the chapter metadata was loaded.
  Future<void> onImageVisible(int imageIndex) async {
    final current = state.value;
    if (current == null || current.images.isEmpty) {
      return;
    }
    final clampedIndex = imageIndex.clamp(0, current.images.length - 1).toInt();
    _recordVisiblePage(
      currentIndex: clampedIndex,
      scrollOffset: current.lastScrollOffset,
      source: ComicReaderProgressSource.initialVisible,
      checkCompletion: false,
    );
    unawaited(_enqueueReadingWindow(clampedIndex));
    await _markEpisodeCompletedIfNeeded(
      currentIndex: clampedIndex,
      scrollOffset: current.lastScrollOffset,
      source: ComicReaderProgressSource.initialVisible,
    );
  }

  Future<void> onImageResolved({
    required int imageIndex,
    required String imageUrl,
    required int width,
    required int height,
  }) async {
    final current = state.value;
    if (current == null ||
        current.images.isEmpty ||
        width <= 0 ||
        height <= 0) {
      return;
    }
    final clampedIndex = imageIndex.clamp(0, current.images.length - 1).toInt();
    final image = current.images[clampedIndex];
    if (image.imageUrl != imageUrl) {
      return;
    }
    _resolvedImageIndexes.add(clampedIndex);
    if (!_firstImageVisibleLogged) {
      _firstImageVisibleLogged = true;
      _logReaderEvent(
        'first_image_visible',
        pageIndex: clampedIndex,
        totalPages: current.images.length,
        extra: <String, Object?>{'width': width, 'height': height},
      );
    }

    if (image.width == width &&
        image.height == height &&
        !image.failed &&
        image.cacheStatus != 'failed') {
      await _markEpisodeCompletedIfNeeded(
        currentIndex: clampedIndex,
        scrollOffset: current.lastScrollOffset,
        source: ComicReaderProgressSource.initialVisible,
      );
      return;
    }

    if (image.cacheStatus == 'failed') {
      await _repository.updateEpisodeImageCacheStatus(
        episodeId: current.episodeId,
        imageUrl: image.imageUrl,
        cacheStatus: 'none',
      );
    }
    await _updateImageCacheMetadata(
      episodeId: current.episodeId,
      imageUrl: image.imageUrl,
      stableCacheKey: image.cacheKey,
      lastSourceUrl: image.imageUrl,
      width: width,
      height: height,
      lastAccessedAt: DateTime.now(),
    );
    if (!ref.mounted) {
      return;
    }
    final latest = state.value;
    if (latest == null || latest.episodeId != current.episodeId) {
      return;
    }
    final updatedImages = latest.images
        .map(
          (item) => item.imageIndex == clampedIndex
              ? item.copyWith(
                  cacheStatus: item.cacheStatus == 'failed'
                      ? 'none'
                      : item.cacheStatus,
                  width: width,
                  height: height,
                  failed: false,
                )
              : item,
        )
        .toList(growable: false);
    state = AsyncData(
      latest.copyWith(
        images: updatedImages,
        failedImageCount: _countFailedImages(updatedImages),
        cacheSummary: _buildCacheSummary(updatedImages),
      ),
    );
    await _markEpisodeCompletedIfNeeded(
      currentIndex: clampedIndex,
      scrollOffset: latest.lastScrollOffset,
      source: ComicReaderProgressSource.initialVisible,
    );
  }

  Future<void> onImageDisplayFailed({
    required int imageIndex,
    required String imageUrl,
  }) async {
    final current = state.value;
    if (current == null || current.images.isEmpty) {
      return;
    }
    final clampedIndex = imageIndex.clamp(0, current.images.length - 1).toInt();
    final image = current.images[clampedIndex];
    if (image.imageUrl != imageUrl) {
      return;
    }
    await _repository.updateEpisodeImageCacheStatus(
      episodeId: current.episodeId,
      imageUrl: imageUrl,
      cacheStatus: 'failed',
      cacheLocalPath: null,
    );
    if (!ref.mounted) {
      return;
    }
    final latest = state.value;
    if (latest == null || latest.episodeId != current.episodeId) {
      return;
    }
    final updatedImages = latest.images
        .map(
          (item) => item.imageIndex == clampedIndex
              ? item.copyWith(
                  cacheStatus: 'failed',
                  failed: true,
                  clearLocalPath: true,
                  clearCacheLocalPath: true,
                )
              : item,
        )
        .toList(growable: false);
    state = AsyncData(
      latest.copyWith(
        images: updatedImages,
        failedImageCount: _countFailedImages(updatedImages),
        cacheSummary: _buildCacheSummary(updatedImages),
      ),
    );
    _logReaderEvent(
      'image_display_failed',
      pageIndex: clampedIndex,
      totalPages: latest.images.length,
      extra: <String, Object?>{'imageUrl': imageUrl},
    );
  }

  /// Flushes the latest progress when the reader is closed.
  Future<void> onExitReader() async {
    final current = state.value;
    if (current == null) {
      return;
    }
    _cancelScheduledProgressPersistence();
    await _saveProgressNow(
      currentIndex: current.currentImageIndex,
      scrollOffset: current.lastScrollOffset,
      source: ComicReaderProgressSource.exit,
    );
    _logReaderEvent(
      'exit',
      pageIndex: current.currentImageIndex,
      totalPages: current.images.length,
    );
  }

  void _scheduleProgressPersistence({
    required int currentIndex,
    required double scrollOffset,
    required ComicReaderProgressSource source,
  }) {
    _progressPersistDebounceTimer?.cancel();
    final version = ++_persistVersion;
    _progressPersistDebounceTimer = Timer(
      const Duration(milliseconds: 180),
      () async {
        await _saveProgressNow(
          currentIndex: currentIndex,
          scrollOffset: scrollOffset,
          source: source,
        );
        if (!ref.mounted || version != _persistVersion) {
          return;
        }
      },
    );
  }

  void _cancelScheduledProgressPersistence() {
    _progressPersistDebounceTimer?.cancel();
    _progressPersistDebounceTimer = null;
    _persistVersion++;
  }

  void _recordVisiblePage({
    required int currentIndex,
    required double scrollOffset,
    required ComicReaderProgressSource source,
    bool checkCompletion = true,
  }) {
    _visibleImageIndexes.add(currentIndex);
    unawaited(_enqueueReadingWindow(currentIndex));
    _scheduleProgressPersistence(
      currentIndex: currentIndex,
      scrollOffset: scrollOffset,
      source: source,
    );
    if (!checkCompletion) {
      return;
    }
    unawaited(
      _markEpisodeCompletedIfNeeded(
        currentIndex: currentIndex,
        scrollOffset: scrollOffset,
        source: source,
      ),
    );
  }

  Future<void> _saveProgressNow({
    required int currentIndex,
    required double scrollOffset,
    required ComicReaderProgressSource source,
  }) async {
    final startedAt = DateTime.now();
    await _readingStateWriter.saveProgress(
      comicId: _args.comicId,
      episodeId: _activeEpisodeId,
      imageIndex: currentIndex,
      scrollOffset: scrollOffset,
    );
    _logReaderEvent(
      'page_visible',
      source: source,
      pageIndex: currentIndex,
      scrollOffset: scrollOffset,
      elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
    );
  }

  Future<void> _markEpisodeCompletedIfNeeded({
    required int currentIndex,
    required double scrollOffset,
    required ComicReaderProgressSource source,
  }) async {
    final current = state.value;
    if (current == null || current.images.isEmpty) {
      return;
    }
    final lastIndex = current.images.length - 1;
    if (currentIndex < lastIndex) {
      return;
    }
    final episodeId = current.episodeId;
    if (_completedEpisodeIds.contains(episodeId)) {
      return;
    }
    if (_completingEpisodeIds.contains(episodeId)) {
      return;
    }
    final lastImage = current.images[lastIndex];
    if (lastImage.failed || lastImage.cacheStatus == 'failed') {
      return;
    }
    if (_featureFlags.readerStrictCompleteRead) {
      // Strict rollout mode requires a real viewport hit and decode callback.
      // This keeps preload/cache metadata from marking an unread chapter read.
      if (!_visibleImageIndexes.contains(lastIndex)) {
        return;
      }
      if (!_isImageResolvedInCurrentSession(lastIndex)) {
        return;
      }
    }

    final completedAt = DateTime.now();
    _completingEpisodeIds.add(episodeId);
    try {
      await _readingStateWriter.markEpisodeCompleted(
        comicId: _args.comicId,
        episodeId: episodeId,
        imageIndex: lastIndex,
        scrollOffset: scrollOffset,
        completedAt: completedAt,
      );
      _completedEpisodeIds.add(episodeId);
    } finally {
      _completingEpisodeIds.remove(episodeId);
    }
    if (!ref.mounted || _activeEpisodeId != episodeId) {
      return;
    }
    _logReaderEvent(
      'chapter_completed',
      source: source,
      pageIndex: lastIndex,
      totalPages: current.images.length,
      scrollOffset: scrollOffset,
    );
    final latest = state.value;
    if (latest == null) {
      return;
    }
    if (latest.episodeId != episodeId) {
      return;
    }
    state = AsyncData(
      latest.copyWith(
        currentImageIndex: lastIndex,
        lastScrollOffset: scrollOffset,
        isCurrentEpisodeRead: true,
        chapters: _markChapterRead(
          latest.chapters,
          episodeId: episodeId,
          isRead: true,
        ),
      ),
    );
  }

  void _enqueueInitialWindow(
    int centerIndex,
    List<ComicReaderImageState> images,
  ) {
    if (!_featureFlags.readerPreloadQueueEnabled) {
      return;
    }
    if (images.isEmpty) {
      return;
    }
    final plan = _prefetchCoordinator.windowForIndex(
      focusIndex: centerIndex,
      itemCount: images.length,
      policy: ContinuousImageFlowPolicy.comicVerticalReading,
    );
    final tasks = _buildWindowTasks(
      images,
      plan: plan,
      visiblePriority: ComicReaderPreloadPriority.visible,
      preferredDirection: ContinuousImageScrollDirection.forward,
    );
    unawaited(_enqueuePreloadTasks(tasks, cancelOldWindow: false));
  }

  Future<void> _enqueueReadingWindow(int centerIndex) async {
    if (!_featureFlags.readerPreloadQueueEnabled) {
      return;
    }
    final current = state.value;
    if (current == null || current.images.isEmpty) {
      return;
    }
    if (centerIndex == _lastPreloadCenterIndex &&
        _preloadQueue.snapshot.pendingCount > 0) {
      return;
    }
    final scrollDirection = centerIndex < _lastPreloadCenterIndex
        ? ContinuousImageScrollDirection.reverse
        : ContinuousImageScrollDirection.forward;
    _lastPreloadCenterIndex = centerIndex;
    final tasks = _buildDirectionalWindowTasks(
      current.images,
      centerIndex: centerIndex,
      scrollDirection: scrollDirection,
    );
    await _enqueuePreloadTasks(tasks, cancelOldWindow: false);
    if (_featureFlags.readerNextChapterPreloadEnabled &&
        _chapterPreloadPolicy.shouldPreloadNextChapter(
          currentImageIndex: centerIndex,
          totalImages: current.images.length,
        )) {
      unawaited(ensureNextChapterPreloaded());
    }
  }

  Future<void> _enqueueJumpWindow(int centerIndex) async {
    if (!_featureFlags.readerPreloadQueueEnabled) {
      return;
    }
    final current = state.value;
    if (current == null || current.images.isEmpty) {
      return;
    }
    _lastPreloadCenterIndex = centerIndex;
    final plan = _prefetchCoordinator.windowForIndex(
      focusIndex: centerIndex,
      itemCount: current.images.length,
      policy: ContinuousImageFlowPolicy.comicVerticalReading,
    );
    final tasks = _buildWindowTasks(
      current.images,
      plan: plan,
      visiblePriority: ComicReaderPreloadPriority.jumpTarget,
      preferredDirection: ContinuousImageScrollDirection.forward,
    );
    await _enqueuePreloadTasks(tasks, cancelOldWindow: true);
  }

  List<ComicReaderPreloadTask> _buildDirectionalWindowTasks(
    List<ComicReaderImageState> images, {
    required int centerIndex,
    required ContinuousImageScrollDirection scrollDirection,
  }) {
    final plan = _prefetchCoordinator.windowForIndex(
      focusIndex: centerIndex,
      itemCount: images.length,
      policy: ContinuousImageFlowPolicy.comicVerticalReading,
      scrollDirection: scrollDirection,
    );
    return _buildWindowTasks(
      images,
      plan: plan,
      visiblePriority: ComicReaderPreloadPriority.visible,
      preferredDirection: scrollDirection,
    );
  }

  List<ComicReaderPreloadTask> _buildWindowTasks(
    List<ComicReaderImageState> images, {
    required ContinuousImagePrefetchPlan plan,
    required ComicReaderPreloadPriority visiblePriority,
    required ContinuousImageScrollDirection preferredDirection,
  }) {
    final focusIndex = plan.focusIndex;
    if (focusIndex == null || images.isEmpty) {
      return const <ComicReaderPreloadTask>[];
    }
    final tasks = <ComicReaderPreloadTask>[];
    for (final index in plan.indices) {
      if (index < 0 || index >= images.length) {
        continue;
      }
      _addReaderTask(
        tasks,
        images[index],
        priority: _priorityForWindowIndex(
          index: index,
          focusIndex: focusIndex,
          visiblePriority: visiblePriority,
          preferredDirection: preferredDirection,
        ),
      );
    }
    return tasks;
  }

  ComicReaderPreloadPriority _priorityForWindowIndex({
    required int index,
    required int focusIndex,
    required ComicReaderPreloadPriority visiblePriority,
    required ContinuousImageScrollDirection preferredDirection,
  }) {
    if (index == focusIndex) {
      return visiblePriority;
    }
    if (preferredDirection == ContinuousImageScrollDirection.reverse) {
      return index < focusIndex
          ? ComicReaderPreloadPriority.adjacentForward
          : ComicReaderPreloadPriority.adjacentBackward;
    }
    if (index > focusIndex) {
      return ComicReaderPreloadPriority.adjacentForward;
    }
    return ComicReaderPreloadPriority.adjacentBackward;
  }

  Future<void> ensureNextChapterPreloaded({bool force = false}) {
    if (!_featureFlags.readerPreloadQueueEnabled ||
        !_featureFlags.readerNextChapterPreloadEnabled) {
      _logReaderEvent('next_chapter_preload_disabled');
      return Future<void>.value();
    }
    final current = state.value;
    if (current == null || !current.hasNextEpisode) {
      _patchNextChapterPreload(ComicReaderChapterPreloadState.unavailable());
      _logReaderEvent('next_chapter_unavailable');
      return Future<void>.value();
    }
    if (!force &&
        current.nextChapterPreload.status ==
            ComicReaderChapterPreloadStatus.ready) {
      return Future<void>.value();
    }
    final existing = _nextChapterPreloadFuture;
    if (!force && existing != null) {
      return existing;
    }
    final future = _preloadNextChapterFor(current);
    _nextChapterPreloadFuture = future;
    return future.whenComplete(() {
      if (identical(_nextChapterPreloadFuture, future)) {
        _nextChapterPreloadFuture = null;
      }
    });
  }

  void _patchNextChapterPreload(ComicReaderChapterPreloadState preloadState) {
    if (!ref.mounted) {
      return;
    }
    final current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncData(current.copyWith(nextChapterPreload: preloadState));
  }

  Future<void> _preloadNextChapterFor(ComicReaderViewState baseState) async {
    final episodes = await _repository.getComicEpisodes(
      comicId: _args.comicId,
      descending: false,
    );
    final currentIndex = episodes.indexWhere(
      (e) => e.episodeId == baseState.episodeId,
    );
    if (currentIndex < 0 || currentIndex + 1 >= episodes.length) {
      _patchNextChapterPreload(ComicReaderChapterPreloadState.unavailable());
      _logReaderEvent('next_chapter_unavailable');
      return;
    }
    if (!ref.mounted || _activeEpisodeId != baseState.episodeId) {
      return;
    }
    final nextEpisode = episodes[currentIndex + 1];
    final nextEpisodeState = ComicReaderChapterPreloadState.idle(nextEpisode);
    _patchNextChapterPreload(
      nextEpisodeState.copyWith(
        status: ComicReaderChapterPreloadStatus.loadingImages,
        message: '正在预加载下一章',
      ),
    );
    _logReaderEvent(
      'next_chapter_preload_start',
      extra: <String, Object?>{
        'nextEpisodeId': nextEpisode.episodeId,
        'sourceTid': nextEpisode.sourceTid,
      },
    );
    List<ComicEpisodeImageItem> images;
    try {
      images = await _ensureEpisodeImages(nextEpisode);
    } catch (error) {
      if (!ref.mounted || _activeEpisodeId != baseState.episodeId) {
        return;
      }
      _patchNextChapterPreload(
        nextEpisodeState.copyWith(
          status: ComicReaderChapterPreloadStatus.failed,
          message: '下一章预加载失败',
        ),
      );
      _logReaderEvent(
        'next_chapter_preload_failed',
        extra: <String, Object?>{
          'nextEpisodeId': nextEpisode.episodeId,
          'error': error,
        },
      );
      return;
    }
    if (!ref.mounted || _activeEpisodeId != baseState.episodeId) {
      return;
    }
    if (images.isEmpty) {
      _patchNextChapterPreload(
        nextEpisodeState.copyWith(
          status: ComicReaderChapterPreloadStatus.failed,
          message: '下一章图片列表为空',
        ),
      );
      return;
    }
    _patchNextChapterPreload(
      nextEpisodeState.copyWith(
        status: ComicReaderChapterPreloadStatus.imagesReady,
        imageCount: images.length,
        firstPageCacheStatus: images.first.cacheStatus,
        clearMessage: true,
      ),
    );
    final limit = _chapterPreloadPolicy.firstPageWindowLength(images.length);
    final tasks = <ComicReaderPreloadTask>[];
    for (var i = 0; i < limit; i++) {
      _addEpisodeTask(
        tasks,
        images[i],
        priority: ComicReaderPreloadPriority.nextChapter,
      );
    }
    if (tasks.isEmpty) {
      _patchNextChapterPreload(
        nextEpisodeState.copyWith(
          status: ComicReaderChapterPreloadStatus.ready,
          imageCount: images.length,
          cachedPageCount: limit,
          firstPageCacheStatus: images.first.cacheStatus,
          message: '下一章已准备好',
        ),
      );
      _logReaderEvent(
        'next_chapter_preload_ready',
        extra: <String, Object?>{
          'nextEpisodeId': nextEpisode.episodeId,
          'imageCount': images.length,
          'cachedPages': limit,
          'fromCache': true,
        },
      );
      return;
    }
    _patchNextChapterPreload(
      nextEpisodeState.copyWith(
        status: ComicReaderChapterPreloadStatus.preloadingPages,
        imageCount: images.length,
        firstPageCacheStatus: images.first.cacheStatus,
        clearMessage: true,
      ),
    );
    await _enqueuePreloadTasks(tasks, cancelOldWindow: false);
    if (!ref.mounted || _activeEpisodeId != baseState.episodeId) {
      return;
    }
    _logReaderEvent(
      'next_chapter_preload_queued',
      extra: <String, Object?>{
        'nextEpisodeId': nextEpisode.episodeId,
        'imageCount': images.length,
        'targetCachedPages': limit,
      },
    );
  }

  Future<void> _enqueuePreloadTasks(
    List<ComicReaderPreloadTask> tasks, {
    required bool cancelOldWindow,
    String? hint,
  }) async {
    if (!_featureFlags.readerPreloadQueueEnabled) {
      return;
    }
    if (tasks.isEmpty) {
      return;
    }
    if (cancelOldWindow) {
      _preloadQueue.cancelExcept(tasks.map((task) => task.dedupeKey).toSet());
      _logReaderEvent(
        'preload_window_cancelled',
        extra: <String, Object?>{'keep': tasks.length, 'reason': 'jump_window'},
      );
    }
    final accepted = _preloadQueue.enqueueAll(tasks, schedule: false);
    if (accepted.isEmpty && hint == null) {
      return;
    }
    for (final task in accepted) {
      await _repository.updateEpisodeImageCacheStatus(
        episodeId: task.episodeId,
        imageUrl: task.storageImageUrl,
        cacheStatus: 'queued',
      );
    }
    if (!ref.mounted) {
      return;
    }
    _patchCurrentEpisodeImageStates(
      accepted,
      cacheStatus: 'queued',
      failed: false,
      hint: hint,
      clearHint: hint == null,
    );
    _patchNextChapterQueuedTasks(accepted);
    _preloadQueue.schedule();
  }

  void _addReaderTask(
    List<ComicReaderPreloadTask> tasks,
    ComicReaderImageState image, {
    required ComicReaderPreloadPriority priority,
  }) {
    final task = _readerTaskForImage(image, priority: priority);
    if (task != null) {
      tasks.add(task);
    }
  }

  void _addEpisodeTask(
    List<ComicReaderPreloadTask> tasks,
    ComicEpisodeImageItem image, {
    required ComicReaderPreloadPriority priority,
  }) {
    final task = _episodeTaskForImage(image, priority: priority);
    if (task != null) {
      tasks.add(task);
    }
  }

  ComicReaderPreloadTask? _readerTaskForImage(
    ComicReaderImageState image, {
    required ComicReaderPreloadPriority priority,
    bool force = false,
  }) {
    // Once a page failed in the display layer, keep it stable until the user
    // explicitly retries. Background windows should not silently overwrite the
    // failure state and make the page look recoverable before it renders again.
    if (!force && (image.failed || image.cacheStatus == 'failed')) {
      return null;
    }
    if (!force &&
        (_isDownloadedReaderImage(image) || image.hasCachedLocalFile)) {
      return null;
    }
    final current = state.value;
    final episodeId = current?.episodeId ?? _activeEpisodeId;
    return ComicReaderPreloadTask(
      episodeId: episodeId,
      imageUrl: image.imageUrl,
      storageImageUrl: image.imageUrl,
      imageIndex: image.imageIndex,
      cacheKey: image.cacheKey ?? _stableKeyForIndex(image.imageIndex),
      priority: priority,
      ownerId: _args.comicId,
      lastSourceUrl: image.imageUrl,
    );
  }

  ComicReaderPreloadTask? _episodeTaskForImage(
    ComicEpisodeImageItem image, {
    required ComicReaderPreloadPriority priority,
  }) {
    if (_isDownloadedEpisodeImage(image) ||
        (image.cacheStatus == 'done' && image.effectiveLocalPath != null)) {
      return null;
    }
    return ComicReaderPreloadTask(
      episodeId: image.episodeId,
      imageUrl: image.effectiveSourceUrl,
      storageImageUrl: image.imageUrl,
      imageIndex: image.imageIndex,
      cacheKey: _stableKeyForEpisodeImage(image),
      priority: priority,
      ownerId: _args.comicId,
      lastSourceUrl: image.effectiveSourceUrl,
    );
  }

  Future<ComicImageCacheResult> _runPreloadTask(ComicReaderPreloadTask task) {
    return _readerService.cacheImage(
      imageUrl: task.imageUrl,
      cacheKey: task.cacheKey,
      ownerType: ImageCacheOwnerType.comic,
      ownerId: task.ownerId ?? _args.comicId,
      role: ImageCacheRole.comicPage,
      episodeId: task.episodeId,
      imageIndex: task.imageIndex,
    );
  }

  Future<void> _handlePreloadStart(ComicReaderPreloadTask task) async {
    if (!ref.mounted) {
      return;
    }
    if (_isBlockedByDisplayFailure(task)) {
      return;
    }
    await _repository.updateEpisodeImageCacheStatus(
      episodeId: task.episodeId,
      imageUrl: task.storageImageUrl,
      cacheStatus: 'downloading',
    );
    _patchCurrentEpisodeImageStates(
      <ComicReaderPreloadTask>[task],
      cacheStatus: 'downloading',
      failed: false,
      clearHint: true,
    );
    final current = state.value;
    if (current != null &&
        current.nextChapterPreload.episodeId == task.episodeId) {
      state = AsyncData(
        current.copyWith(
          nextChapterPreload: current.nextChapterPreload.copyWith(
            status: ComicReaderChapterPreloadStatus.preloadingPages,
            firstPageCacheStatus: task.imageIndex == 0
                ? 'downloading'
                : current.nextChapterPreload.firstPageCacheStatus,
            clearMessage: true,
          ),
        ),
      );
    }
  }

  Future<void> _handlePreloadResult(
    ComicReaderPreloadResult preloadResult,
  ) async {
    final task = preloadResult.task;
    final cacheResult = preloadResult.cacheResult;
    final done = cacheResult.success;
    final localPath = done ? cacheResult.localPath : null;
    if (!ref.mounted) {
      return;
    }
    if (_isBlockedByDisplayFailure(task)) {
      return;
    }
    await _repository.updateEpisodeImageCacheStatus(
      episodeId: task.episodeId,
      imageUrl: task.storageImageUrl,
      cacheStatus: done ? 'done' : 'failed',
      cacheLocalPath: localPath,
    );
    await _updateImageCacheMetadata(
      episodeId: task.episodeId,
      imageUrl: task.storageImageUrl,
      stableCacheKey: cacheResult.cacheKey ?? task.cacheKey,
      lastSourceUrl: task.lastSourceUrl ?? task.imageUrl,
      localPath: localPath,
      bytes: done ? cacheResult.bytes : null,
      lastAccessedAt: done ? DateTime.now() : null,
    );
    _patchCurrentEpisodeImageStates(
      <ComicReaderPreloadTask>[task],
      cacheStatus: done ? 'done' : 'failed',
      localPath: localPath,
      cacheLocalPath: localPath,
      failed: !done,
      hint: task.priority == ComicReaderPreloadPriority.retry
          ? (done ? '图片重试成功' : '图片重试失败')
          : null,
      clearHint: task.priority != ComicReaderPreloadPriority.retry,
    );
    _logReaderEvent(
      done ? 'preload_success' : 'preload_failed',
      pageIndex: task.imageIndex,
      extra: <String, Object?>{
        'priority': task.priority.name,
        'episodeId': task.episodeId,
        'fromCache': cacheResult.fromCache,
        'bytes': cacheResult.bytes,
      },
    );
    _logReaderEvent(
      cacheResult.fromCache ? 'image_cache_hit' : 'image_cache_miss',
      pageIndex: task.imageIndex,
      extra: <String, Object?>{
        'priority': task.priority.name,
        'episodeId': task.episodeId,
      },
    );
    _patchNextChapterTaskResult(task: task, done: done);
  }

  void _patchCurrentEpisodeImageStates(
    List<ComicReaderPreloadTask> tasks, {
    required String cacheStatus,
    String? localPath,
    String? cacheLocalPath,
    bool? failed,
    String? hint,
    bool clearHint = false,
  }) {
    final current = state.value;
    if (current == null || tasks.isEmpty) {
      return;
    }
    final byIndex = {
      for (final task in tasks.where(
        (task) => task.episodeId == current.episodeId,
      ))
        task.imageIndex: task,
    };
    if (byIndex.isEmpty) {
      return;
    }
    final patched = current.images
        .map((image) {
          final task = byIndex[image.imageIndex];
          if (task == null) {
            return image;
          }
          if (image.cacheStatus == 'downloaded') {
            return image;
          }
          if ((image.failed || image.cacheStatus == 'failed') &&
              task.priority != ComicReaderPreloadPriority.retry &&
              cacheStatus != 'failed') {
            return image;
          }
          return image.copyWith(
            cacheStatus: cacheStatus,
            localPath: localPath,
            cacheLocalPath: cacheLocalPath,
            failed: failed,
          );
        })
        .toList(growable: false);
    state = AsyncData(
      current.copyWith(
        images: patched,
        failedImageCount: _countFailedImages(patched),
        cacheSummary: _buildCacheSummary(patched),
        hint: hint,
        clearHint: clearHint,
      ),
    );
  }

  void _patchNextChapterQueuedTasks(List<ComicReaderPreloadTask> tasks) {
    final current = state.value;
    if (current == null || tasks.isEmpty) {
      return;
    }
    final preload = current.nextChapterPreload;
    final nextEpisodeId = preload.episodeId;
    if (nextEpisodeId == null) {
      return;
    }
    final queued = tasks
        .where((task) => task.episodeId == nextEpisodeId)
        .length;
    if (queued == 0) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        nextChapterPreload: preload.copyWith(
          status: ComicReaderChapterPreloadStatus.preloadingPages,
          firstPageCacheStatus: 'queued',
          clearMessage: true,
        ),
      ),
    );
  }

  void _patchNextChapterTaskResult({
    required ComicReaderPreloadTask task,
    required bool done,
  }) {
    if (task.priority != ComicReaderPreloadPriority.nextChapter) {
      return;
    }
    final current = state.value;
    if (current == null) {
      return;
    }
    final preload = current.nextChapterPreload;
    if (preload.episodeId != task.episodeId) {
      return;
    }
    if (preload.status == ComicReaderChapterPreloadStatus.ready) {
      return;
    }
    final targetCachedCount = _chapterPreloadPolicy.firstPageWindowLength(
      preload.imageCount,
    );
    final cachedPageCount = done
        ? (preload.cachedPageCount + 1).clamp(0, targetCachedCount).toInt()
        : preload.cachedPageCount;
    final ready = targetCachedCount > 0 && cachedPageCount >= targetCachedCount;
    final firstPageFailed = task.imageIndex == 0 && !done;
    state = AsyncData(
      current.copyWith(
        nextChapterPreload: preload.copyWith(
          status: ready
              ? ComicReaderChapterPreloadStatus.ready
              : (firstPageFailed
                    ? ComicReaderChapterPreloadStatus.failed
                    : ComicReaderChapterPreloadStatus.preloadingPages),
          cachedPageCount: cachedPageCount,
          firstPageCacheStatus: task.imageIndex == 0
              ? (done ? 'done' : 'failed')
              : preload.firstPageCacheStatus,
          message: ready ? '下一章已准备好' : (firstPageFailed ? '下一章首图预加载失败' : null),
          clearMessage: !ready && !firstPageFailed,
        ),
      ),
    );
    if (ready && preload.status != ComicReaderChapterPreloadStatus.ready) {
      _logReaderEvent(
        'next_chapter_preload_ready',
        extra: <String, Object?>{
          'nextEpisodeId': task.episodeId,
          'cachedPages': cachedPageCount,
        },
      );
    }
  }

  void _logPreloadSnapshot(ComicReaderPreloadQueueSnapshot snapshot) {
    _logReaderEvent(
      'preload_queue',
      extra: <String, Object?>{
        'pending': snapshot.pendingCount,
        'running': snapshot.runningCount,
        'success': snapshot.successCount,
        'failed': snapshot.failureCount,
        'cancelled': snapshot.cancelledCount,
      },
    );
  }

  Future<String?> _ensureCurrentImageLocalFile(
    ComicReaderImageState image,
  ) async {
    final episodeId = state.value?.episodeId ?? _activeEpisodeId;
    final existing = image.effectiveLocalPath?.trim();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final result = await _cacheReaderImage(image);
    if (!result.success) {
      return null;
    }
    final localPath = result.localPath?.trim();
    if (localPath == null || localPath.isEmpty) {
      return null;
    }
    await _repository.updateEpisodeImageCacheStatus(
      episodeId: episodeId,
      imageUrl: image.imageUrl,
      cacheStatus: 'done',
      cacheLocalPath: localPath,
    );
    await _updateImageCacheMetadata(
      episodeId: episodeId,
      imageUrl: image.imageUrl,
      stableCacheKey: result.cacheKey ?? image.cacheKey,
      lastSourceUrl: image.imageUrl,
      localPath: localPath,
      bytes: result.bytes,
      lastAccessedAt: DateTime.now(),
    );
    if (!ref.mounted) {
      return localPath;
    }
    final current = state.value;
    if (current == null) {
      return localPath;
    }
    final images = [...current.images];
    final idx = images.indexWhere(
      (item) => item.imageIndex == image.imageIndex,
    );
    if (idx >= 0) {
      images[idx] = images[idx].copyWith(
        cacheStatus: 'done',
        localPath: localPath,
        cacheLocalPath: localPath,
        failed: false,
      );
      state = AsyncData(
        current.copyWith(
          images: images,
          failedImageCount: _countFailedImages(images),
          cacheSummary: _buildCacheSummary(images),
        ),
      );
    }
    return localPath;
  }

  /// Returns previous episode id if available.
  Future<String?> goToPreviousEpisode() async {
    final episodes = await _repository.getComicEpisodes(
      comicId: _args.comicId,
      descending: false,
    );
    final currentIndex = episodes.indexWhere(
      (e) => e.episodeId == _activeEpisodeId,
    );
    if (currentIndex <= 0) {
      return null;
    }
    return episodes[currentIndex - 1].episodeId;
  }

  /// Returns next episode id if available.
  Future<String?> goToNextEpisode() async {
    final episodes = await _repository.getComicEpisodes(
      comicId: _args.comicId,
      descending: false,
    );
    final currentIndex = episodes.indexWhere(
      (e) => e.episodeId == _activeEpisodeId,
    );
    if (currentIndex < 0 || currentIndex + 1 >= episodes.length) {
      return null;
    }
    return episodes[currentIndex + 1].episodeId;
  }

  Future<ComicReaderViewState> _loadState({required String episodeId}) async {
    final startedAt = DateTime.now();
    final episodes = await _repository.getComicEpisodes(
      comicId: _args.comicId,
      descending: false,
    );
    final episodeIndex = episodes.indexWhere((e) => e.episodeId == episodeId);
    if (episodeIndex < 0) {
      throw StateError('章节不存在');
    }
    final episode = episodes[episodeIndex];
    final images = await _ensureEpisodeImages(episode);
    if (!ref.mounted) {
      throw StateError('阅读器已销毁');
    }
    final progress = await _repository.getLastReadProgress(
      comicId: _args.comicId,
    );
    final currentImageIndex =
        progress != null && progress.episodeId == episodeId
        ? progress.imageIndex
              .clamp(0, images.isEmpty ? 0 : images.length - 1)
              .toInt()
        : 0;
    final scrollOffset = progress != null && progress.episodeId == episodeId
        ? progress.scrollOffset
        : 0.0;
    final isRead = await _readingStateWriter.isEpisodeRead(
      comicId: _args.comicId,
      episodeId: episodeId,
    );
    final isBookmarked = await _readingStateWriter.isEpisodeBookmarked(
      comicId: _args.comicId,
      episodeId: episodeId,
    );
    if (isRead) {
      _completedEpisodeIds.add(episodeId);
    }

    final detail = await _repository.getComicDetail(comicId: _args.comicId);
    final imageStates = images
        .map(
          (image) => ComicReaderImageState(
            imageUrl: image.imageUrl,
            imageIndex: image.imageIndex,
            cacheStatus: image.cacheStatus,
            cacheKey: _stableKeyForEpisodeImage(image),
            localPath: image.effectiveLocalPath,
            cacheLocalPath: image.cacheLocalPath,
            width: image.width,
            height: image.height,
            failed: image.cacheStatus == 'failed',
          ),
        )
        .toList(growable: false);
    final chapters = <ComicReaderChapterEntry>[];
    for (final item in episodes) {
      final read = await _readingStateWriter.isEpisodeRead(
        comicId: _args.comicId,
        episodeId: item.episodeId,
      );
      chapters.add(
        ComicReaderChapterEntry(
          episodeId: item.episodeId,
          title: item.episodeTitle ?? '章节 ${item.sourceTid}',
          orderIndex: item.orderIndex,
          sourceTid: item.sourceTid,
          isCurrent: item.episodeId == episodeId,
          isRead: read,
        ),
      );
    }

    final viewState = ComicReaderViewState(
      comicId: _args.comicId,
      episodeId: episodeId,
      comicTitle: detail?.title ?? '漫画',
      episodeTitle: episode.episodeTitle ?? '章节 ${episode.sourceTid}',
      sourceTid: episode.sourceTid,
      images: imageStates,
      chapters: List<ComicReaderChapterEntry>.unmodifiable(chapters),
      currentImageIndex: currentImageIndex,
      lastScrollOffset: scrollOffset,
      hasPreviousEpisode: episodeIndex > 0,
      hasNextEpisode: episodeIndex < episodes.length - 1,
      isCurrentEpisodeRead: isRead,
      isBookmarked: isBookmarked,
      failedImageCount: _countFailedImages(imageStates),
      cacheSummary: _buildCacheSummary(imageStates),
      nextChapterPreload: episodeIndex < episodes.length - 1
          ? ComicReaderChapterPreloadState.idle(episodes[episodeIndex + 1])
          : ComicReaderChapterPreloadState.unavailable(),
    );
    _logReaderEvent(
      'open',
      pageIndex: currentImageIndex,
      totalPages: viewState.images.length,
      elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
    );
    return viewState;
  }

  Future<List<ComicEpisodeImageItem>> _ensureEpisodeImages(
    ComicEpisodeItem episode,
  ) async {
    final downloaded = await _downloadService.getDownloadedEpisodeImages(
      comicId: _args.comicId,
      episodeId: episode.episodeId,
    );
    if (downloaded.isNotEmpty) {
      return downloaded;
    }

    var images = await _repository.getEpisodeImages(
      episodeId: episode.episodeId,
    );
    if (images.isNotEmpty) {
      return images;
    }
    final fetchResult = await _readerService.fetchEpisodeImages(
      episode.sourceTid,
    );
    switch (fetchResult) {
      case ComicEpisodeImagesFetchFailed(:final reason, :final message):
        // 让 AsyncValue 进入 error 态，UI 渲染重试入口；不再把瞬时网络错
        // 误悄悄塞成"当前章节没有可阅读图片"。
        throw ComicEpisodeImagesUnavailable(reason: reason, message: message);
      case ComicEpisodeImagesFetched(:final imageUrls):
        if (imageUrls.isEmpty) {
          // 真没图：合法空态。
          return const <ComicEpisodeImageItem>[];
        }
        // 落库是副作用，跟 controller 生命周期解耦——哪怕用户在动画里返
        // 回了，下次进入也能直接命中 DB，不用再发一次 viewthread。
        await _repository.saveEpisodeImages(
          episodeId: episode.episodeId,
          imageUrls: imageUrls,
        );
        if (!ref.mounted) {
          return const <ComicEpisodeImageItem>[];
        }
        return _repository.getEpisodeImages(episodeId: episode.episodeId);
    }
  }

  Future<ComicImageCacheResult> _cacheReaderImage(ComicReaderImageState image) {
    if (_isDownloadedReaderImage(image) || image.hasCachedLocalFile) {
      return Future<ComicImageCacheResult>.value(
        ComicImageCacheResult(
          success: true,
          localPath: image.effectiveLocalPath,
          cacheKey: image.cacheKey,
          fromCache: true,
        ),
      );
    }
    final key = image.cacheKey ?? _stableKeyForIndex(image.imageIndex);
    return _readerService.cacheImage(
      imageUrl: image.imageUrl,
      cacheKey: key,
      ownerType: ImageCacheOwnerType.comic,
      ownerId: _args.comicId,
      role: ImageCacheRole.comicPage,
      episodeId: _activeEpisodeId,
      imageIndex: image.imageIndex,
    );
  }

  Future<ComicImageCacheResult> _cacheEpisodeImage(
    ComicEpisodeImageItem image,
  ) {
    if (_isDownloadedEpisodeImage(image)) {
      return Future<ComicImageCacheResult>.value(
        ComicImageCacheResult(
          success: true,
          localPath: image.effectiveLocalPath,
          cacheKey: image.stableCacheKey,
          bytes: image.bytes,
          fromCache: true,
        ),
      );
    }
    if (image.cacheStatus == 'done' && image.effectiveLocalPath != null) {
      return Future<ComicImageCacheResult>.value(
        ComicImageCacheResult(
          success: true,
          localPath: image.effectiveLocalPath,
          cacheKey: image.stableCacheKey,
          bytes: image.bytes,
          fromCache: true,
        ),
      );
    }
    final key = _stableKeyForEpisodeImage(image);
    return _readerService.cacheImage(
      imageUrl: image.effectiveSourceUrl,
      cacheKey: key,
      ownerType: ImageCacheOwnerType.comic,
      ownerId: _args.comicId,
      role: ImageCacheRole.comicPage,
      episodeId: image.episodeId,
      imageIndex: image.imageIndex,
    );
  }

  bool _isDownloadedReaderImage(ComicReaderImageState image) {
    return image.cacheStatus == 'downloaded' &&
        image.effectiveLocalPath != null;
  }

  bool _isDownloadedEpisodeImage(ComicEpisodeImageItem image) {
    return image.cacheStatus == 'downloaded' &&
        image.effectiveLocalPath != null;
  }

  bool _isImageResolvedInCurrentSession(int imageIndex) {
    return _resolvedImageIndexes.contains(imageIndex);
  }

  bool _isBlockedByDisplayFailure(ComicReaderPreloadTask task) {
    if (task.priority == ComicReaderPreloadPriority.retry) {
      return false;
    }
    final current = state.value;
    if (current == null || current.episodeId != task.episodeId) {
      return false;
    }
    for (final image in current.images) {
      if (image.imageIndex == task.imageIndex) {
        return image.failed || image.cacheStatus == 'failed';
      }
    }
    return false;
  }

  int _countFailedImages(List<ComicReaderImageState> images) {
    return images
        .where((image) => image.failed || image.cacheStatus == 'failed')
        .length;
  }

  ComicReaderCacheSummary _buildCacheSummary(
    List<ComicReaderImageState> images,
  ) {
    var done = 0;
    var downloaded = 0;
    var failed = 0;
    for (final image in images) {
      if (image.cacheStatus == 'downloaded') {
        downloaded++;
      } else if (image.hasCachedLocalFile) {
        done++;
      } else if (image.failed || image.cacheStatus == 'failed') {
        failed++;
      }
    }
    return ComicReaderCacheSummary(
      totalCount: images.length,
      doneCount: done,
      downloadedCount: downloaded,
      failedCount: failed,
    );
  }

  List<ComicReaderChapterEntry> _markChapterRead(
    List<ComicReaderChapterEntry> chapters, {
    required String episodeId,
    required bool isRead,
  }) {
    return chapters
        .map(
          (chapter) => chapter.episodeId == episodeId
              ? ComicReaderChapterEntry(
                  episodeId: chapter.episodeId,
                  title: chapter.title,
                  orderIndex: chapter.orderIndex,
                  sourceTid: chapter.sourceTid,
                  isCurrent: chapter.isCurrent,
                  isRead: isRead,
                )
              : chapter,
        )
        .toList(growable: false);
  }

  String _stableKeyForEpisodeImage(ComicEpisodeImageItem image) {
    final key = image.stableCacheKey?.trim();
    if (key != null && key.isNotEmpty) {
      return key;
    }
    return ImageCacheKeys.comicPage(
      comicId: _args.comicId,
      episodeId: image.episodeId,
      imageIndex: image.imageIndex,
    );
  }

  String _stableKeyForIndex(int imageIndex) {
    return ImageCacheKeys.comicPage(
      comicId: _args.comicId,
      episodeId: _activeEpisodeId,
      imageIndex: imageIndex,
    );
  }

  Future<void> _updateImageCacheMetadata({
    required String episodeId,
    required String imageUrl,
    String? stableCacheKey,
    String? lastSourceUrl,
    String? localPath,
    int? width,
    int? height,
    int? bytes,
    DateTime? lastAccessedAt,
  }) async {
    if (_repository is! ComicEpisodeImageCacheMetadataWriter) {
      return;
    }
    final writer = _repository as ComicEpisodeImageCacheMetadataWriter;
    await writer.updateEpisodeImageCacheMetadata(
      episodeId: episodeId,
      imageUrl: imageUrl,
      stableCacheKey: stableCacheKey,
      lastSourceUrl: lastSourceUrl,
      localPath: localPath,
      width: width,
      height: height,
      bytes: bytes,
      lastAccessedAt: lastAccessedAt,
      protected: false,
    );
  }

  void _logReaderEvent(
    String event, {
    ComicReaderProgressSource? source,
    int? pageIndex,
    int? totalPages,
    double? scrollOffset,
    int? elapsedMs,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    final openedAt = _openedAt;
    _eventLogger.log(
      event: event,
      comicId: _args.comicId,
      episodeId: _activeEpisodeId,
      source: source,
      pageIndex: pageIndex,
      totalPages: totalPages,
      scrollOffset: scrollOffset,
      elapsedMs: elapsedMs,
      sinceOpenMs: openedAt == null
          ? null
          : DateTime.now().difference(openedAt).inMilliseconds,
      extra: extra,
    );
  }
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/cache/domain/image_cache_keys.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/comic/data/comic_download_service.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/services/comic_reader_events.dart';
import 'package:y300/features/comic/domain/services/comic_reading_state_writer.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';

class ComicReaderArgs {
  const ComicReaderArgs({
    required this.comicId,
    required this.episodeId,
  });

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
    this.failed = false,
  });

  final String imageUrl;
  final int imageIndex;
  final String cacheStatus;
  final String? cacheKey;
  final String? localPath;
  final String? cacheLocalPath;
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
      cacheLocalPath: clearCacheLocalPath ? null : (cacheLocalPath ?? this.cacheLocalPath),
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
  late final ComicRepository _repository;
  late final ComicReaderService _readerService;
  late final ComicDownloadService _downloadService;
  late final ComicReadingStateWriter _readingStateWriter;
  late final ImageCacheService _imageCacheService;
  late final ComicCoverCacheWriter? _coverCacheWriter;
  late final ComicReaderEventLogger _eventLogger;
  Timer? _progressPersistDebounceTimer;
  int _persistVersion = 0;
  final Set<String> _completedEpisodeIds = <String>{};
  final Set<String> _completingEpisodeIds = <String>{};
  final Set<int> _visibleImageIndexes = <int>{};
  DateTime? _openedAt;

  @override
  FutureOr<ComicReaderViewState> build() async {
    // Read dependencies once during build to avoid accessing `ref` from
    // async continuations after provider disposal.
    _repository = ref.read(comicRepositoryProvider);
    _readerService = await ref.read(comicReaderServiceProvider.future);
    _downloadService = ref.read(comicDownloadServiceProvider);
    _readingStateWriter = ref.read(comicReadingStateWriterProvider);
    _imageCacheService = ref.read(imageCacheServiceProvider);
    _coverCacheWriter = _repository is ComicCoverCacheWriter
        ? _repository as ComicCoverCacheWriter
        : ref.read(comicCoverCacheWriterProvider);
    _eventLogger = ref.read(comicReaderEventLoggerProvider);
    _openedAt = DateTime.now();
    ref.onDispose(() {
      _progressPersistDebounceTimer?.cancel();
    });
    return _loadState();
  }

  Future<void> retryImage(String imageUrl) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    final idx = current.images.indexWhere((element) => element.imageUrl == imageUrl);
    if (idx < 0) {
      return;
    }

    final updatedImages = [...current.images];
    updatedImages[idx] = updatedImages[idx].copyWith(failed: false, cacheStatus: 'downloading');
    state = AsyncData(current.copyWith(images: updatedImages, clearHint: true));

    final targetImage = updatedImages[idx];
    final cacheResult = await _cacheReaderImage(targetImage);
    final done = cacheResult.success;
    if (!ref.mounted) {
      return;
    }
    await _repository.updateEpisodeImageCacheStatus(
      episodeId: _args.episodeId,
      imageUrl: imageUrl,
      cacheStatus: done ? 'done' : 'failed',
      cacheLocalPath: done ? cacheResult.localPath : null,
    );
    await _updateImageCacheMetadata(
      episodeId: _args.episodeId,
      imageUrl: imageUrl,
      stableCacheKey: done ? cacheResult.cacheKey : targetImage.cacheKey,
      lastSourceUrl: imageUrl,
      localPath: done ? cacheResult.localPath : null,
      bytes: done ? cacheResult.bytes : null,
      lastAccessedAt: done ? DateTime.now() : null,
    );

    final refreshed = [...updatedImages];
    refreshed[idx] = refreshed[idx].copyWith(
      failed: !done,
      cacheStatus: done ? 'done' : 'failed',
      localPath: done ? cacheResult.localPath : null,
      cacheLocalPath: done ? cacheResult.localPath : null,
    );
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        images: refreshed,
        failedImageCount: _countFailedImages(refreshed),
        cacheSummary: _buildCacheSummary(refreshed),
        hint: done ? '图片重试成功' : '图片重试失败',
      ),
    );
  }

  Future<void> cacheCurrentEpisode() async {
    final current = state.value;
    if (current == null || current.images.isEmpty) {
      return;
    }
    for (final image in current.images) {
      await _repository.updateEpisodeImageCacheStatus(
        episodeId: _args.episodeId,
        imageUrl: image.imageUrl,
        cacheStatus: 'downloading',
      );
      final cacheResult = await _cacheReaderImage(image);
      final done = cacheResult.success;
      if (!ref.mounted) {
        return;
      }
      await _repository.updateEpisodeImageCacheStatus(
        episodeId: _args.episodeId,
        imageUrl: image.imageUrl,
        cacheStatus: done ? 'done' : 'failed',
        cacheLocalPath: done ? cacheResult.localPath : null,
      );
      await _updateImageCacheMetadata(
        episodeId: _args.episodeId,
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
    final episodes = await _repository.getComicEpisodes(comicId: _args.comicId, descending: false);
    final currentIndex = episodes.indexWhere((e) => e.episodeId == _args.episodeId);
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
    final nextState = await _loadState();
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
    await _repository.clearEpisodeImageCache(episodeId: _args.episodeId);
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
      episodeId: _args.episodeId,
      isBookmarked: next,
    );
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        isBookmarked: next,
        hint: next ? '已添加书签' : '已取消书签',
      ),
    );
  }

  Future<void> setCurrentEpisodeRead(bool isRead) async {
    final current = state.value;
    if (current == null) {
      return;
    }
    await _readingStateWriter.setEpisodeRead(
      comicId: _args.comicId,
      episodeId: _args.episodeId,
      isRead: isRead,
    );
    if (isRead) {
      _completedEpisodeIds.add(_args.episodeId);
    } else {
      _completedEpisodeIds.remove(_args.episodeId);
    }
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        isCurrentEpisodeRead: isRead,
        chapters: _markChapterRead(
          current.chapters,
          episodeId: _args.episodeId,
          isRead: isRead,
        ),
        hint: isRead ? '本章已标记为已读' : '本章已标记为未读',
      ),
    );
  }

  Future<void> setCurrentImageAsCover() async {
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
        episodeId: _args.episodeId,
        imageIndex: image.imageIndex,
      ),
    );
    final protectedPath = result.localPath?.trim();
    final writer = _coverCacheWriter;
    if (!result.success || protectedPath == null || protectedPath.isEmpty || writer == null) {
      if (!ref.mounted) {
        return;
      }
      final latest = state.value ?? current;
      state = AsyncData(latest.copyWith(hint: '封面更新失败，请稍后重试'));
      return;
    }
    await writer.updateCoverCache(
      comicId: _args.comicId,
      customCoverLocalPath: protectedPath,
    );
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
    // Warm up images around the jump target to improve immediate readability.
    unawaited(_prefetchAroundIndex(clampedIndex));
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
    await _markEpisodeCompletedIfNeeded(
      currentIndex: clampedIndex,
      scrollOffset: current.lastScrollOffset,
      source: ComicReaderProgressSource.initialVisible,
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
    await _readingStateWriter.saveProgress(
      comicId: _args.comicId,
      episodeId: _args.episodeId,
      imageIndex: currentIndex,
      scrollOffset: scrollOffset,
    );
    _logReaderEvent(
      'page_visible',
      source: source,
      pageIndex: currentIndex,
      scrollOffset: scrollOffset,
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
    if (_completedEpisodeIds.contains(_args.episodeId)) {
      return;
    }
    if (_completingEpisodeIds.contains(_args.episodeId)) {
      return;
    }
    // The last page must have actually entered the viewport. This prevents
    // automatic read completion from firing during chapter load.
    if (!_visibleImageIndexes.contains(lastIndex)) {
      return;
    }
    final lastImage = current.images[lastIndex];
    if (lastImage.failed || lastImage.cacheStatus == 'failed') {
      return;
    }

    final completedAt = DateTime.now();
    _completingEpisodeIds.add(_args.episodeId);
    try {
      await _readingStateWriter.markEpisodeCompleted(
        comicId: _args.comicId,
        episodeId: _args.episodeId,
        imageIndex: lastIndex,
        scrollOffset: scrollOffset,
        completedAt: completedAt,
      );
      _completedEpisodeIds.add(_args.episodeId);
    } finally {
      _completingEpisodeIds.remove(_args.episodeId);
    }
    _logReaderEvent(
      'chapter_completed',
      source: source,
      pageIndex: lastIndex,
      totalPages: current.images.length,
      scrollOffset: scrollOffset,
    );
    if (!ref.mounted) {
      return;
    }
    final latest = state.value;
    if (latest == null) {
      return;
    }
    state = AsyncData(
      latest.copyWith(
        currentImageIndex: lastIndex,
        lastScrollOffset: scrollOffset,
        isCurrentEpisodeRead: true,
        chapters: _markChapterRead(
          latest.chapters,
          episodeId: _args.episodeId,
          isRead: true,
        ),
      ),
    );
  }

  Future<void> _prefetchAroundIndex(int centerIndex) async {
    final current = state.value;
    if (current == null || current.images.isEmpty) {
      return;
    }

    const radius = 2;
    final start = (centerIndex - radius).clamp(0, current.images.length - 1).toInt();
    final end = (centerIndex + radius).clamp(0, current.images.length - 1).toInt();
    final futures = <Future<ComicImageCacheResult>>[];
    for (var i = start; i <= end; i++) {
      futures.add(_cacheReaderImage(current.images[i]));
    }
    await Future.wait(futures);
  }

  Future<String?> _ensureCurrentImageLocalFile(ComicReaderImageState image) async {
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
      episodeId: _args.episodeId,
      imageUrl: image.imageUrl,
      cacheStatus: 'done',
      cacheLocalPath: localPath,
    );
    await _updateImageCacheMetadata(
      episodeId: _args.episodeId,
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
    final idx = images.indexWhere((item) => item.imageIndex == image.imageIndex);
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
    final currentIndex = episodes.indexWhere((e) => e.episodeId == _args.episodeId);
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
    final currentIndex = episodes.indexWhere((e) => e.episodeId == _args.episodeId);
    if (currentIndex < 0 || currentIndex + 1 >= episodes.length) {
      return null;
    }
    return episodes[currentIndex + 1].episodeId;
  }

  Future<ComicReaderViewState> _loadState() async {
    final startedAt = DateTime.now();
    final episodes = await _repository.getComicEpisodes(comicId: _args.comicId, descending: false);
    final episodeIndex = episodes.indexWhere((e) => e.episodeId == _args.episodeId);
    if (episodeIndex < 0) {
      throw StateError('章节不存在');
    }
    final episode = episodes[episodeIndex];
    final images = await _ensureEpisodeImages(episode);
    if (!ref.mounted) {
      throw StateError('阅读器已销毁');
    }
    final progress = await _repository.getLastReadProgress(comicId: _args.comicId);
    final currentImageIndex = progress != null && progress.episodeId == _args.episodeId
        ? progress.imageIndex
            .clamp(0, images.isEmpty ? 0 : images.length - 1)
            .toInt()
        : 0;
    final scrollOffset = progress != null && progress.episodeId == _args.episodeId
        ? progress.scrollOffset
        : 0.0;
    final isRead = await _readingStateWriter.isEpisodeRead(
      comicId: _args.comicId,
      episodeId: _args.episodeId,
    );
    final isBookmarked = await _readingStateWriter.isEpisodeBookmarked(
      comicId: _args.comicId,
      episodeId: _args.episodeId,
    );
    if (isRead) {
      _completedEpisodeIds.add(_args.episodeId);
    }

    _preloadFirstBatch(images);
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
          isCurrent: item.episodeId == _args.episodeId,
          isRead: read,
        ),
      );
    }

    final viewState = ComicReaderViewState(
      comicId: _args.comicId,
      episodeId: _args.episodeId,
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
    );
    _logReaderEvent(
      'open',
      pageIndex: currentImageIndex,
      totalPages: viewState.images.length,
      elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
    );
    return viewState;
  }

  Future<List<ComicEpisodeImageItem>> _ensureEpisodeImages(ComicEpisodeItem episode) async {
    final downloaded = await _downloadService.getDownloadedEpisodeImages(
      comicId: _args.comicId,
      episodeId: episode.episodeId,
    );
    if (downloaded.isNotEmpty) {
      return downloaded;
    }

    var images = await _repository.getEpisodeImages(episodeId: episode.episodeId);
    if (images.isNotEmpty) {
      return images;
    }
    final fetched = await _readerService.fetchEpisodeImagesByTid(episode.sourceTid);
    if (!ref.mounted) {
      return const <ComicEpisodeImageItem>[];
    }
    if (fetched.isEmpty) {
      return const <ComicEpisodeImageItem>[];
    }
    await _repository.saveEpisodeImages(episodeId: episode.episodeId, imageUrls: fetched);
    images = await _repository.getEpisodeImages(episodeId: episode.episodeId);
    return images;
  }

  void _preloadFirstBatch(List<ComicEpisodeImageItem> images) {
    final limit = images.length < 3 ? images.length : 3;
    for (var i = 0; i < limit; i++) {
      if (_isDownloadedEpisodeImage(images[i])) {
        continue;
      }
      unawaited(_cacheEpisodeImage(images[i]));
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
      episodeId: _args.episodeId,
      imageIndex: image.imageIndex,
    );
  }

  Future<ComicImageCacheResult> _cacheEpisodeImage(ComicEpisodeImageItem image) {
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
    return image.cacheStatus == 'downloaded' && image.effectiveLocalPath != null;
  }

  bool _isDownloadedEpisodeImage(ComicEpisodeImageItem image) {
    return image.cacheStatus == 'downloaded' && image.effectiveLocalPath != null;
  }

  int _countFailedImages(List<ComicReaderImageState> images) {
    return images
        .where((image) => image.failed || image.cacheStatus == 'failed')
        .length;
  }

  ComicReaderCacheSummary _buildCacheSummary(List<ComicReaderImageState> images) {
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
      episodeId: _args.episodeId,
      imageIndex: imageIndex,
    );
  }

  Future<void> _updateImageCacheMetadata({
    required String episodeId,
    required String imageUrl,
    String? stableCacheKey,
    String? lastSourceUrl,
    String? localPath,
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
  }) {
    final openedAt = _openedAt;
    _eventLogger.log(
      event: event,
      comicId: _args.comicId,
      episodeId: _args.episodeId,
      source: source,
      pageIndex: pageIndex,
      totalPages: totalPages,
      scrollOffset: scrollOffset,
      elapsedMs: elapsedMs,
      sinceOpenMs: openedAt == null
          ? null
          : DateTime.now().difference(openedAt).inMilliseconds,
    );
  }
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/comic/data/services/comic_download_service.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/services/comic_episode_images_fetch_result.dart';
import 'package:y300/features/comic/domain/services/comic_episode_images_unavailable.dart';
import 'package:y300/features/comic/domain/services/comic_reader_events.dart';
import 'package:y300/features/comic/domain/services/comic_reader_feature_flags.dart';
import 'package:y300/features/comic/domain/services/comic_reading_state_writer.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/domain/services/comic_episode_sequence.dart';
import 'package:y300/features/comic/presentation/comic_presentation_models.dart';
import 'package:y300/features/library_shared/data/providers/library_cover_providers.dart';
import 'package:y300/features/library_shared/domain/models/library_cover_asset.dart';
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

/// Repository data needed to prepare the next episode lookahead. This model
/// intentionally carries no reader widgets or preload implementation details.
class ComicAdjacentEpisodePreload {
  const ComicAdjacentEpisodePreload({
    required this.episodeId,
    required this.images,
  });

  final String episodeId;
  final List<ComicEpisodeImageItem> images;
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
    this.isSwitchingEpisode = false,
    this.isRefreshingEpisode = false,
    this.imageSessionRevision = 0,
    this.noticeCode,
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
  final bool isSwitchingEpisode;
  final bool isRefreshingEpisode;
  final int imageSessionRevision;
  final ComicReaderNoticeCode? noticeCode;

  ComicReaderChapterEntry? get nextChapter {
    final currentIndex = chapters.indexWhere((chapter) => chapter.isCurrent);
    if (currentIndex < 0 || currentIndex + 1 >= chapters.length) {
      return null;
    }
    return chapters[currentIndex + 1];
  }

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
    bool? isSwitchingEpisode,
    bool? isRefreshingEpisode,
    int? imageSessionRevision,
    ComicReaderNoticeCode? noticeCode,
    bool clearNotice = false,
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
      isSwitchingEpisode: isSwitchingEpisode ?? this.isSwitchingEpisode,
      isRefreshingEpisode: isRefreshingEpisode ?? this.isRefreshingEpisode,
      imageSessionRevision: imageSessionRevision ?? this.imageSessionRevision,
      noticeCode: clearNotice ? null : (noticeCode ?? this.noticeCode),
    );
  }
}

final comicReaderControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ComicReaderController, ComicReaderViewState, ComicReaderArgs>(
      (args) => ComicReaderController(args),
    );

class ComicReaderController extends AsyncNotifier<ComicReaderViewState> {
  ComicReaderController(this._args);

  static const ComicEpisodeSequence _episodeSequence = ComicEpisodeSequence();

  final ComicReaderArgs _args;
  late ComicRepository _repository;
  late ComicReaderService _readerService;
  late ComicDownloadService _downloadService;
  late ComicReadingStateWriter _readingStateWriter;
  late ComicReaderEventLogger _eventLogger;
  late ComicReaderFeatureFlags _featureFlags;
  Timer? _progressPersistDebounceTimer;
  int _persistVersion = 0;
  final Set<String> _completedEpisodeIds = <String>{};
  final Set<String> _completingEpisodeIds = <String>{};
  final Set<int> _visibleImageIndexes = <int>{};
  final Set<int> _resolvedImageIndexes = <int>{};
  final Map<String, Future<void>> _episodeRetryProbeInFlight =
      <String, Future<void>>{};
  late String _currentEpisodeId;
  int _episodeOperationGeneration = 0;
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
    _eventLogger = ref.read(comicReaderEventLoggerProvider);
    _featureFlags = ref.read(comicReaderFeatureFlagsProvider);
    _openedAt = DateTime.now();
    _currentEpisodeId = _args.episodeId;
    ref.onDispose(() {
      _episodeOperationGeneration += 1;
      _progressPersistDebounceTimer?.cancel();
    });
    return _loadState(episodeId: _currentEpisodeId);
  }

  Future<ComicReaderNoticeCode?> toggleBookmark() async {
    final current = state.value;
    if (current == null) {
      return null;
    }
    final next = !current.isBookmarked;
    await _readingStateWriter.setEpisodeBookmarked(
      comicId: _args.comicId,
      episodeId: current.episodeId,
      isBookmarked: next,
    );
    if (!ref.mounted) {
      return null;
    }
    state = AsyncData(current.copyWith(isBookmarked: next, clearNotice: true));
    return next
        ? ComicReaderNoticeCode.bookmarkAdded
        : ComicReaderNoticeCode.bookmarkRemoved;
  }

  Future<ComicReaderNoticeCode?> setCurrentEpisodeRead(bool isRead) async {
    final current = state.value;
    if (current == null) {
      return null;
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
      return null;
    }
    state = AsyncData(
      current.copyWith(
        isCurrentEpisodeRead: isRead,
        chapters: _markChapterRead(
          current.chapters,
          episodeId: current.episodeId,
          isRead: isRead,
        ),
        clearNotice: true,
      ),
    );
    return isRead
        ? ComicReaderNoticeCode.episodeMarkedRead
        : ComicReaderNoticeCode.episodeMarkedUnread;
  }

  /// 为“设为封面”准备当前页的本地文件，供 UI 在焦点选区器里预览。
  ///
  /// 返回可读的本地路径（必要时先落盘缓存）；失败返回 null。
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
      state = AsyncData(latest.copyWith(clearNotice: true));
      return null;
    }
    return localPath;
  }

  Future<ComicReaderNoticeCode?> setCurrentImageAsCover({
    double? focusX,
    double? focusY,
  }) async {
    final coverStore = ref.read(libraryCoverStoreProvider);
    final current = state.value;
    final image = current?.currentImage;
    if (current == null || image == null) {
      return null;
    }

    state = AsyncData(current.copyWith(clearNotice: true));
    final localPath = await _ensureCurrentImageLocalFile(image);
    if (localPath == null || localPath.trim().isEmpty) {
      if (!ref.mounted) {
        return null;
      }
      final latest = state.value ?? current;
      state = AsyncData(latest.copyWith(clearNotice: true));
      return ComicReaderNoticeCode.coverImageUnavailable;
    }

    final repository = _repository;
    if (repository is! ComicCustomCoverAssetWriter) {
      if (!ref.mounted) {
        return null;
      }
      final latest = state.value ?? current;
      state = AsyncData(latest.copyWith(clearNotice: true));
      return ComicReaderNoticeCode.coverUpdateFailed;
    }
    final assetWriter = repository as ComicCustomCoverAssetWriter;
    final detail = await repository.getComicDetail(comicId: _args.comicId);
    final asset = LibraryCoverAssetRef(
      assetId: LibraryCoverAssetIds.custom(
        ownerType: 'comic',
        ownerId: _args.comicId,
      ),
      revision: (detail?.customCoverRevision ?? 0) + 1,
      kind: LibraryCoverAssetKind.custom,
    );
    var installed = false;
    try {
      await coverStore.installLocalFile(asset: asset, sourcePath: localPath);
      installed = true;
      await assetWriter.activateCustomCoverAsset(
        comicId: _args.comicId,
        revision: asset.revision,
        focusX: focusX,
        focusY: focusY,
      );
      await coverStore.deleteOlderRevisions(asset);
    } catch (_) {
      if (installed) {
        await coverStore.invalidate(asset);
      }
      if (!ref.mounted) {
        return null;
      }
      final latest = state.value ?? current;
      state = AsyncData(latest.copyWith(clearNotice: true));
      return ComicReaderNoticeCode.coverUpdateFailed;
    }
    if (!ref.mounted) {
      return null;
    }
    final latest = state.value ?? current;
    state = AsyncData(latest.copyWith(clearNotice: true));
    return ComicReaderNoticeCode.coverUpdated;
  }

  Future<void> onScrollProgress({
    required int currentIndex,
    required double scrollOffset,
    String? expectedEpisodeId,
  }) async {
    if (expectedEpisodeId != null && expectedEpisodeId != _activeEpisodeId) {
      return;
    }
    final current = state.value;
    if (current == null ||
        current.isSwitchingEpisode ||
        current.isRefreshingEpisode) {
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
  Future<void> jumpToImageIndex(
    int index, {
    double? scrollOffset,
    String? expectedEpisodeId,
  }) async {
    if (expectedEpisodeId != null && expectedEpisodeId != _activeEpisodeId) {
      return;
    }
    final current = state.value;
    if (current == null ||
        current.isSwitchingEpisode ||
        current.isRefreshingEpisode ||
        current.images.isEmpty) {
      return;
    }
    final clampedIndex = index.clamp(0, current.images.length - 1).toInt();
    final nextOffset = scrollOffset ?? current.lastScrollOffset;
    _cancelScheduledProgressPersistence();
    _visibleImageIndexes.add(clampedIndex);
    await _saveProgressNow(
      episodeId: current.episodeId,
      currentIndex: clampedIndex,
      scrollOffset: nextOffset,
      source: ComicReaderProgressSource.jump,
    );
    if (!ref.mounted || _activeEpisodeId != current.episodeId) {
      return;
    }
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
  }

  /// Runs the normal chapter request before retrying an individual image.
  ///
  /// The result is deliberately not persisted here: the request exists to
  /// let the shared gateway recover WAF/session state. Only the explicit
  /// refresh action is allowed to replace the chapter image directory.
  Future<void> prepareImageRetry({required String expectedEpisodeId}) async {
    final current = state.value;
    if (current == null ||
        current.episodeId != expectedEpisodeId ||
        current.isSwitchingEpisode ||
        current.isRefreshingEpisode) {
      return;
    }
    final episodeId = current.episodeId;
    final sourceTid = current.sourceTid;
    final generation = _episodeOperationGeneration;
    final existing = _episodeRetryProbeInFlight[episodeId];
    if (existing != null) {
      await existing;
      return;
    }

    late final Future<void> probe;
    probe = _runEpisodeRetryProbe(
      episodeId: episodeId,
      sourceTid: sourceTid,
      generation: generation,
    );
    _episodeRetryProbeInFlight[episodeId] = probe;
    try {
      await probe;
    } finally {
      if (identical(_episodeRetryProbeInFlight[episodeId], probe)) {
        _episodeRetryProbeInFlight.remove(episodeId);
      }
    }
  }

  Future<void> _runEpisodeRetryProbe({
    required String episodeId,
    required String sourceTid,
    required int generation,
  }) async {
    try {
      await _readerService.fetchEpisodeImages(sourceTid);
    } catch (_) {
      // The image retry still runs. A failed parse may follow a successful WAF
      // recovery, and the user must not lose the original direct retry path.
    }
    if (!_ownsEpisodeOperation(episodeId: episodeId, generation: generation)) {
      return;
    }
  }

  Future<ComicReaderEpisodeRefreshResult> refreshCurrentEpisode() async {
    final current = state.value;
    if (current == null ||
        current.isSwitchingEpisode ||
        current.isRefreshingEpisode) {
      return const ComicReaderEpisodeRefreshResult.stale();
    }

    final episodeId = current.episodeId;
    final sourceTid = current.sourceTid;
    final previousImageUrl = current.currentImage?.imageUrl;
    final previousIndex = current.currentImageIndex;
    final generation = ++_episodeOperationGeneration;
    _cancelScheduledProgressPersistence();
    state = AsyncData(
      current.copyWith(isRefreshingEpisode: true, clearNotice: true),
    );

    try {
      final fetchResult = await _readerService.fetchEpisodeImages(sourceTid);
      if (!_ownsEpisodeOperation(
        episodeId: episodeId,
        generation: generation,
      )) {
        return const ComicReaderEpisodeRefreshResult.stale();
      }
      switch (fetchResult) {
        case ComicEpisodeImagesFetchFailed(:final reason):
          _finishEpisodeRefresh(episodeId: episodeId, generation: generation);
          return ComicReaderEpisodeRefreshResult.failed(reason: reason);
        case ComicEpisodeImagesFetched(:final imageUrls):
          if (imageUrls.isEmpty) {
            _finishEpisodeRefresh(episodeId: episodeId, generation: generation);
            return const ComicReaderEpisodeRefreshResult.noImages();
          }
          final repository = _repository;
          if (repository is! ComicEpisodeImageDirectoryReplacer) {
            _finishEpisodeRefresh(episodeId: episodeId, generation: generation);
            return const ComicReaderEpisodeRefreshResult.failed();
          }
          final replacer = repository as ComicEpisodeImageDirectoryReplacer;
          await replacer.replaceEpisodeImages(
            episodeId: episodeId,
            imageUrls: imageUrls,
          );
      }

      if (!_ownsEpisodeOperation(
        episodeId: episodeId,
        generation: generation,
      )) {
        return const ComicReaderEpisodeRefreshResult.stale();
      }
      final refreshedImages = await _repository.getEpisodeImages(
        episodeId: episodeId,
      );
      if (!_ownsEpisodeOperation(
        episodeId: episodeId,
        generation: generation,
      )) {
        return const ComicReaderEpisodeRefreshResult.stale();
      }
      if (refreshedImages.isEmpty) {
        _finishEpisodeRefresh(episodeId: episodeId, generation: generation);
        return const ComicReaderEpisodeRefreshResult.noImages();
      }

      final imageStates = _mapImageStates(refreshedImages);
      final matchingIndex = previousImageUrl == null
          ? -1
          : imageStates.indexWhere(
              (image) => image.imageUrl == previousImageUrl,
            );
      final nextIndex = matchingIndex >= 0
          ? matchingIndex
          : previousIndex.clamp(0, imageStates.length - 1).toInt();
      try {
        await _saveProgressNow(
          episodeId: episodeId,
          currentIndex: nextIndex,
          scrollOffset: 0,
          source: ComicReaderProgressSource.jump,
        );
      } catch (_) {
        // The image directory has already been replaced atomically. A progress
        // persistence failure must not report the server refresh as failed.
      }
      if (!_ownsEpisodeOperation(
        episodeId: episodeId,
        generation: generation,
      )) {
        return const ComicReaderEpisodeRefreshResult.stale();
      }

      final latest = state.value;
      if (latest == null) {
        return const ComicReaderEpisodeRefreshResult.stale();
      }
      _visibleImageIndexes.clear();
      _resolvedImageIndexes.clear();
      _firstImageVisibleLogged = false;
      state = AsyncData(
        latest.copyWith(
          images: imageStates,
          currentImageIndex: nextIndex,
          lastScrollOffset: 0,
          failedImageCount: _countFailedImages(imageStates),
          cacheSummary: _buildCacheSummary(imageStates),
          isRefreshingEpisode: false,
          imageSessionRevision: latest.imageSessionRevision + 1,
          clearNotice: true,
        ),
      );
      return const ComicReaderEpisodeRefreshResult.refreshed();
    } catch (_) {
      if (_ownsEpisodeOperation(episodeId: episodeId, generation: generation)) {
        _finishEpisodeRefresh(episodeId: episodeId, generation: generation);
        return const ComicReaderEpisodeRefreshResult.failed();
      }
      return const ComicReaderEpisodeRefreshResult.stale();
    }
  }

  bool _ownsEpisodeOperation({
    required String episodeId,
    required int generation,
  }) {
    return ref.mounted &&
        _activeEpisodeId == episodeId &&
        _episodeOperationGeneration == generation;
  }

  void _finishEpisodeRefresh({
    required String episodeId,
    required int generation,
  }) {
    if (!_ownsEpisodeOperation(episodeId: episodeId, generation: generation)) {
      return;
    }
    final latest = state.value;
    if (latest != null) {
      state = AsyncData(
        latest.copyWith(isRefreshingEpisode: false, clearNotice: true),
      );
    }
  }

  Future<bool> openEpisode({
    required String episodeId,
    ComicEpisodeOpenPolicy policy = ComicEpisodeOpenPolicy.resumeIfUnread,
  }) {
    return _openEpisodeTransaction(
      requestedEpisodeId: episodeId,
      policy: policy,
    );
  }

  Future<bool> openAdjacentEpisode({
    required String sourceEpisodeId,
    required ComicEpisodeDirection direction,
  }) {
    return _openEpisodeTransaction(
      sourceEpisodeId: sourceEpisodeId,
      direction: direction,
      policy: ComicEpisodeOpenPolicy.startAtBeginning,
    );
  }

  Future<bool> _openEpisodeTransaction({
    String? requestedEpisodeId,
    String? sourceEpisodeId,
    ComicEpisodeDirection? direction,
    required ComicEpisodeOpenPolicy policy,
  }) async {
    final current = state.value;
    final sourceId = sourceEpisodeId?.trim();
    if (current == null ||
        current.isSwitchingEpisode ||
        current.isRefreshingEpisode ||
        (sourceId != null && sourceId != _activeEpisodeId)) {
      return false;
    }

    final requestedId = requestedEpisodeId?.trim();
    if (direction == null &&
        (requestedId == null ||
            requestedId.isEmpty ||
            requestedId == _activeEpisodeId)) {
      return false;
    }

    _episodeOperationGeneration += 1;
    state = AsyncData(
      current.copyWith(isSwitchingEpisode: true, clearNotice: true),
    );
    _cancelScheduledProgressPersistence();

    String? targetEpisodeId = requestedEpisodeId?.trim();
    try {
      if (direction != null) {
        final episodes = await _loadEpisodesInReaderOrder();
        if (!ref.mounted ||
            (sourceId != null && sourceId != _activeEpisodeId)) {
          return false;
        }
        targetEpisodeId = _episodeSequence
            .adjacent(
              episodes: episodes,
              episodeId: sourceId ?? _activeEpisodeId,
              direction: direction,
            )
            ?.episodeId;
      }
      if (!ref.mounted ||
          targetEpisodeId == null ||
          targetEpisodeId.isEmpty ||
          targetEpisodeId == _activeEpisodeId) {
        if (ref.mounted) {
          final latest = state.value ?? current;
          state = AsyncData(
            latest.copyWith(isSwitchingEpisode: false, clearNotice: true),
          );
        }
        return false;
      }

      final nextState = await _loadState(
        episodeId: targetEpisodeId,
        policy: policy,
      );
      if (!ref.mounted) {
        return false;
      }
      _currentEpisodeId = targetEpisodeId;
      _visibleImageIndexes.clear();
      _resolvedImageIndexes.clear();
      _firstImageVisibleLogged = false;
      state = AsyncData(
        nextState.copyWith(isSwitchingEpisode: false, clearNotice: true),
      );
      _logReaderEvent(
        'episode_switched',
        pageIndex: nextState.currentImageIndex,
        totalPages: nextState.images.length,
        extra: <String, Object?>{
          'targetEpisodeId': targetEpisodeId,
          'policy': policy.name,
        },
      );
      return true;
    } catch (error) {
      if (!ref.mounted) {
        return false;
      }
      final latest = state.value ?? current;
      state = AsyncData(
        latest.copyWith(
          isSwitchingEpisode: false,
          noticeCode: ComicReaderNoticeCode.episodeSwitchFailed,
        ),
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
  Future<void> onImageVisible(
    int imageIndex, {
    String? expectedEpisodeId,
  }) async {
    return _onImageVisible(
      imageIndex: imageIndex,
      expectedEpisodeId: expectedEpisodeId,
    );
  }

  Future<void> _onImageVisible({
    required int imageIndex,
    String? expectedEpisodeId,
  }) async {
    if (expectedEpisodeId != null && expectedEpisodeId != _activeEpisodeId) {
      return;
    }
    final current = state.value;
    if (current == null ||
        current.isSwitchingEpisode ||
        current.isRefreshingEpisode ||
        current.images.isEmpty) {
      return;
    }
    final clampedIndex = imageIndex.clamp(0, current.images.length - 1).toInt();
    _recordVisiblePage(
      currentIndex: clampedIndex,
      scrollOffset: current.lastScrollOffset,
      source: ComicReaderProgressSource.initialVisible,
      checkCompletion: false,
    );
    final latest = state.value;
    if (latest != null && latest.episodeId == current.episodeId) {
      state = AsyncData(latest.copyWith(currentImageIndex: clampedIndex));
    }
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
    String? expectedEpisodeId,
  }) async {
    if (expectedEpisodeId != null && expectedEpisodeId != _activeEpisodeId) {
      return;
    }
    final current = state.value;
    if (current == null ||
        current.isSwitchingEpisode ||
        current.isRefreshingEpisode ||
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
      if (_visibleImageIndexes.contains(clampedIndex)) {
        await _markEpisodeCompletedIfNeeded(
          currentIndex: clampedIndex,
          scrollOffset: current.lastScrollOffset,
          source: ComicReaderProgressSource.initialVisible,
        );
      }
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
    if (_visibleImageIndexes.contains(clampedIndex)) {
      await _markEpisodeCompletedIfNeeded(
        currentIndex: clampedIndex,
        scrollOffset: latest.lastScrollOffset,
        source: ComicReaderProgressSource.initialVisible,
      );
    }
  }

  Future<void> onImageDisplayFailed({
    required int imageIndex,
    required String imageUrl,
    String? expectedEpisodeId,
  }) async {
    if (expectedEpisodeId != null && expectedEpisodeId != _activeEpisodeId) {
      return;
    }
    final current = state.value;
    if (current == null ||
        current.isSwitchingEpisode ||
        current.isRefreshingEpisode ||
        current.images.isEmpty) {
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
      episodeId: current.episodeId,
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
    final episodeId = _activeEpisodeId;
    _progressPersistDebounceTimer = Timer(
      const Duration(milliseconds: 180),
      () async {
        await _saveProgressNow(
          episodeId: episodeId,
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
    required String episodeId,
    required int currentIndex,
    required double scrollOffset,
    required ComicReaderProgressSource source,
  }) async {
    if (!ref.mounted || episodeId != _activeEpisodeId) {
      return;
    }
    final startedAt = DateTime.now();
    await _readingStateWriter.saveProgress(
      comicId: _args.comicId,
      episodeId: episodeId,
      imageIndex: currentIndex,
      scrollOffset: scrollOffset,
    );
    if (!ref.mounted || episodeId != _activeEpisodeId) {
      return;
    }
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
    // Image resolution may be caused by a preload task. Completion is a
    // reading event and therefore requires an actual viewport hit first.
    if (!_visibleImageIndexes.contains(lastIndex)) {
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

  /// Resolves only the next episode's image metadata for reader lookahead.
  ///
  /// It may populate the normal episode-image table when the next chapter has
  /// not been discovered yet, but it never changes reading progress, read
  /// state, bookmark state, or explicit download state.
  Future<ComicAdjacentEpisodePreload?> prepareNextEpisodePreload() async {
    final current = state.value;
    if (current == null ||
        current.isSwitchingEpisode ||
        current.isRefreshingEpisode) {
      return null;
    }
    final activeEpisodeId = _activeEpisodeId;
    final episodes = await _loadEpisodesInReaderOrder();
    final nextEpisode = _episodeSequence.adjacent(
      episodes: episodes,
      episodeId: activeEpisodeId,
      direction: ComicEpisodeDirection.next,
    );
    if (nextEpisode == null) {
      return null;
    }
    final images = await _ensureEpisodeImages(nextEpisode);
    if (!ref.mounted || _activeEpisodeId != activeEpisodeId || images.isEmpty) {
      return null;
    }
    return ComicAdjacentEpisodePreload(
      episodeId: nextEpisode.episodeId,
      images: List<ComicEpisodeImageItem>.unmodifiable(images),
    );
  }

  Future<ComicReaderViewState> _loadState({
    required String episodeId,
    ComicEpisodeOpenPolicy policy = ComicEpisodeOpenPolicy.resumeIfUnread,
  }) async {
    final startedAt = DateTime.now();
    final episodes = await _loadEpisodesInReaderOrder();
    final episodeIndex = episodes.indexWhere((e) => e.episodeId == episodeId);
    if (episodeIndex < 0) {
      throw const ComicReaderLoadException(
        ComicReaderLoadFailureCode.episodeNotFound,
      );
    }
    final episode = episodes[episodeIndex];
    final isRead = await _readingStateWriter.isEpisodeRead(
      comicId: _args.comicId,
      episodeId: episodeId,
    );
    final isBookmarked = await _readingStateWriter.isEpisodeBookmarked(
      comicId: _args.comicId,
      episodeId: episodeId,
    );
    final images = await _ensureEpisodeImages(episode);
    if (!ref.mounted) {
      throw StateError('reader_disposed');
    }
    final shouldRestoreProgress =
        policy == ComicEpisodeOpenPolicy.resumeIfUnread && !isRead;
    final progress = shouldRestoreProgress
        ? await _repository.getReadingProgressForEpisode(
            comicId: _args.comicId,
            episodeId: episodeId,
          )
        : null;
    final currentImageIndex = progress == null
        ? 0
        : progress.imageIndex
              .clamp(0, images.isEmpty ? 0 : images.length - 1)
              .toInt();
    final scrollOffset = progress?.scrollOffset ?? 0.0;
    if (isRead) {
      _completedEpisodeIds.add(episodeId);
    }

    final detail = await _repository.getComicDetail(comicId: _args.comicId);
    final imageStates = _mapImageStates(images);
    final chapters = <ComicReaderChapterEntry>[];
    for (final item in episodes) {
      final read = await _readingStateWriter.isEpisodeRead(
        comicId: _args.comicId,
        episodeId: item.episodeId,
      );
      chapters.add(
        ComicReaderChapterEntry(
          episodeId: item.episodeId,
          title: item.episodeTitle ?? '',
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
      comicTitle: detail?.title ?? '',
      episodeTitle: episode.episodeTitle ?? '',
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

  Future<List<ComicEpisodeItem>> _loadEpisodesInReaderOrder() async {
    final episodes = await _repository.getComicEpisodes(
      comicId: _args.comicId,
      descending: false,
    );
    return _episodeSequence.order(episodes);
  }

  List<ComicReaderImageState> _mapImageStates(
    List<ComicEpisodeImageItem> images,
  ) {
    return images
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

  bool _isDownloadedReaderImage(ComicReaderImageState image) {
    return image.cacheStatus == 'downloaded' &&
        image.effectiveLocalPath != null;
  }

  bool _isImageResolvedInCurrentSession(int imageIndex) {
    return _resolvedImageIndexes.contains(imageIndex);
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

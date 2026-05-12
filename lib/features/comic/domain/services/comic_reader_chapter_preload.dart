import 'package:y300/features/comic/domain/models/comic_detail_models.dart';

enum ComicReaderChapterPreloadStatus {
  unavailable,
  idle,
  loadingImages,
  imagesReady,
  preloadingPages,
  ready,
  failed,
}

/// Policy object for Phase 5 chapter-level preloading.
///
/// Keeping thresholds in one small value object makes reader behavior easy to
/// review and test without reaching into the Riverpod controller.
class ComicReaderChapterPreloadPolicy {
  const ComicReaderChapterPreloadPolicy({
    this.shortChapterMaxPageCount = 6,
    this.shortChapterTrailingPages = 2,
    this.longChapterTrailingPages = 4,
    this.firstPagePreloadCount = 3,
  });

  final int shortChapterMaxPageCount;
  final int shortChapterTrailingPages;
  final int longChapterTrailingPages;
  final int firstPagePreloadCount;

  bool shouldPreloadNextChapter({
    required int currentImageIndex,
    required int totalImages,
  }) {
    if (totalImages <= 0) {
      return false;
    }
    final trailingPages = totalImages <= shortChapterMaxPageCount
        ? shortChapterTrailingPages
        : longChapterTrailingPages;
    final firstTriggerIndex = totalImages - trailingPages.clamp(1, totalImages);
    return currentImageIndex >= firstTriggerIndex;
  }

  int firstPageWindowLength(int imageCount) {
    if (imageCount <= 0) {
      return 0;
    }
    return imageCount < firstPagePreloadCount ? imageCount : firstPagePreloadCount;
  }
}

class ComicReaderChapterPreloadState {
  const ComicReaderChapterPreloadState({
    required this.status,
    this.episodeId,
    this.title,
    this.sourceTid,
    this.imageCount = 0,
    this.cachedPageCount = 0,
    this.firstPageCacheStatus,
    this.message,
  });

  factory ComicReaderChapterPreloadState.unavailable({
    String message = '已是最后一章',
  }) {
    return ComicReaderChapterPreloadState(
      status: ComicReaderChapterPreloadStatus.unavailable,
      message: message,
    );
  }

  factory ComicReaderChapterPreloadState.idle(ComicEpisodeItem episode) {
    return ComicReaderChapterPreloadState(
      status: ComicReaderChapterPreloadStatus.idle,
      episodeId: episode.episodeId,
      title: episode.episodeTitle ?? '章节 ${episode.sourceTid}',
      sourceTid: episode.sourceTid,
    );
  }

  final ComicReaderChapterPreloadStatus status;
  final String? episodeId;
  final String? title;
  final String? sourceTid;
  final int imageCount;
  final int cachedPageCount;
  final String? firstPageCacheStatus;
  final String? message;

  bool get hasEpisode => episodeId != null;

  bool get hasLoadedImageList {
    return status == ComicReaderChapterPreloadStatus.imagesReady ||
        status == ComicReaderChapterPreloadStatus.preloadingPages ||
        status == ComicReaderChapterPreloadStatus.ready;
  }

  bool get canOpen {
    return hasEpisode && status != ComicReaderChapterPreloadStatus.unavailable;
  }

  String get displayTitle {
    final value = title?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
    final tid = sourceTid?.trim();
    return tid == null || tid.isEmpty ? '下一章' : '章节 $tid';
  }

  ComicReaderChapterPreloadState copyWith({
    ComicReaderChapterPreloadStatus? status,
    int? imageCount,
    int? cachedPageCount,
    String? firstPageCacheStatus,
    String? message,
    bool clearMessage = false,
  }) {
    return ComicReaderChapterPreloadState(
      status: status ?? this.status,
      episodeId: episodeId,
      title: title,
      sourceTid: sourceTid,
      imageCount: imageCount ?? this.imageCount,
      cachedPageCount: cachedPageCount ?? this.cachedPageCount,
      firstPageCacheStatus: firstPageCacheStatus ?? this.firstPageCacheStatus,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

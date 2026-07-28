import 'package:y300/features/comic/domain/models/comic_download_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_episode_images_fetch_result.dart';
import 'package:y300/features/comic/domain/services/comic_episode_images_unavailable.dart';
import 'package:y300/features/comic/presentation/comic_presentation_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/presentation/services/library_error_summary.dart';
import 'package:y300/features/library_shared/presentation/services/library_title_fallback_policy.dart';
import 'package:y300/features/reader_shared/domain/reader_preferences/reader_preferences.dart';
import 'package:y300/l10n/app_localizations.dart';

abstract final class ComicTextResolver {
  static String workTitle(
    AppLocalizations l10n,
    String rawTitle,
    String workId,
  ) {
    return LibraryTitleFallbackPolicy.needsWorkFallback(
          LibraryModuleKey.comic,
          rawTitle,
        )
        ? l10n.comicUntitledWork(workId)
        : rawTitle;
  }

  static String chapterTitle(
    AppLocalizations l10n,
    String rawTitle,
    String sourceTid,
  ) {
    return LibraryTitleFallbackPolicy.needsChapterFallback(rawTitle, sourceTid)
        ? l10n.comicChapterFallbackTitle(sourceTid)
        : rawTitle;
  }

  static String readerNotice(
    AppLocalizations l10n,
    ComicReaderNoticeCode code,
  ) {
    return switch (code) {
      ComicReaderNoticeCode.bookmarkAdded => l10n.comicBookmarkAdded,
      ComicReaderNoticeCode.bookmarkRemoved => l10n.comicBookmarkRemoved,
      ComicReaderNoticeCode.episodeMarkedRead => l10n.comicEpisodeMarkedRead,
      ComicReaderNoticeCode.episodeMarkedUnread =>
        l10n.comicEpisodeMarkedUnread,
      ComicReaderNoticeCode.coverImageUnavailable =>
        l10n.comicCoverImageUnavailable,
      ComicReaderNoticeCode.coverUpdateFailed => l10n.comicCoverUpdateFailed,
      ComicReaderNoticeCode.coverUpdated => l10n.comicCoverUpdated,
      ComicReaderNoticeCode.episodeSwitchFailed =>
        l10n.comicEpisodeSwitchFailed,
    };
  }

  static String readerFailure(AppLocalizations l10n, Object error) {
    if (error is ComicEpisodeImagesUnavailable) {
      return switch (error.reason) {
        ComicEpisodeImagesFetchFailureReason.network =>
          l10n.comicReaderNetworkFailure,
        ComicEpisodeImagesFetchFailureReason.auth =>
          l10n.comicReaderAuthFailure,
        ComicEpisodeImagesFetchFailureReason.server =>
          l10n.comicReaderServerFailure,
        ComicEpisodeImagesFetchFailureReason.parse =>
          l10n.comicReaderParseFailure,
        ComicEpisodeImagesFetchFailureReason.unknown =>
          l10n.comicReaderUnknownFailure,
      };
    }
    if (error is ComicReaderLoadException) {
      return switch (error.code) {
        ComicReaderLoadFailureCode.episodeNotFound =>
          l10n.comicReaderEpisodeUnavailable,
      };
    }
    return l10n.comicReaderLoadFailed(LibraryErrorSummary.resolve(l10n, error));
  }

  static String detailRefreshNotice(
    AppLocalizations l10n,
    ComicDetailRefreshNotice notice,
  ) {
    return switch (notice.code) {
      ComicDetailRefreshNoticeCode.noLinks => l10n.comicRefreshNoNewLinks,
      ComicDetailRefreshNoticeCode.completed => l10n.comicRefreshCompleted(
        notice.insertedCount,
        notice.updatedCount,
      ),
      ComicDetailRefreshNoticeCode.failed => l10n.comicRefreshFailed(
        LibraryErrorSummary.resolve(l10n, notice.detail),
      ),
    };
  }

  static String downloadFailure(
    AppLocalizations l10n,
    ComicDownloadFailureCode code,
  ) {
    return switch (code) {
      ComicDownloadFailureCode.workUnavailable =>
        l10n.comicDownloadWorkUnavailable,
      ComicDownloadFailureCode.episodeUnavailable =>
        l10n.comicDownloadEpisodeUnavailable,
      ComicDownloadFailureCode.noImages => l10n.comicDownloadNoImages,
      ComicDownloadFailureCode.imageDownloadFailed =>
        l10n.comicDownloadImageFailed,
      ComicDownloadFailureCode.storageFailed => l10n.comicDownloadStorageFailed,
      ComicDownloadFailureCode.unknown => l10n.comicDownloadUnknownFailure,
    };
  }

  static String readerMode(AppLocalizations l10n, ReaderModePreference mode) {
    return switch (mode) {
      ReaderModePreference.vertical => l10n.readerModeVertical,
      ReaderModePreference.ltr => l10n.readerModeLtr,
      ReaderModePreference.rtl => l10n.readerModeRtl,
    };
  }
}

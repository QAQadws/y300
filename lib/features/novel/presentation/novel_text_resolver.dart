import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/presentation/services/library_error_summary.dart';
import 'package:y300/features/library_shared/presentation/services/library_title_fallback_policy.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/domain/models/novel_interaction_models.dart';
import 'package:y300/features/novel/presentation/controllers/novel_chapter_hydration_controller.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_chapter_turn.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_bootstrap_service.dart';
import 'package:y300/l10n/app_localizations.dart';

abstract final class NovelTextResolver {
  static String workTitle(
    AppLocalizations l10n,
    String rawTitle,
    String novelId,
  ) {
    return LibraryTitleFallbackPolicy.needsWorkFallback(
          LibraryModuleKey.novel,
          rawTitle,
        )
        ? l10n.novelUntitledWork(novelId)
        : rawTitle;
  }

  static String chapterTitle(
    AppLocalizations l10n,
    String rawTitle,
    String sourceTid,
  ) {
    return LibraryTitleFallbackPolicy.needsChapterFallback(rawTitle, sourceTid)
        ? l10n.novelChapterFallbackTitle(sourceTid)
        : rawTitle;
  }

  static String hydrationMessage(
    AppLocalizations l10n,
    NovelChapterHydrationViewState state,
  ) {
    if (state.status == NovelChapterHydrationViewStatus.failed) {
      return syncFailure(
        l10n,
        state.failureCode ?? NovelChapterSyncFailureCode.unknown,
        state.diagnosticDetail,
      );
    }
    if (state.status == NovelChapterHydrationViewStatus.recoveringMetadata) {
      return l10n.novelHydrationRecoveringMetadata;
    }
    final progress = state.progress;
    if (progress == null || progress.phase == NovelChapterSyncPhase.preparing) {
      return l10n.novelHydrationPreparing;
    }
    if (progress.phase == NovelChapterSyncPhase.committing) {
      return l10n.novelHydrationCommitting(progress.acceptedCount);
    }
    final currentPage = progress.currentPage ?? 1;
    final totalPages = progress.totalPages;
    return totalPages == null || totalPages < currentPage
        ? l10n.novelHydrationLoadingPage(currentPage, progress.acceptedCount)
        : l10n.novelHydrationLoadingPageOfTotal(
            currentPage,
            totalPages,
            progress.acceptedCount,
          );
  }

  static String syncFailure(
    AppLocalizations l10n,
    NovelChapterSyncFailureCode code,
    Object? detail,
  ) {
    return switch (code) {
      NovelChapterSyncFailureCode.missingSourceState =>
        l10n.novelHydrationMissingSource,
      NovelChapterSyncFailureCode.missingPublisherId =>
        l10n.novelHydrationMissingPublisher,
      NovelChapterSyncFailureCode.missingSourceTid =>
        l10n.novelHydrationMissingTid,
      NovelChapterSyncFailureCode.missingCheckpoint =>
        l10n.novelHydrationMissingCheckpoint,
      NovelChapterSyncFailureCode.interrupted => l10n.novelHydrationInterrupted,
      NovelChapterSyncFailureCode.synchronizationFailed =>
        l10n.novelChapterLoadFailed(LibraryErrorSummary.resolve(l10n, detail)),
      NovelChapterSyncFailureCode.unknown => l10n.novelChapterLoadUnknown,
    };
  }

  static String sourceRouteFailure(
    AppLocalizations l10n,
    NovelChapterSourceRouteException error,
  ) {
    return switch (error.code) {
      NovelChapterSourceRouteFailureCode.invalidTid =>
        l10n.novelSourceRouteInvalidTid,
      NovelChapterSourceRouteFailureCode.invalidPid =>
        l10n.novelSourceRouteInvalidPid,
      NovelChapterSourceRouteFailureCode.locatorFailed =>
        l10n.novelSourceRouteLocatorFailed(
          LibraryErrorSummary.resolve(l10n, error.detail),
        ),
      NovelChapterSourceRouteFailureCode.emptyResult =>
        l10n.novelSourceRouteEmptyResult,
      NovelChapterSourceRouteFailureCode.mismatchedResult =>
        l10n.novelSourceRouteMismatchedResult,
      NovelChapterSourceRouteFailureCode.invalidPage =>
        l10n.novelSourceRouteInvalidPage,
    };
  }

  static String readerFailure(AppLocalizations l10n, Object error) {
    if (error is NovelReaderLoadException) {
      return switch (error.code) {
        NovelReaderLoadFailureCode.noChapters => l10n.novelReaderNoChapters,
        NovelReaderLoadFailureCode.chapterContentMissing =>
          l10n.novelReaderContentMissing,
      };
    }
    return l10n.novelReaderLoadFailed(LibraryErrorSummary.resolve(l10n, error));
  }

  static String conversionMode(
    AppLocalizations l10n,
    NovelReaderConversionMode mode,
  ) {
    return switch (mode) {
      NovelReaderConversionMode.none => l10n.novelConversionOriginal,
      NovelReaderConversionMode.toSimplified => l10n.novelConversionSimplified,
      NovelReaderConversionMode.toTraditional =>
        l10n.novelConversionTraditional,
    };
  }

  static String flowMode(AppLocalizations l10n, NovelReaderFlowMode mode) {
    return switch (mode) {
      NovelReaderFlowMode.vertical => l10n.novelFlowScroll,
      NovelReaderFlowMode.pagedLtr => l10n.novelFlowPagedLtr,
      NovelReaderFlowMode.pagedRtl => l10n.novelFlowPagedRtl,
    };
  }

  static String chapterTurnHint(
    AppLocalizations l10n,
    NovelReaderChapterTurnHint hint,
  ) {
    final direction = hint.edge == NovelReaderChapterEdge.end
        ? 'next'
        : 'previous';
    final title = hint.chapterTitle.trim();
    if (!hint.isReadyToCommit || title.isEmpty) {
      return l10n.novelChapterTurnContinue(direction);
    }
    return l10n.novelChapterTurnRelease(direction, title);
  }
}

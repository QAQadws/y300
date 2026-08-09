import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/presentation/services/library_error_summary.dart';
import 'package:y300/features/library_shared/presentation/services/library_task_text_resolver.dart';
import 'package:y300/features/library_shared/presentation/services/library_title_fallback_policy.dart';
import 'package:y300/l10n/app_localizations.dart';

abstract final class LibraryDetailTextResolver {
  static String safeError(AppLocalizations l10n, Object? error) {
    return LibraryErrorSummary.resolve(l10n, error);
  }

  static String refreshOutcome(
    AppLocalizations l10n,
    DetailRefreshResult result,
  ) {
    return switch (result.outcomeCode) {
      DetailRefreshOutcomeCode.updated => l10n.libraryDetailRefreshUpdated,
      DetailRefreshOutcomeCode.chaptersChanged =>
        l10n.libraryDetailRefreshChaptersChanged(
          result.insertedCount,
          result.updatedCount,
        ),
      DetailRefreshOutcomeCode.alreadyCurrent =>
        l10n.libraryDetailRefreshAlreadyCurrent,
      DetailRefreshOutcomeCode.noUpdates => l10n.libraryDetailRefreshNoUpdates,
      DetailRefreshOutcomeCode.queued => _queuedRefresh(l10n, result),
      DetailRefreshOutcomeCode.unavailable =>
        l10n.libraryDetailRefreshUnavailable,
    };
  }

  static String metadataField(
    AppLocalizations l10n,
    LibraryMetadataField field,
  ) {
    return switch (field) {
      LibraryMetadataField.title => l10n.libraryDetailMetadataTitle,
      LibraryMetadataField.author => l10n.libraryDetailAuthor,
      LibraryMetadataField.translationGroup =>
        l10n.libraryDetailTranslationGroup,
      LibraryMetadataField.searchTitle => l10n.libraryDetailMetadataSearchTitle,
    };
  }

  static String metadataSourceField(
    AppLocalizations l10n,
    LibraryMetadataField field,
  ) {
    return switch (field) {
      LibraryMetadataField.title => l10n.libraryDetailMetadataSourceTitle,
      LibraryMetadataField.author => l10n.libraryDetailMetadataSourceAuthor,
      LibraryMetadataField.translationGroup =>
        l10n.libraryDetailMetadataSourceTranslationGroup,
      LibraryMetadataField.searchTitle => l10n.libraryDetailMetadataSearchTitle,
    };
  }

  static String sourceValue(
    AppLocalizations l10n,
    String label,
    String? value,
  ) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty
        ? l10n.libraryDetailSourceEmpty(label)
        : l10n.libraryDetailSourceValue(label, normalized);
  }

  static String chapterTitle(
    AppLocalizations l10n,
    String title,
    String? sourceTid,
  ) {
    if (!LibraryTitleFallbackPolicy.needsChapterFallback(title, sourceTid)) {
      return title;
    }
    return l10n.libraryChapterFallbackTitle(sourceTid?.trim() ?? '-');
  }

  static String chapterProgress(
    AppLocalizations l10n,
    LibraryChapterProgressInfo progress,
  ) {
    return switch (progress.kind) {
      LibraryChapterProgressKind.currentPage => _currentPage(l10n, progress),
      LibraryChapterProgressKind.lastRead => l10n.libraryChapterLastRead,
    };
  }

  static String manualChapterInputError(
    AppLocalizations l10n,
    DetailManualChapterAddOutcome outcome,
  ) {
    final code = outcome.inputErrorCode;
    return switch (code) {
      DetailManualChapterInputErrorCode.emptyInput =>
        l10n.libraryChapterInputEmpty,
      DetailManualChapterInputErrorCode.invalidUrl =>
        l10n.libraryChapterInputInvalidUrl,
      DetailManualChapterInputErrorCode.unsupportedScheme =>
        l10n.libraryChapterInputUnsupportedScheme,
      DetailManualChapterInputErrorCode.unexpectedHost => _manualUnexpectedHost(
        l10n,
        outcome.expectedHost,
      ),
      DetailManualChapterInputErrorCode.unsupportedThreadUrl =>
        l10n.libraryChapterInputUnsupportedThreadUrl,
      DetailManualChapterInputErrorCode.missingTid =>
        l10n.libraryChapterInputMissingTid,
      null => l10n.commonUnknownError,
    };
  }

  static String catalogInputError(
    AppLocalizations l10n,
    DetailCatalogUpdateOutcome outcome,
  ) {
    final code = outcome.inputErrorCode;
    return switch (code) {
      DetailCatalogInputErrorCode.invalidUrl =>
        l10n.libraryDetailCatalogInvalidUrl,
      DetailCatalogInputErrorCode.incompleteUrl =>
        l10n.libraryDetailCatalogIncompleteUrl,
      DetailCatalogInputErrorCode.unsupportedScheme =>
        l10n.libraryDetailCatalogUnsupportedScheme,
      DetailCatalogInputErrorCode.unexpectedHost => _catalogUnexpectedHost(
        l10n,
        outcome.expectedHost,
      ),
      DetailCatalogInputErrorCode.notTagCatalog =>
        l10n.libraryDetailCatalogNotTagCatalog,
      null => l10n.commonUnknownError,
    };
  }

  static String chapterRemovalOutcome(
    AppLocalizations l10n,
    DetailChapterRemovalResult result,
  ) {
    if (!result.removed) {
      if (result.rejectionCode ==
          DetailChapterRemovalRejectionCode.lastVisible) {
        return l10n.libraryChapterKeepOneVisible;
      }
      return l10n.libraryChapterParsedCannotRemove;
    }
    if (result.warnings.isEmpty) {
      return l10n.libraryChapterRemoved;
    }
    final warnings = result.warnings
        .map((warning) {
          return switch (warning) {
            DetailChapterRemovalWarningCode.downloadTaskCleanupFailed =>
              l10n.libraryChapterDownloadTaskCleanupFailed,
            DetailChapterRemovalWarningCode.downloadFileCleanupFailed =>
              l10n.libraryChapterDownloadFileCleanupFailed,
          };
        })
        .join('、');
    return l10n.libraryChapterRemovedWithWarnings(warnings);
  }

  static String _queuedRefresh(
    AppLocalizations l10n,
    DetailRefreshResult result,
  ) {
    final duration = LibraryTaskTextResolver.duration(
      l10n,
      result.estimatedDuration ?? Duration.zero,
    );
    final position = result.queuePosition;
    return position == null
        ? l10n.libraryDetailRefreshQueued(duration)
        : l10n.libraryDetailRefreshQueuedAtPosition(position, duration);
  }

  static String _currentPage(
    AppLocalizations l10n,
    LibraryChapterProgressInfo progress,
  ) {
    final page = progress.currentPage ?? 1;
    return l10n.libraryChapterCurrentPage(page);
  }

  static String _manualUnexpectedHost(
    AppLocalizations l10n,
    String? expectedHost,
  ) {
    final host = expectedHost?.trim();
    return host == null || host.isEmpty
        ? l10n.libraryChapterInputInvalidUrl
        : l10n.libraryChapterInputUnexpectedHost(host);
  }

  static String _catalogUnexpectedHost(
    AppLocalizations l10n,
    String? expectedHost,
  ) {
    final host = expectedHost?.trim();
    return host == null || host.isEmpty
        ? l10n.libraryDetailCatalogInvalidUrl
        : l10n.libraryDetailCatalogUnexpectedHost(host);
  }
}

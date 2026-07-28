import 'package:y300/features/library_shared/domain/contracts/shelf_selection_action_adapter.dart';
import 'package:y300/l10n/app_localizations.dart';

/// Resolves shared selection action copy without putting UI text in adapters.
final class SelectionActionTextResolver {
  const SelectionActionTextResolver._();

  static String label(AppLocalizations l10n, String actionId) {
    return switch (actionId) {
      SelectionActionIds.assignCategory =>
        l10n.librarySelectionActionAssignCategory,
      SelectionActionIds.markAllRead => l10n.librarySelectionActionMarkAllRead,
      SelectionActionIds.markAllUnread =>
        l10n.librarySelectionActionMarkAllUnread,
      SelectionActionIds.download => l10n.librarySelectionActionDownload,
      SelectionActionIds.unfavorite => l10n.librarySelectionActionUnfavorite,
      _ => l10n.librarySelectionActionGeneric,
    };
  }

  static String resultMessage(
    AppLocalizations l10n,
    String actionId,
    SelectionActionOutcome result,
  ) {
    final actionLabel = label(l10n, actionId);
    switch (result.code) {
      case SelectionActionOutcomeCode.success:
        return _successMessage(l10n, actionId, result, actionLabel);
      case SelectionActionOutcomeCode.partialFailure:
        return _partialFailureMessage(l10n, actionId, result, actionLabel);
      case SelectionActionOutcomeCode.unsupported:
        return l10n.librarySelectionUnsupported(actionLabel);
      case SelectionActionOutcomeCode.missingTargetCategory:
        return l10n.librarySelectionMissingTargetCategory;
      case SelectionActionOutcomeCode.noValidItems:
        return l10n.librarySelectionNoValidItems;
      case SelectionActionOutcomeCode.noChange:
        if (actionId == SelectionActionIds.download) {
          return result.deduplicatedCount > 0
              ? l10n.librarySelectionDownloadAlreadyQueued
              : l10n.librarySelectionNothingToDownload;
        }
        return l10n.librarySelectionNoChange(actionLabel);
    }
  }

  static String _successMessage(
    AppLocalizations l10n,
    String actionId,
    SelectionActionOutcome result,
    String actionLabel,
  ) {
    switch (actionId) {
      case SelectionActionIds.assignCategory:
        return l10n.librarySelectionCategoryAssigned(result.succeededCount);
      case SelectionActionIds.markAllRead:
        return l10n.librarySelectionReadStateChanged(
          result.succeededCount,
          l10n.librarySelectionRead,
        );
      case SelectionActionIds.markAllUnread:
        return l10n.librarySelectionReadStateChanged(
          result.succeededCount,
          l10n.librarySelectionUnread,
        );
      case SelectionActionIds.download:
        return result.enqueuedCount > 0
            ? l10n.librarySelectionDownloadQueued(result.enqueuedCount)
            : result.deduplicatedCount > 0
            ? l10n.librarySelectionDownloadAlreadyQueued
            : l10n.librarySelectionNothingToDownload;
      case SelectionActionIds.unfavorite:
        return l10n.librarySelectionUnfavorite(result.succeededCount);
      default:
        return l10n.librarySelectionNoChange(actionLabel);
    }
  }

  static String _partialFailureMessage(
    AppLocalizations l10n,
    String actionId,
    SelectionActionOutcome result,
    String actionLabel,
  ) {
    switch (actionId) {
      case SelectionActionIds.assignCategory:
        return l10n.librarySelectionCategoryAssignedPartial(
          result.succeededCount,
          result.failedCount,
        );
      case SelectionActionIds.markAllRead:
        return l10n.librarySelectionReadStateChangedPartial(
          result.succeededCount,
          result.failedCount,
          l10n.librarySelectionRead,
        );
      case SelectionActionIds.markAllUnread:
        return l10n.librarySelectionReadStateChangedPartial(
          result.succeededCount,
          result.failedCount,
          l10n.librarySelectionUnread,
        );
      case SelectionActionIds.download:
        return l10n.librarySelectionDownloadQueuedPartial(
          result.enqueuedCount,
          result.failedCount,
        );
      case SelectionActionIds.unfavorite:
        return l10n.librarySelectionUnfavoritePartial(
          result.succeededCount,
          result.failedCount,
        );
      default:
        return l10n.librarySelectionNoChange(actionLabel);
    }
  }
}

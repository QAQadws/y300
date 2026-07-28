import 'package:y300/features/library_shared/domain/contracts/shelf_selection_action_adapter.dart';
import 'package:y300/l10n/app_localizations.dart';

/// Resolves shared selection action copy without putting UI text in adapters.
final class SelectionActionTextResolver {
  const SelectionActionTextResolver._();

  static String label(AppLocalizations l10n, String actionId) {
    return switch (actionId) {
      SelectionActionIds.assignCategory =>
        l10n.startupSelectionActionAssignCategory,
      SelectionActionIds.markAllRead => l10n.startupSelectionActionMarkAllRead,
      SelectionActionIds.markAllUnread =>
        l10n.startupSelectionActionMarkAllUnread,
      SelectionActionIds.download => l10n.startupSelectionActionDownload,
      SelectionActionIds.unfavorite => l10n.startupSelectionActionUnfavorite,
      _ => l10n.startupSelectionActionGeneric,
    };
  }

  static String resultMessage(
    AppLocalizations l10n,
    String actionId,
    SelectionActionResult result,
  ) {
    final actionLabel = label(l10n, actionId);
    switch (result.code) {
      case SelectionActionResultCode.legacyMessage:
        final legacy = result.message?.trim();
        return legacy == null || legacy.isEmpty
            ? l10n.startupSelectionNoChange(actionLabel)
            : legacy;
      case SelectionActionResultCode.success:
        return _successMessage(l10n, actionId, result, actionLabel);
      case SelectionActionResultCode.partialFailure:
        return _partialFailureMessage(l10n, actionId, result, actionLabel);
      case SelectionActionResultCode.unsupported:
        return l10n.startupSelectionUnsupported(actionLabel);
      case SelectionActionResultCode.missingTargetCategory:
        return l10n.startupSelectionMissingTargetCategory;
      case SelectionActionResultCode.noValidItems:
        return l10n.startupSelectionNoValidItems;
      case SelectionActionResultCode.noChange:
        if (actionId == SelectionActionIds.download) {
          return result.deduplicatedCount > 0
              ? l10n.startupSelectionDownloadAlreadyQueued
              : l10n.startupSelectionNothingToDownload;
        }
        return l10n.startupSelectionNoChange(actionLabel);
    }
  }

  static String _successMessage(
    AppLocalizations l10n,
    String actionId,
    SelectionActionResult result,
    String actionLabel,
  ) {
    switch (actionId) {
      case SelectionActionIds.assignCategory:
        return l10n.startupSelectionCategoryAssigned(result.succeededCount);
      case SelectionActionIds.markAllRead:
        return l10n.startupSelectionReadStateChanged(
          result.succeededCount,
          l10n.startupSelectionRead,
        );
      case SelectionActionIds.markAllUnread:
        return l10n.startupSelectionReadStateChanged(
          result.succeededCount,
          l10n.startupSelectionUnread,
        );
      case SelectionActionIds.download:
        return result.enqueuedCount > 0
            ? l10n.startupSelectionDownloadQueued(result.enqueuedCount)
            : result.deduplicatedCount > 0
            ? l10n.startupSelectionDownloadAlreadyQueued
            : l10n.startupSelectionNothingToDownload;
      case SelectionActionIds.unfavorite:
        return l10n.startupSelectionUnfavorite(result.succeededCount);
      default:
        return l10n.startupSelectionNoChange(actionLabel);
    }
  }

  static String _partialFailureMessage(
    AppLocalizations l10n,
    String actionId,
    SelectionActionResult result,
    String actionLabel,
  ) {
    switch (actionId) {
      case SelectionActionIds.assignCategory:
        return l10n.startupSelectionCategoryAssignedPartial(
          result.succeededCount,
          result.failedCount,
        );
      case SelectionActionIds.markAllRead:
        return l10n.startupSelectionReadStateChangedPartial(
          result.succeededCount,
          result.failedCount,
          l10n.startupSelectionRead,
        );
      case SelectionActionIds.markAllUnread:
        return l10n.startupSelectionReadStateChangedPartial(
          result.succeededCount,
          result.failedCount,
          l10n.startupSelectionUnread,
        );
      case SelectionActionIds.download:
        return l10n.startupSelectionDownloadQueuedPartial(
          result.enqueuedCount,
          result.failedCount,
        );
      case SelectionActionIds.unfavorite:
        return l10n.startupSelectionUnfavoritePartial(
          result.succeededCount,
          result.failedCount,
        );
      default:
        return l10n.startupSelectionNoChange(actionLabel);
    }
  }
}

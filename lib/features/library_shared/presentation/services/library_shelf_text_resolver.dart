import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/presentation/services/library_error_summary.dart';
import 'package:y300/l10n/app_localizations.dart';

abstract final class LibraryShelfTextResolver {
  static String moduleTitle(AppLocalizations l10n, LibraryModuleKey moduleKey) {
    return l10n.libraryShelfTitle(moduleKey.name);
  }

  static String categoryName(AppLocalizations l10n, LibraryCategory category) {
    return category.isDefault
        ? l10n.libraryShelfDefaultCategory
        : category.name;
  }

  static String categoryLabel(
    AppLocalizations l10n,
    LibraryCategory category, {
    required bool showMatchCount,
    required int matchCount,
  }) {
    final name = categoryName(l10n, category);
    return showMatchCount
        ? l10n.libraryShelfCategoryMatchCount(name, matchCount)
        : name;
  }

  static String menuAction(
    AppLocalizations l10n,
    LibraryShelfMenuAction action,
  ) {
    return switch (action) {
      LibraryShelfMenuAction.mergeDuplicates =>
        l10n.libraryShelfMergeDuplicates,
    };
  }

  static String menuOutcome(
    AppLocalizations l10n,
    LibraryShelfMenuAction action,
    ShelfModuleActionOutcome outcome,
  ) {
    return switch ((action, outcome.code)) {
      (
        LibraryShelfMenuAction.mergeDuplicates,
        ShelfModuleActionOutcomeCode.success,
      ) =>
        l10n.libraryShelfMergeDuplicatesSuccess(outcome.affectedCount),
      (
        LibraryShelfMenuAction.mergeDuplicates,
        ShelfModuleActionOutcomeCode.noChange,
      ) =>
        l10n.libraryShelfMergeDuplicatesNoChange,
      (_, ShelfModuleActionOutcomeCode.unsupported) =>
        l10n.libraryShelfActionUnsupported,
    };
  }

  static String sortField(AppLocalizations l10n, LibraryShelfSortField field) {
    return switch (field) {
      LibraryShelfSortField.name => l10n.libraryShelfSortName,
      LibraryShelfSortField.chapterCount => l10n.libraryShelfSortChapterCount,
      LibraryShelfSortField.lastReadAt => l10n.libraryShelfSortLastReadAt,
      LibraryShelfSortField.lastCheckedAt => l10n.libraryShelfSortLastCheckedAt,
      LibraryShelfSortField.unreadCount => l10n.libraryShelfSortUnreadCount,
      LibraryShelfSortField.workUpdatedAt => l10n.libraryShelfSortWorkUpdatedAt,
      LibraryShelfSortField.fetchedAt => l10n.libraryShelfSortFetchedAt,
      LibraryShelfSortField.favoriteAddedAt =>
        l10n.libraryShelfSortFavoriteAddedAt,
    };
  }

  static String loadError(AppLocalizations l10n, Object? error) {
    return l10n.libraryShelfLoadFailed(
      LibraryErrorSummary.resolve(l10n, error),
    );
  }
}

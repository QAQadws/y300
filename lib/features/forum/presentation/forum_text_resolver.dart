import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/forum/domain/models/forum_webview_models.dart';
import 'package:y300/features/forum/presentation/forum_display_state.dart';
import 'package:y300/features/forum/presentation/forum_home_state.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_state.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';

/// Presentation-only mapping for forum UI text.
///
/// Forum/domain models intentionally keep server strings raw. This resolver
/// owns the boundary where stable forum state becomes application UI text.
final class ForumTextResolver {
  const ForumTextResolver._();

  static String sectionTitle(AppLocalizations l10n, ForumSection section) {
    return switch (section.type) {
      ForumSectionType.favorite => l10n.forumHomeFavoriteForums,
      ForumSectionType.uncategorized => l10n.forumHomeUncategorized,
      ForumSectionType.regular => section.title,
    };
  }

  static String forumDisplayTitle(AppLocalizations l10n, String rawTitle) {
    final title = rawTitle.trim();
    return title.isEmpty ? l10n.forumDisplayTitle : title;
  }

  static String forumShellModeLabel(
    AppLocalizations l10n,
    ForumShellMode mode,
  ) {
    return switch (mode) {
      ForumShellMode.native => l10n.forumShellNative,
      ForumShellMode.webview => l10n.forumShellWebView,
    };
  }

  static String webViewTitle(AppLocalizations l10n, ForumWebViewState state) {
    final boardName = state.boardName?.trim();
    final pageTitle = state.pageTitle?.trim();
    final fid = state.fid?.trim();

    return switch (state.pageKind) {
      ForumWebViewPageKind.home => l10n.forumHomeTitle,
      ForumWebViewPageKind.forumDisplay || ForumWebViewPageKind.threadDetail =>
        boardName?.isNotEmpty == true
            ? boardName!
            : fid?.isNotEmpty == true
            ? l10n.forumForumByFid(fid!)
            : l10n.forumHomeTitle,
      ForumWebViewPageKind.search =>
        state.searchScope == ForumWebViewSearchScope.curForum
            ? boardName?.isNotEmpty == true
                  ? l10n.forumWebViewForumSearch(boardName!)
                  : fid?.isNotEmpty == true
                  ? l10n.forumForumByFid(fid!)
                  : l10n.forumWebViewSearchForum
            : l10n.forumWebViewSearchForum,
      ForumWebViewPageKind.other =>
        pageTitle?.isNotEmpty == true ? pageTitle! : l10n.forumHomeTitle,
    };
  }

  static String searchTooltip(AppLocalizations l10n, ForumWebViewState state) {
    return state.pageKind == ForumWebViewPageKind.forumDisplay &&
            (state.fid ?? '').trim().isNotEmpty
        ? l10n.forumDisplaySearch
        : l10n.forumHomeSearch;
  }

  static String homeNotice(AppLocalizations l10n, ForumHomeNotice notice) {
    return switch (notice.code) {
      ForumHomeNoticeCode.refreshFailed => l10n.forumHomeRefreshFailed(
        _detailOrUnknown(l10n, notice.detail),
      ),
    };
  }

  static String homeLoadFailure(AppLocalizations l10n, Object? error) {
    return l10n.forumHomeLoadFailed(_detailOrUnknown(l10n, error));
  }

  static String displayFailure(
    AppLocalizations l10n,
    ForumDisplayFailure failure,
  ) {
    return switch (failure.code) {
      ForumDisplayFailureCode.loadFailed => l10n.forumDisplayLoadFailed(
        _detailOrUnknown(l10n, failure.detail),
      ),
    };
  }

  static String legacyDisplayFailure(AppLocalizations l10n, String? detail) {
    return l10n.forumDisplayLoadFailed(_detailOrUnknown(l10n, detail));
  }

  static String favoriteActionFailure(AppLocalizations l10n, Object? error) {
    return l10n.forumActionFailed(LocalizedErrorSummary.resolve(l10n, error));
  }

  static String favoriteForumsLoadFailure(
    AppLocalizations l10n,
    Object? error,
  ) {
    return l10n.forumFavoriteForumsLoadFailed(_detailOrUnknown(l10n, error));
  }

  static String safeErrorSummary(Object? error) {
    return _safeErrorSummary(error);
  }

  static String _safeErrorSummary(Object? error) {
    var value = error?.toString().trim() ?? '';
    if (value.isEmpty) {
      return '';
    }
    value = value.replaceAll(RegExp(r'\s+'), ' ');
    value = value.replaceAll(
      RegExp(r'https?://\S+', caseSensitive: false),
      '[url]',
    );
    value = value.replaceAll(
      RegExp(
        r'(cookie|formhash|uploadhash)\s*[:=]\s*\S+',
        caseSensitive: false,
      ),
      '[redacted]',
    );
    if (value.length > 160) {
      value = '${value.substring(0, 157)}...';
    }
    return value;
  }

  static String _detailOrUnknown(AppLocalizations l10n, Object? error) {
    final detail = _safeErrorSummary(error);
    return detail.isEmpty ? l10n.commonUnknownError : detail;
  }
}

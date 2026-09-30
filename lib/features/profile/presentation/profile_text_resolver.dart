import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/services/localized_error_summary.dart';

abstract final class ProfileTextResolver {
  static String blogReadError(AppLocalizations l10n, Object? error) =>
      switch (error) {
        DataReadFailure(code: 'user_blog_password_required') =>
          l10n.profileBlogReadPasswordRequired,
        DataReadFailure(code: 'user_blog_private') => l10n.profileBlogPrivate,
        DataReadFailure(code: 'user_blog_unavailable') =>
          l10n.profileBlogUnavailable,
        DataReadFailure(kind: DataReadFailureKind.unauthorized) =>
          l10n.threadLoginRequired,
        _ => l10n.profileBlogLoadFailed(
          LocalizedErrorSummary.resolve(l10n, error),
        ),
      };

  static String blogView(AppLocalizations l10n, UserBlogFeedScope view) {
    return switch (view) {
      UserBlogFeedScope.friends => l10n.profileBlogFriends,
      UserBlogFeedScope.self => l10n.profileBlogMine,
      UserBlogFeedScope.public => l10n.profileBlogExplore,
    };
  }

  static String blogOrder(AppLocalizations l10n, UserBlogOrder order) {
    return switch (order) {
      UserBlogOrder.latest => l10n.profileBlogLatest,
      UserBlogOrder.recommended => l10n.profileBlogRecommended,
    };
  }

  static String blogOrderShort(AppLocalizations l10n, UserBlogOrder order) {
    return switch (order) {
      UserBlogOrder.latest => l10n.profileBlogLatestShort,
      UserBlogOrder.recommended => l10n.profileBlogRecommendedShort,
    };
  }
}

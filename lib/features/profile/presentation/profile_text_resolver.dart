import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/l10n/app_localizations.dart';

abstract final class ProfileTextResolver {
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
}

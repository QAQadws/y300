import 'package:y300/features/profile/data/models/profile_blog_models.dart';
import 'package:y300/l10n/app_localizations.dart';

abstract final class ProfileTextResolver {
  static String blogView(AppLocalizations l10n, ProfileBlogView view) {
    return switch (view) {
      ProfileBlogView.friends => l10n.profileBlogFriends,
      ProfileBlogView.mine => l10n.profileBlogMine,
      ProfileBlogView.all => l10n.profileBlogExplore,
    };
  }

  static String blogOrder(AppLocalizations l10n, ProfileBlogOrder order) {
    return switch (order) {
      ProfileBlogOrder.latest => l10n.profileBlogLatest,
      ProfileBlogOrder.hot => l10n.profileBlogRecommended,
    };
  }
}

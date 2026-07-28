import 'package:flutter/material.dart';
import 'package:y300/app/navigation/main_navigation_settings.dart';
import 'package:y300/l10n/app_localizations.dart';

extension MainShellDestinationPresentation on MainShellDestination {
  String localizedLabel(AppLocalizations l10n) {
    return switch (this) {
      MainShellDestination.forum => l10n.appNavigationForum,
      MainShellDestination.favorites => l10n.appNavigationFavorites,
      MainShellDestination.comic => l10n.appNavigationComic,
      MainShellDestination.novel => l10n.appNavigationNovel,
      MainShellDestination.history => l10n.appNavigationHistory,
      MainShellDestination.more => l10n.appNavigationMore,
    };
  }

  IconData get icon {
    return switch (this) {
      MainShellDestination.forum => Icons.forum_outlined,
      MainShellDestination.favorites => Icons.explore_outlined,
      MainShellDestination.comic => Icons.collections_bookmark_outlined,
      MainShellDestination.novel => Icons.local_library_outlined,
      MainShellDestination.history => Icons.history_outlined,
      MainShellDestination.more => Icons.more_horiz_outlined,
    };
  }

  IconData get selectedIcon {
    return switch (this) {
      MainShellDestination.forum => Icons.forum,
      MainShellDestination.favorites => Icons.explore,
      MainShellDestination.comic => Icons.collections_bookmark,
      MainShellDestination.novel => Icons.local_library,
      MainShellDestination.history => Icons.history,
      MainShellDestination.more => Icons.more_horiz,
    };
  }
}

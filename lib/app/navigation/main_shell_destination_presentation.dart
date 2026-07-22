import 'package:flutter/material.dart';
import 'package:y300/app/navigation/main_navigation_settings.dart';

extension MainShellDestinationPresentation on MainShellDestination {
  String get displayLabel {
    return switch (this) {
      MainShellDestination.forum => '论坛',
      MainShellDestination.favorites => '收藏',
      MainShellDestination.comic => '漫画',
      MainShellDestination.novel => '小说',
      MainShellDestination.history => '记录',
      MainShellDestination.more => '更多',
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

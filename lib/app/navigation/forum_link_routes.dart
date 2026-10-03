import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/navigation/friend_routes.dart';
import 'package:y300/features/forum/domain/services/yamibo_forum_link_resolver.dart';
import 'package:y300/features/forum/presentation/forum_display_page.dart';
import 'package:y300/features/forum/presentation/forum_home_page.dart';
import 'package:y300/features/profile/presentation/threads/user_thread_page.dart';
import 'package:y300/features/search/presentation/forum_search_page.dart';
import 'package:y300/features/tags/presentation/yamibo_tag_thread_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

typedef NativeForumLinkPageFactory =
    Widget? Function(YamiboForumLinkDestination destination, {bool isActive});

final nativeForumLinkPageFactoryProvider = Provider<NativeForumLinkPageFactory>(
  (ref) => nativeForumLinkPage,
);

/// App composition owns cross-feature pages. Post targets require the existing
/// asynchronous locator and are deliberately handled by the calling flow.
Widget? nativeForumLinkPage(
  YamiboForumLinkDestination destination, {
  bool isActive = true,
}) {
  if (!isActive &&
      destination.kind != YamiboForumLinkKind.home &&
      destination.kind != YamiboForumLinkKind.friendFeed &&
      destination.kind != YamiboForumLinkKind.userThreadDirectory) {
    return const SizedBox.shrink();
  }
  return switch (destination.kind) {
    YamiboForumLinkKind.home => ForumHomePage(isActive: isActive),
    YamiboForumLinkKind.forumDisplay => ForumDisplayPage(
      fid: destination.forumId!,
      initialPage: destination.page ?? 1,
    ),
    YamiboForumLinkKind.search => ForumSearchPage(
      scope: destination.searchScope!,
      forumId: destination.forumId,
    ),
    YamiboForumLinkKind.thread => ThreadDetailPage(
      tid: destination.tid!,
      initialPage: destination.page ?? 1,
    ),
    YamiboForumLinkKind.tagThreadPage => YamiboTagThreadPage(
      tagId: destination.tagId!,
      page: destination.page ?? 1,
    ),
    YamiboForumLinkKind.userThreadDirectory => UserThreadPage(
      userId: destination.userId,
      initialType: destination.userThreadType!,
      initialPage: destination.page ?? 1,
      isActive: isActive,
    ),
    YamiboForumLinkKind.friendFeed => MyFriendsDestination(
      initialScope: destination.friendScope!,
      initialPage: destination.page ?? 1,
      isActive: isActive,
    ),
    YamiboForumLinkKind.threadPost ||
    YamiboForumLinkKind.managedWebView ||
    YamiboForumLinkKind.external => null,
  };
}

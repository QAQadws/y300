import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/profile/presentation/my_message_center_page.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';

/// Routes only protocol-approved action kinds. No page-provided href reaches
/// Navigator; WebView destinations are built from fixed application paths.
void openMyProfileAction({
  required BuildContext context,
  required WidgetRef ref,
  required ForumUserProfileActionKind action,
  required String userId,
  required bool Function() isCurrentOwner,
}) {
  if (!isCurrentOwner()) return;
  switch (action) {
    case ForumUserProfileActionKind.blogs:
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const ProfileBlogPage(initialScope: UserBlogFeedScope.self),
        ),
      );
      return;
    case ForumUserProfileActionKind.messages:
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const MyMessageCenterPage()),
      );
      return;
    case ForumUserProfileActionKind.threads:
    case ForumUserProfileActionKind.forumFavorites:
    case ForumUserProfileActionKind.friends:
    case ForumUserProfileActionKind.settings:
    case ForumUserProfileActionKind.creditHistory:
      Navigator.of(context).push(
        ref.read(forumWebViewRouteFactoryProvider)(
          ForumWebViewLaunchConfig(
            initialUri: _myProfileWebUri(action, userId),
            popOnRootBack: true,
          ),
        ),
      );
      return;
  }
}

/// Opens the fixed forum profile page only after the caller verifies the
/// current session owner. No URL from a failed response is reused here.
void openMyProfileForumPage({
  required BuildContext context,
  required WidgetRef ref,
  required String userId,
}) {
  final uri = Uri.parse(AppConfig.siteBaseUrl).replace(
    path: '/home.php',
    queryParameters: <String, String>{
      'mod': 'space',
      'uid': userId,
      'do': 'profile',
      'mycenter': '1',
      'mobile': '2',
    },
  );
  Navigator.of(context).push(
    ref.read(forumWebViewRouteFactoryProvider)(
      ForumWebViewLaunchConfig(initialUri: uri, popOnRootBack: true),
    ),
  );
}

Uri _myProfileWebUri(ForumUserProfileActionKind action, String uid) {
  final parameters = switch (action) {
    ForumUserProfileActionKind.threads => <String, String>{
      'mod': 'space',
      'uid': uid,
      'do': 'thread',
      'view': 'me',
      'mobile': '2',
    },
    ForumUserProfileActionKind.forumFavorites => <String, String>{
      'mod': 'space',
      'uid': uid,
      'do': 'favorite',
      'view': 'me',
      'type': 'thread',
      'mobile': '2',
    },
    ForumUserProfileActionKind.friends => <String, String>{
      'mod': 'space',
      'do': 'friend',
      'mobile': '2',
    },
    ForumUserProfileActionKind.settings => <String, String>{
      'mod': 'spacecp',
      'mobile': '2',
    },
    ForumUserProfileActionKind.creditHistory => <String, String>{
      'mod': 'spacecp',
      'ac': 'credit',
      'op': 'log',
    },
    ForumUserProfileActionKind.blogs || ForumUserProfileActionKind.messages =>
      throw ArgumentError.value(action, 'action', 'Native route only'),
  };
  return Uri.parse(
    AppConfig.siteBaseUrl,
  ).replace(path: '/home.php', queryParameters: parameters);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/navigation/message_routes.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/features/profile/presentation/profile_friend_action_sheet.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/features/profile/presentation/threads/my_thread_page.dart';

/// Native destinations remain useful while the remote profile is loading.
/// Session-sensitive entries still verify their owner at the point of opening.
Future<Object?> openProfileNativeAction({
  required BuildContext context,
  required WidgetRef ref,
  required ForumUserProfileActionKind action,
  required String userId,
  required bool isMyProfile,
  required bool Function() isCurrentOwner,
  String? displayName,
}) {
  if (!context.mounted ||
      !isCurrentOwner() ||
      !_positiveUserId(userId) ||
      (ModalRoute.of(context)?.isCurrent == false)) {
    return Future.value();
  }
  final owner = ref.read(verifiedProfileOwnerProvider);
  if (isMyProfile && owner?.uid != userId) return Future.value();
  final Widget destination;
  switch (action) {
    case ForumUserProfileActionKind.threads:
    case ForumUserProfileActionKind.replies:
      final type = action == ForumUserProfileActionKind.replies
          ? UserThreadDirectoryType.replies
          : UserThreadDirectoryType.threads;
      destination = isMyProfile
          ? MyThreadPage(initialType: type)
          : UserThreadPage(userId: userId, initialType: type);
    case ForumUserProfileActionKind.blogs:
      destination = ProfileBlogPage(
        ownerUserId: isMyProfile ? null : userId,
        initialScope: UserBlogFeedScope.self,
      );
    case ForumUserProfileActionKind.messages:
      if (!isMyProfile || owner == null) return Future.value();
      destination = const MessageCenterDestination();
    case ForumUserProfileActionKind.sendMessage:
      if (isMyProfile || owner == null || owner.uid == userId) {
        return Future.value();
      }
      return Navigator.of(context).push<Object?>(
        ref.read(privateConversationRouteFactoryProvider)(
          ForumConversationTarget.direct(userId),
          title: displayName?.trim().isNotEmpty == true ? displayName! : userId,
        ),
      );
    case ForumUserProfileActionKind.forumFavorites:
    case ForumUserProfileActionKind.friends:
    case ForumUserProfileActionKind.settings:
    case ForumUserProfileActionKind.creditHistory:
    case ForumUserProfileActionKind.addFriend:
    case ForumUserProfileActionKind.removeFriend:
      return Future.value();
  }
  return Navigator.of(
    context,
  ).push<Object?>(MaterialPageRoute<Object?>(builder: (_) => destination));
}

/// Opens an advertised capability. Web operations use the validated server
/// destination rather than reconstructing optional template parameters.
Future<Object?> openProfileAction({
  required BuildContext context,
  required WidgetRef ref,
  required ForumUserProfileActionKind action,
  required ForumUserProfileData profile,
  required bool isMyProfile,
  required bool Function() isCurrentOwner,
}) {
  final userId = profile.identity.userId;
  if (!context.mounted ||
      !isCurrentOwner() ||
      !profile.actions.contains(action) ||
      !_positiveUserId(userId) ||
      (ModalRoute.of(context)?.isCurrent == false)) {
    return Future.value();
  }
  final owner = ref.read(verifiedProfileOwnerProvider);
  if ((isMyProfile && owner?.uid != userId) ||
      (profile.viewerUserId != null && profile.viewerUserId != owner?.uid)) {
    return Future.value();
  }
  switch (action) {
    case ForumUserProfileActionKind.threads:
    case ForumUserProfileActionKind.replies:
    case ForumUserProfileActionKind.blogs:
    case ForumUserProfileActionKind.messages:
    case ForumUserProfileActionKind.sendMessage:
      return openProfileNativeAction(
        context: context,
        ref: ref,
        action: action,
        userId: userId,
        isMyProfile: isMyProfile,
        isCurrentOwner: isCurrentOwner,
        displayName: profile.identity.displayName,
      );
    case ForumUserProfileActionKind.addFriend:
    case ForumUserProfileActionKind.removeFriend:
      if (isMyProfile || owner == null || owner.uid == userId) {
        return Future.value();
      }
      final actionLink = _actionLink(profile, action);
      if (actionLink == null) return Future.value();
      return showProfileFriendAction(
        context: context,
        ref: ref,
        targetUserId: userId,
        actionLink: actionLink,
      );
    case ForumUserProfileActionKind.forumFavorites:
    case ForumUserProfileActionKind.friends:
    case ForumUserProfileActionKind.settings:
    case ForumUserProfileActionKind.creditHistory:
      if (!isMyProfile || owner == null) return Future.value();
      final actionLink = _actionLink(profile, action);
      if (actionLink == null) return Future.value();
      return Navigator.of(context).push<Object?>(
        ref.read(forumWebViewRouteFactoryProvider)(
          ForumWebViewLaunchConfig(
            initialUri: actionLink.uri,
            popOnRootBack: true,
            expectedAccountId: owner.uid,
          ),
        ),
      );
  }
}

Future<Object?> openProfileForumPage({
  required BuildContext context,
  required WidgetRef ref,
  required String userId,
  required bool isMyProfile,
  required bool Function() isCurrentOwner,
}) {
  if (!context.mounted ||
      !isCurrentOwner() ||
      !_positiveUserId(userId) ||
      (ModalRoute.of(context)?.isCurrent == false) ||
      (isMyProfile && ref.read(verifiedProfileOwnerProvider)?.uid != userId)) {
    return Future.value();
  }
  final uri = Uri.parse(AppConfig.siteBaseUrl).replace(
    path: '/home.php',
    queryParameters: <String, String>{
      'mod': 'space',
      'uid': userId,
      'do': 'profile',
      if (isMyProfile) 'mycenter': '1',
      'mobile': '2',
    },
  );
  return Navigator.of(context).push<Object?>(
    ref.read(forumWebViewRouteFactoryProvider)(
      ForumWebViewLaunchConfig(
        initialUri: uri,
        popOnRootBack: true,
        purpose: isMyProfile
            ? ForumWebViewHostPurpose.selfProfile
            : ForumWebViewHostPurpose.browse,
        expectedAccountId: ref.read(verifiedProfileOwnerProvider)?.uid,
      ),
    ),
  );
}

ForumUserProfileActionLink? _actionLink(
  ForumUserProfileData profile,
  ForumUserProfileActionKind kind,
) {
  final site = Uri.parse(AppConfig.siteBaseUrl);
  for (final link in profile.actionLinks) {
    final uri = link.uri;
    if (link.kind == kind &&
        uri.scheme == site.scheme &&
        uri.host == site.host &&
        uri.port == site.port &&
        uri.userInfo.isEmpty &&
        uri.path == '/home.php' &&
        !uri.hasFragment) {
      return link;
    }
  }
  return null;
}

bool _positiveUserId(String value) => RegExp(r'^[1-9]\d*$').hasMatch(value);

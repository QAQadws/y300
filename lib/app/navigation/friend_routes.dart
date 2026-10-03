import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/navigation/message_routes.dart';
import 'package:y300/features/profile/presentation/friends/my_friends_page.dart';

/// Source links use the shared opener; explicit friend actions use IDs.
class MyFriendsDestination extends ConsumerWidget {
  const MyFriendsDestination({
    super.key,
    this.isActive = true,
    this.initialScope = ForumFriendFeedScope.friends,
    this.initialPage = 1,
  });

  final bool isActive;
  final ForumFriendFeedScope initialScope;
  final int initialPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) => MyFriendsPage(
    isActive: isActive,
    initialScope: initialScope,
    initialPage: initialPage,
    onOpenLink: ref.watch(messageLinkOpenerProvider),
    onOpenConversation: (context, target, title) => Navigator.of(context).push(
      ref.read(privateConversationRouteFactoryProvider)(target, title: title),
    ),
  );
}

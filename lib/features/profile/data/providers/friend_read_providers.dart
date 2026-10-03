import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/profile/presentation/friends/my_friends_controller.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';

final friendFeedRepositoryProvider = Provider<ForumFriendFeedRepository>(
  (ref) => ref.watch(yamiboForumClientProvider).friendFeed!,
);

final friendRemovalCommandProvider = Provider<ForumFriendRemovalCommand>(
  (ref) => ref.watch(yamiboForumClientProvider).friendRemovalCommand!,
);

final myFriendsControllerProvider = Provider.autoDispose
    .family<MyFriendsController, MyFriendsPageArgs>((ref, args) {
      final owner = ref.watch(verifiedProfileOwnerProvider);
      final controller = MyFriendsController(
        repository: ref.watch(friendFeedRepositoryProvider),
        removalCommand: ref.watch(friendRemovalCommandProvider),
        owner: owner,
        currentOwner: () => ref.read(verifiedProfileOwnerProvider),
        args: args,
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

final currentUserProfileRepositoryProvider =
    Provider<CurrentUserProfileRepository>((ref) {
      return ref.watch(yamiboForumClientProvider).currentUserProfile!;
    });

final forumUserProfileRepositoryProvider = Provider<ForumUserProfileRepository>(
  (ref) {
    return ref.watch(yamiboForumClientProvider).forumUserProfile!;
  },
);

final userBlogDirectoryRepositoryProvider =
    Provider<UserBlogDirectoryRepository>((ref) {
      return ref.watch(yamiboForumClientProvider).userBlogDirectory!;
    });

final userBlogDetailRepositoryProvider = Provider<UserBlogDetailRepository>((
  ref,
) {
  return ref.watch(yamiboForumClientProvider).userBlogDetail!;
});

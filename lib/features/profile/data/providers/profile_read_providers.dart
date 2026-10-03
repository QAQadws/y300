import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

final currentUserProfileRepositoryProvider =
    Provider<CurrentUserProfileRepository>((ref) {
      return ref.watch(yamiboForumClientProvider).currentUserProfile!;
    });

final currentAccountSummaryRepositoryProvider =
    Provider<CurrentAccountSummaryRepository>((ref) {
      return ref.watch(yamiboForumClientProvider).currentAccountSummary!;
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

final userBlogCommentServiceProvider = Provider<UserBlogCommentService>((ref) {
  return ref.watch(yamiboForumClientProvider).blogComments!;
});

final userBlogNavigationProvider = Provider<UserBlogNavigation?>((ref) {
  return ref.watch(yamiboForumClientProvider).blogNavigation;
});

final userBlogOperationsProvider = Provider<UserBlogOperations>((ref) {
  return ref.watch(yamiboForumClientProvider).blogOperations!;
});

final userBlogMediaOperationsProvider = Provider<UserBlogMediaOperations?>((
  ref,
) {
  return ref.watch(yamiboForumClientProvider).blogMedia;
});

final forumFriendOperationsProvider = Provider<ForumFriendOperations>((ref) {
  return ref.watch(yamiboForumClientProvider).friendOperations!;
});

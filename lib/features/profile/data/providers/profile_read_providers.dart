import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/profile/domain/repositories/current_user_profile_repository.dart';
import 'package:y300/features/profile/domain/repositories/forum_user_profile_repository.dart';
import 'package:y300/features/profile/domain/repositories/user_blog_detail_repository.dart';
import 'package:y300/features/profile/domain/repositories/user_blog_directory_repository.dart';

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

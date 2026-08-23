import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/profile/data/repositories/current_user_profile_repository.dart';
import 'package:y300/features/profile/data/repositories/forum_user_profile_repository.dart';
import 'package:y300/features/profile/data/repositories/user_blog_detail_repository.dart';
import 'package:y300/features/profile/data/repositories/user_blog_directory_repository.dart';
import 'package:y300/features/profile/domain/repositories/current_user_profile_repository.dart';
import 'package:y300/features/profile/domain/repositories/forum_user_profile_repository.dart';
import 'package:y300/features/profile/domain/repositories/user_blog_detail_repository.dart';
import 'package:y300/features/profile/domain/repositories/user_blog_directory_repository.dart';

final currentUserProfileRepositoryProvider =
    Provider<CurrentUserProfileRepository>((ref) {
      return DiscuzCurrentUserProfileRepository(ref.watch(apiClientProvider));
    });

final forumUserProfileRepositoryProvider = Provider<ForumUserProfileRepository>(
  (ref) {
    return DiscuzForumUserProfileRepository(
      htmlClient: ref.watch(yamiboHtmlClientProvider),
    );
  },
);

final userBlogDirectoryRepositoryProvider =
    Provider<UserBlogDirectoryRepository>((ref) {
      return DiscuzUserBlogDirectoryRepository(
        htmlClient: ref.watch(yamiboHtmlClientProvider),
      );
    });

final userBlogDetailRepositoryProvider = Provider<UserBlogDetailRepository>((
  ref,
) {
  return DiscuzUserBlogDetailRepository(
    htmlClient: ref.watch(yamiboHtmlClientProvider),
  );
});

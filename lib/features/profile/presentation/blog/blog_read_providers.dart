import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_detail_controller.dart';
import 'package:y300/features/profile/presentation/blog/blog_feed_controller.dart';

final blogAccountIdProvider = Provider<String?>((ref) {
  final session = ref.watch(authSessionControllerProvider).value;
  return session?.isLoggedIn == true && !session!.isLoggingOut
      ? session.uid
      : null;
});

final profileBlogListProvider = Provider.autoDispose
    .family<ProfileBlogPageController, ProfileBlogPageArgs>((ref, args) {
      final controller = ProfileBlogPageController(
        repository: ref.watch(userBlogDirectoryRepositoryProvider),
        accountId: ref.watch(blogAccountIdProvider),
        args: args,
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

final profileBlogDetailProvider = Provider.autoDispose
    .family<ProfileBlogDetailController, (UserBlogDetailQuery, Object)>((
      ref,
      target,
    ) {
      // Even a public URL can return private content after authentication. Its
      // retained body belongs to the account which loaded it, just like the feeds.
      ref.watch(blogAccountIdProvider);
      final controller = ProfileBlogDetailController(
        repository: ref.watch(userBlogDetailRepositoryProvider),
        query: target.$1,
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

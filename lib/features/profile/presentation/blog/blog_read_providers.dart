import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/blog/blog_detail_controller.dart';
import 'package:y300/features/profile/presentation/blog/blog_feed_controller.dart';
import 'package:y300/features/profile/presentation/blog/blog_mutation_bus.dart';

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
      final bus = ref.watch(blogMutationBusProvider);
      void onChanged() {
        final change = bus.last;
        if (change != null &&
            (args.ownerUserId == null ||
                args.ownerUserId == change.ownerUserId)) {
          unawaited(controller.invalidate());
        }
      }

      bus.addListener(onChanged);
      ref.onDispose(() {
        bus.removeListener(onChanged);
        controller.dispose();
      });
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
      final bus = ref.watch(blogMutationBusProvider);
      void onChanged() {
        final change = bus.last;
        if (change != null &&
            change.ownerUserId == target.$1.ownerUserId &&
            change.blogId == target.$1.blogId) {
          unawaited(
            change.commentAction != null
                ? controller.refreshAfterComment(
                    change.commentAction!,
                    followNewComment: identical(
                      change.origin,
                      controller.commentRefreshOrigin,
                    ),
                  )
                : controller.invalidate(
                    deleted: change.articleAction == UserBlogAction.delete,
                  ),
          );
        }
      }

      bus.addListener(onChanged);
      ref.onDispose(() {
        bus.removeListener(onChanged);
        controller.dispose();
      });
      return controller;
    });

final blogMutationBusProvider = Provider<BlogMutationBus>((ref) {
  final bus = BlogMutationBus(ref.watch(blogAccountIdProvider));
  ref.onDispose(bus.dispose);
  return bus;
});

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/navigation/friend_routes.dart';
import 'package:y300/features/forum/domain/services/yamibo_forum_link_resolver.dart';
import 'package:y300/features/profile/presentation/threads/user_thread_page.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_page.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_account_guard.dart';

typedef ForumWebViewRouteFactory =
    Route<Object?> Function(ForumWebViewLaunchConfig config);

final forumWebViewRouteFactoryProvider = Provider<ForumWebViewRouteFactory>((
  ref,
) {
  return (config) {
    const resolver = YamiboForumLinkResolver();
    final destination = resolver.resolveForViewer(
      config.initialUri.toString(),
      readViewerUserId: () => ref.read(verifiedProfileOwnerProvider)?.uid,
    );
    if (config.purpose != ForumWebViewHostPurpose.postEditFallback &&
        {
          YamiboForumLinkKind.userThreadDirectory,
          YamiboForumLinkKind.friendFeed,
        }.contains(destination?.kind)) {
      Widget page({bool isActive = true}) =>
          destination!.kind == YamiboForumLinkKind.friendFeed
          ? MyFriendsDestination(
              initialScope: destination.friendScope!,
              initialPage: destination.page ?? 1,
              isActive: isActive,
            )
          : UserThreadPage(
              userId: destination.userId,
              initialType: destination.userThreadType!,
              initialPage: destination.page ?? 1,
              isActive: isActive,
            );
      return MaterialPageRoute<Object?>(
        builder: (_) => config.expectedAccountId == null
            ? page()
            : ForumWebViewAccountGuard(
                accountId: config.expectedAccountId!,
                builder: (_, isCurrent) => page(isActive: isCurrent()),
              ),
      );
    }
    return MaterialPageRoute<Object?>(
      builder: (_) => ProviderScope(
        overrides: [
          forumWebViewInitialUriProvider.overrideWithValue(config.initialUri),
          forumWebViewPopOnRootBackProvider.overrideWithValue(
            config.popOnRootBack,
          ),
          forumWebViewHostPurposeProvider.overrideWithValue(config.purpose),
          forumWebViewCompletionTargetProvider.overrideWithValue(
            config.completionTarget,
          ),
          forumWebViewDriverProvider.overrideWith((ref) {
            final factory = ref.watch(forumWebViewDriverFactoryProvider);
            return factory();
          }),
          forumWebViewControllerProvider.overrideWith(
            ForumWebViewController.new,
          ),
        ],
        child: config.expectedAccountId == null
            ? const ForumWebViewPage()
            : ForumWebViewAccountGuard(
                accountId: config.expectedAccountId!,
                builder: (_, isCurrent) =>
                    ForumWebViewPage(isAccountCurrent: isCurrent),
              ),
      ),
    );
  };
});

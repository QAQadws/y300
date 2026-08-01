import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_page.dart';

typedef ForumWebViewRouteFactory =
    Route<Object?> Function(ForumWebViewLaunchConfig config);

final forumWebViewRouteFactoryProvider = Provider<ForumWebViewRouteFactory>((
  ref,
) {
  return (config) => MaterialPageRoute<Object?>(
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
        forumWebViewControllerProvider.overrideWith(ForumWebViewController.new),
      ],
      child: const ForumWebViewPage(),
    ),
  );
});

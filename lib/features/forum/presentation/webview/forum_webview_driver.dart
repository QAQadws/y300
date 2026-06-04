import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/domain/models/forum_webview_runtime_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver_contract.dart';
import 'package:y300/features/forum/presentation/webview/runtime/inapp_forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/runtime/forum_webview_platform_configurator.dart';
import 'package:y300/features/forum/presentation/webview/runtime/legacy_forum_webview_driver.dart';

export 'package:y300/features/forum/domain/models/forum_webview_runtime_models.dart';
export 'package:y300/features/forum/domain/models/forum_webview_visual_policy_models.dart';
export 'package:y300/features/forum/presentation/webview/forum_webview_driver_contract.dart';

final forumWebViewPreferredEngineProvider = Provider<ForumWebViewEngine>((ref) {
  return ForumWebViewEngine.advanced;
});

final forumWebViewLegacyDriverFactoryProvider = Provider<ForumWebViewDriverFactory>((
  ref,
) {
  return LegacyForumWebViewDriver.new;
});

final forumWebViewAdvancedDriverFactoryProvider = Provider<ForumWebViewDriverFactory>((
  ref,
) {
  final platformConfigurator = ref.watch(
    forumWebViewPlatformConfiguratorProvider,
  );
  return () => InAppForumWebViewDriver(
        platformConfigurator: platformConfigurator,
      );
});

final forumWebViewDriverFactoryProvider = Provider<ForumWebViewDriverFactory>((
  ref,
) {
  final preferredEngine = ref.watch(forumWebViewPreferredEngineProvider);
  return switch (preferredEngine) {
    ForumWebViewEngine.legacy =>
      ref.watch(forumWebViewLegacyDriverFactoryProvider),
    ForumWebViewEngine.advanced =>
      ref.watch(forumWebViewAdvancedDriverFactoryProvider),
  };
});

final forumWebViewDriverProvider = Provider.autoDispose<ForumWebViewDriver>((
  ref,
) {
  final factory = ref.watch(forumWebViewDriverFactoryProvider);
  return factory();
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/domain/services/forum_webview_resource_classifier.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver_contract.dart';
import 'package:y300/features/forum/presentation/webview/runtime/inapp_forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/runtime/forum_webview_platform_configurator.dart';

export 'package:y300/features/forum/domain/models/forum_webview_network_policy_models.dart';
export 'package:y300/features/forum/domain/models/forum_webview_resource_diagnostic_models.dart';
export 'package:y300/features/forum/domain/models/forum_webview_runtime_models.dart';
export 'package:y300/features/forum/domain/models/forum_webview_visual_policy_models.dart';
export 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
export 'package:y300/features/forum/presentation/webview/forum_webview_driver_contract.dart';

final forumWebViewDriverFactoryProvider = Provider<ForumWebViewDriverFactory>((
  ref,
) {
  final platformConfigurator = ref.watch(
    forumWebViewPlatformConfiguratorProvider,
  );
  final resourceClassifier = ref.watch(forumWebViewResourceClassifierProvider);
  return () => InAppForumWebViewDriver(
    platformConfigurator: platformConfigurator,
    resourceClassifier: resourceClassifier,
  );
});

final forumWebViewDriverProvider = Provider.autoDispose<ForumWebViewDriver>((
  ref,
) {
  final factory = ref.watch(forumWebViewDriverFactoryProvider);
  return factory();
});

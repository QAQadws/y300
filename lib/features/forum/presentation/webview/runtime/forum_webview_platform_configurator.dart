import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as inapp;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/forum/domain/models/forum_webview_runtime_models.dart';

final forumWebViewPlatformConfiguratorProvider =
    Provider<ForumWebViewPlatformConfigurator>((ref) {
      return const DefaultForumWebViewPlatformConfigurator();
    });

abstract class ForumWebViewPlatformConfigurator {
  inapp.InAppWebViewSettings buildSettings({
    required ForumWebViewBootstrapConfig bootstrapConfig,
  });
}

class DefaultForumWebViewPlatformConfigurator
    implements ForumWebViewPlatformConfigurator {
  const DefaultForumWebViewPlatformConfigurator();

  @override
  inapp.InAppWebViewSettings buildSettings({
    required ForumWebViewBootstrapConfig bootstrapConfig,
  }) {
    assert(
      bootstrapConfig.capabilityProfile.engine == ForumWebViewEngine.advanced,
      'ForumWebViewPlatformConfigurator only supports advanced runtime.',
    );
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => _buildAndroidSettings(),
      TargetPlatform.iOS => _buildAppleSettings(),
      TargetPlatform.macOS => _buildAppleSettings(),
      TargetPlatform.fuchsia => _buildSharedSettings(),
      TargetPlatform.linux => _buildSharedSettings(),
      TargetPlatform.windows => _buildSharedSettings(),
    };
  }

  inapp.InAppWebViewSettings _buildSharedSettings() {
    return inapp.InAppWebViewSettings(
      javaScriptEnabled: true,
      useShouldOverrideUrlLoading: true,
      transparentBackground: true,
      verticalScrollBarEnabled: false,
      horizontalScrollBarEnabled: false,
      disableVerticalScroll: false,
      disableHorizontalScroll: true,
    );
  }

  inapp.InAppWebViewSettings _buildAndroidSettings() {
    final settings = _buildSharedSettings();
    settings.textZoom = 100;
    settings.useWideViewPort = true;
    settings.loadWithOverviewMode = true;
    settings.supportZoom = false;
    settings.builtInZoomControls = false;
    settings.displayZoomControls = false;
    return settings;
  }

  inapp.InAppWebViewSettings _buildAppleSettings() {
    final settings = _buildSharedSettings();
    settings.alwaysBounceVertical = true;
    settings.scrollsToTop = true;
    settings.contentInsetAdjustmentBehavior =
        inapp.ScrollViewContentInsetAdjustmentBehavior.NEVER;
    settings.allowsBackForwardNavigationGestures = false;
    return settings;
  }
}

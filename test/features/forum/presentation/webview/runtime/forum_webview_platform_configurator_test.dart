import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as inapp;
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/models/forum_webview_runtime_models.dart';
import 'package:y300/features/forum/domain/models/forum_webview_visual_policy_models.dart';
import 'package:y300/features/forum/presentation/webview/runtime/forum_webview_platform_configurator.dart';

void main() {
  const configurator = DefaultForumWebViewPlatformConfigurator();

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('android baseline keeps browser-shell tuning centralized', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    final settings = configurator.buildSettings(
      bootstrapConfig: _advancedBootstrapConfig(),
    );

    expect(settings.javaScriptEnabled, isTrue);
    expect(settings.useShouldOverrideUrlLoading, isTrue);
    expect(settings.transparentBackground, isTrue);
    expect(settings.verticalScrollBarEnabled, isFalse);
    expect(settings.horizontalScrollBarEnabled, isFalse);
    expect(settings.disableVerticalScroll, isFalse);
    expect(settings.disableHorizontalScroll, isTrue);
    expect(settings.textZoom, 100);
    expect(settings.useWideViewPort, isTrue);
    expect(settings.loadWithOverviewMode, isTrue);
    expect(settings.supportZoom, isFalse);
    expect(settings.builtInZoomControls, isFalse);
    expect(settings.displayZoomControls, isFalse);
  });

  test('apple baseline keeps scroll indicators and insets aligned', () {
    for (final platform in <TargetPlatform>[
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ]) {
      debugDefaultTargetPlatformOverride = platform;

      final settings = configurator.buildSettings(
        bootstrapConfig: _advancedBootstrapConfig(),
      );

      expect(settings.verticalScrollBarEnabled, isFalse);
      expect(settings.horizontalScrollBarEnabled, isFalse);
      expect(settings.disableHorizontalScroll, isTrue);
      expect(settings.alwaysBounceVertical, isTrue);
      expect(settings.scrollsToTop, isTrue);
      expect(
        settings.contentInsetAdjustmentBehavior,
        inapp.ScrollViewContentInsetAdjustmentBehavior.NEVER,
      );
      expect(settings.allowsBackForwardNavigationGestures, isFalse);
    }
  });
}

ForumWebViewBootstrapConfig _advancedBootstrapConfig() {
  return ForumWebViewBootstrapConfig(
    initialUri: Uri(scheme: 'https', host: 'bbs.yamibo.com', path: '/'),
    capabilityProfile: const ForumWebViewCapabilityProfile(
      engine: ForumWebViewEngine.advanced,
      documentStartMode: ForumWebViewDocumentStartMode.reliable,
      supportsContentBlockers: false,
      supportsTransparentBackground: true,
      supportsPlatformScrollTuning: true,
      supportsCookieHooks: true,
      supportsPageCommitVisible: true,
    ),
    visualPolicy: const ForumWebViewVisualPolicy(
      earlyHiddenSelectors: <String>{'#header-padding'},
      lateRemovedSelectors: <String>{'#header-padding'},
      extraCss: '',
      useLoadingMaskUntilStable: true,
      disableHorizontalOverflow: true,
    ),
    initialUserScripts: const <ForumWebViewInitialUserScript>[],
  );
}

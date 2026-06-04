import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/models/forum_webview_runtime_models.dart';
import 'package:y300/features/forum/domain/models/forum_webview_visual_policy_models.dart';
import 'package:y300/features/forum/domain/services/forum_webview_early_script_builder.dart';

void main() {
  const builder = DefaultForumWebViewEarlyScriptBuilder();
  const visualPolicy = ForumWebViewVisualPolicy(
    earlyHiddenSelectors: <String>{
      '#header-padding',
      '.header.cl',
      '.footer.mt10.cl',
      '.foot.flex-box',
    },
    lateRemovedSelectors: <String>{
      '#header-padding',
      '.header.cl',
      '.footer.mt10.cl',
      '.foot.flex-box',
    },
    extraCss: '',
    useLoadingMaskUntilStable: true,
    disableHorizontalOverflow: true,
  );

  test('unavailable document-start mode produces no initial user scripts', () {
    final scripts = builder.build(
      capabilityProfile: const ForumWebViewCapabilityProfile(
        engine: ForumWebViewEngine.legacy,
        documentStartMode: ForumWebViewDocumentStartMode.unavailable,
        supportsContentBlockers: false,
        supportsTransparentBackground: false,
        supportsPlatformScrollTuning: false,
        supportsCookieHooks: false,
      ),
      visualPolicy: visualPolicy,
    );

    expect(scripts, isEmpty);
  });

  test('best-effort and reliable modes produce a document-start style script', () {
    for (final mode in <ForumWebViewDocumentStartMode>[
      ForumWebViewDocumentStartMode.bestEffort,
      ForumWebViewDocumentStartMode.reliable,
    ]) {
      final scripts = builder.build(
        capabilityProfile: ForumWebViewCapabilityProfile(
          engine: ForumWebViewEngine.advanced,
          documentStartMode: mode,
          supportsContentBlockers: false,
          supportsTransparentBackground: true,
          supportsPlatformScrollTuning: true,
          supportsCookieHooks: true,
        ),
        visualPolicy: visualPolicy,
      );

      expect(scripts, hasLength(1));
      expect(
        scripts.single.injectionTime,
        ForumWebViewInitialUserScriptInjectionTime.documentStart,
      );
      expect(scripts.single.source, contains("window.location.host !== 'bbs.yamibo.com'"));
      expect(scripts.single.source, contains('#header-padding'));
      expect(scripts.single.source, contains('.header.cl'));
      expect(
        scripts.single.source,
        contains('overscroll-behavior-x: none !important;'),
      );
    }
  });
}

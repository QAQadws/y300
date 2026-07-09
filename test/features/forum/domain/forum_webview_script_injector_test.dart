import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/models/forum_webview_visual_policy_models.dart';
import 'package:y300/features/forum/domain/services/forum_webview_script_injector.dart';

void main() {
  const injector = DefaultForumWebViewScriptInjector();
  const pwaLateOnlyVisualPolicy = ForumWebViewVisualPolicy(
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
      '.foot_height',
      '.foot-pwa',
    },
    extraCss: '',
    disableHorizontalOverflow: true,
  );
  const threadDetailVisualPolicy = ForumWebViewVisualPolicy(
    earlyHiddenSelectors: <String>{
      '#header-padding',
      '.header.cl',
      '.footer.mt10.cl',
      '.foot.flex-box',
      '.foot.foot_reply.flex-box.cl',
      '.foot_height_view',
    },
    lateRemovedSelectors: <String>{
      '#header-padding',
      '.header.cl',
      '.footer.mt10.cl',
      '.foot.flex-box',
      '.foot.foot_reply.flex-box.cl',
      '.foot_height_view',
    },
    extraCss: '',
    disableHorizontalOverflow: true,
  );

  test(
    'cleanupScriptForPolicy contains forum list/search selectors and late-repair css',
    () {
      final script = injector.cleanupScriptForPolicy(pwaLateOnlyVisualPolicy);

      expect(script, contains('#header-padding'));
      expect(script, contains('.header.cl'));
      expect(script, contains('.footer.mt10.cl'));
      expect(script, contains('.foot.flex-box'));
      expect(script, contains('.foot_height'));
      expect(script, contains('.foot-pwa'));
      expect(script, contains('overscroll-behavior-x: none !important;'));
      expect(script, contains('querySelectorAll'));
    },
  );

  test(
    'cleanupScriptForPolicy contains thread-detail reply footer selectors',
    () {
      final script = injector.cleanupScriptForPolicy(threadDetailVisualPolicy);

      expect(script, contains('.foot.foot_reply.flex-box.cl'));
      expect(script, contains('.foot_height_view'));
      expect(script, contains('querySelectorAll'));
    },
  );

  test('cleanChrome runs late-repair script once', () async {
    final target = _FakeScriptTarget();

    await injector.cleanChrome(target, visualPolicy: threadDetailVisualPolicy);

    expect(target.scripts, <String>[
      injector.cleanupScriptForPolicy(threadDetailVisualPolicy),
    ]);
  });
}

class _FakeScriptTarget implements ForumWebViewScriptTarget {
  final List<String> scripts = <String>[];

  @override
  Future<void> runJavaScript(String script) async {
    scripts.add(script);
  }
}

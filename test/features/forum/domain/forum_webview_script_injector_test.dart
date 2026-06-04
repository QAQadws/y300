import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/models/forum_webview_visual_policy_models.dart';
import 'package:y300/features/forum/domain/services/forum_webview_script_injector.dart';

void main() {
  const injector = DefaultForumWebViewScriptInjector();
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

  test('cleanupScriptForPolicy contains target selectors and late-repair css', () {
    final script = injector.cleanupScriptForPolicy(visualPolicy);

    expect(script, contains('#header-padding'));
    expect(script, contains('.header.cl'));
    expect(script, contains('.footer.mt10.cl'));
    expect(script, contains('.foot.flex-box'));
    expect(script, contains('overscroll-behavior-x: none !important;'));
    expect(script, contains('querySelectorAll'));
  });

  test('cleanChrome runs late-repair script once', () async {
    final target = _FakeScriptTarget();

    await injector.cleanChrome(
      target,
      visualPolicy: visualPolicy,
    );

    expect(
      target.scripts,
      <String>[injector.cleanupScriptForPolicy(visualPolicy)],
    );
  });
}

class _FakeScriptTarget implements ForumWebViewScriptTarget {
  final List<String> scripts = <String>[];

  @override
  Future<void> runJavaScript(String script) async {
    scripts.add(script);
  }
}

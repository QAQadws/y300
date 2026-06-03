import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/services/forum_webview_script_injector.dart';

void main() {
  const injector = DefaultForumWebViewScriptInjector();

  test('cleanupScript contains target selectors', () {
    expect(injector.cleanupScript, contains('#header-padding'));
    expect(injector.cleanupScript, contains('.header.cl'));
    expect(injector.cleanupScript, contains('.footer.mt10.cl'));
    expect(injector.cleanupScript, contains('.foot.flex-box'));
  });

  test('cleanChrome runs cleanupScript once', () async {
    final target = _FakeScriptTarget();

    await injector.cleanChrome(target);

    expect(target.scripts, <String>[injector.cleanupScript]);
  });
}

class _FakeScriptTarget implements ForumWebViewScriptTarget {
  final List<String> scripts = <String>[];

  @override
  Future<void> runJavaScript(String script) async {
    scripts.add(script);
  }
}

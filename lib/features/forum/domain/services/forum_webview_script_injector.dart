import 'package:flutter_riverpod/flutter_riverpod.dart';

final forumWebViewScriptInjectorProvider = Provider<ForumWebViewScriptInjector>((
  ref,
) {
  return const DefaultForumWebViewScriptInjector();
});

abstract class ForumWebViewScriptInjector {
  String get cleanupScript;

  Future<void> cleanChrome(ForumWebViewScriptTarget target);
}

abstract class ForumWebViewScriptTarget {
  Future<void> runJavaScript(String script);
}

class DefaultForumWebViewScriptInjector implements ForumWebViewScriptInjector {
  const DefaultForumWebViewScriptInjector();

  @override
  String get cleanupScript => '''
document.querySelector('#header-padding')?.remove();
document.querySelector('.header.cl')?.remove();
document.querySelector('.footer.mt10.cl')?.remove();
document.querySelector('.foot.flex-box')?.remove();
''';

  @override
  Future<void> cleanChrome(ForumWebViewScriptTarget target) {
    return target.runJavaScript(cleanupScript);
  }
}

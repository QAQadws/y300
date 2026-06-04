import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigator.dart';
import 'package:y300/features/forum/domain/services/forum_webview_thread_menu_bridge.dart';

void main() {
  const bridge = DefaultForumWebViewThreadMenuBridge();
  final navigator = DefaultForumWebViewNavigator();

  test('extractScript reads nav-more-menu items and target labels', () {
    expect(bridge.extractScript, contains('#nav-more-menu .nav-more-item'));
    expect(bridge.extractScript, contains('只看楼主'));
    expect(bridge.extractScript, contains('看全部'));
    expect(bridge.extractScript, contains('倒序浏览'));
    expect(bridge.extractScript, contains('正序浏览'));
  });

  test('read resolves relative urls and ignores javascript links', () async {
    final target = _FakeThreadMenuTarget(
      result: jsonEncode(
        jsonEncode(<String, String?>{
          'authorOnlyHref':
              'forum.php?mod=viewthread&tid=123&authorid=9&mobile=2',
          'normalThreadHref': 'javascript:history.back()',
          'reverseOrderHref':
              'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&ordertype=1&mobile=2',
          'normalOrderHref': '/forum.php?mod=viewthread&tid=123&mobile=2',
        }),
      ),
    );

    final snapshot = await bridge.read(
      target: target,
      navigator: navigator,
    );

    expect(
      snapshot?.authorOnlyUri?.toString(),
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&authorid=9&mobile=2',
    );
    expect(snapshot?.normalThreadUri, isNull);
    expect(
      snapshot?.reverseOrderUri?.toString(),
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&ordertype=1&mobile=2',
    );
    expect(
      snapshot?.normalOrderUri?.toString(),
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );
  });
}

class _FakeThreadMenuTarget implements ForumWebViewThreadMenuTarget {
  const _FakeThreadMenuTarget({required this.result});

  final Object? result;

  @override
  Future<Object?> runJavaScriptReturningResult(String script) async {
    return result;
  }
}

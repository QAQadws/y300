import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigator.dart';
import 'package:y300/features/forum/domain/services/forum_webview_thread_document_bridge.dart';

void main() {
  const bridge = DefaultForumWebViewThreadDocumentBridge();
  final navigator = DefaultForumWebViewNavigator();

  test('extractScript reads thread metadata, post proof, and menu items', () {
    expect(bridge.extractScript, contains('.viewthread .view_tit'));
    expect(bridge.extractScript, contains('#thread_subject'));
    expect(bridge.extractScript, contains('.viewthread .plc[id^="pid"]'));
    expect(bridge.extractScript, contains('#postlist > div[id^="post_"]'));
    expect(bridge.extractScript, contains('link[rel="canonical"]'));
    expect(bridge.extractScript, contains('.display.pione'));
    expect(bridge.extractScript, contains("floorLabel === '楼主'"));
    expect(
      bridge.extractScript,
      contains('.header h2 a[href*="forumdisplay"]'),
    );
    expect(bridge.extractScript, contains('#nav-more-menu .nav-more-item'));
    expect(bridge.extractScript, contains('只看楼主'));
    expect(bridge.extractScript, contains('看全部'));
    expect(bridge.extractScript, contains('倒序浏览'));
    expect(bridge.extractScript, contains('正序浏览'));
    expect(bridge.extractScript, isNot(contains('document.title.split')));
  });

  test('read resolves structured metadata and menu urls', () async {
    final target = _FakeThreadDocumentTarget(
      result: jsonEncode(
        jsonEncode(<String, Object?>{
          'title': '  测试 主题  ',
          'forumName': ' 中文百合漫画区 ',
          'canonicalHref': '/thread-123-1-1.html',
          'firstPostAvatarHref': '/uc_server/avatar.jpg',
          'postCount': 20,
          'authorOnlyHref':
              'forum.php?mod=viewthread&tid=123&authorid=9&mobile=2',
          'normalThreadHref': 'javascript:history.back()',
          'reverseOrderHref':
              'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&ordertype=1&mobile=2',
          'normalOrderHref': '/forum.php?mod=viewthread&tid=123&mobile=2',
        }),
      ),
    );

    final snapshot = await bridge.read(target: target, navigator: navigator);

    expect(snapshot?.title, '测试 主题');
    expect(snapshot?.forumName, '中文百合漫画区');
    expect(snapshot?.postCount, 20);
    expect(snapshot?.hasPostProof, isTrue);
    expect(
      snapshot?.canonicalUri?.toString(),
      'https://bbs.yamibo.com/thread-123-1-1.html',
    );
    expect(
      snapshot?.firstPostAvatarUrl,
      'https://bbs.yamibo.com/uc_server/avatar.jpg',
    );
    expect(
      snapshot?.menu.authorOnlyUri?.toString(),
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&authorid=9&mobile=2',
    );
    expect(snapshot?.menu.normalThreadUri, isNull);
    expect(
      snapshot?.menu.reverseOrderUri?.toString(),
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&ordertype=1&mobile=2',
    );
    expect(
      snapshot?.menu.normalOrderUri?.toString(),
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );
  });

  test('read requires both a title and post wrappers for post proof', () async {
    final missingTitle = await bridge.read(
      target: _FakeThreadDocumentTarget(
        result: jsonEncode(<String, Object?>{'postCount': 1}),
      ),
      navigator: navigator,
    );
    final missingPosts = await bridge.read(
      target: _FakeThreadDocumentTarget(
        result: jsonEncode(<String, Object?>{'title': '主题不存在', 'postCount': 0}),
      ),
      navigator: navigator,
    );

    expect(missingTitle?.hasPostProof, isFalse);
    expect(missingPosts?.hasPostProof, isFalse);
  });
}

class _FakeThreadDocumentTarget implements ForumWebViewThreadDocumentTarget {
  const _FakeThreadDocumentTarget({required this.result});

  final Object? result;

  @override
  Future<Object?> runJavaScriptReturningResult(String script) async => result;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigator.dart';
import 'package:y300/features/forum/domain/services/forum_webview_post_navigator.dart';

void main() {
  group('ForumWebViewPostNavigator', () {
    final navigator = ForumWebViewPostNavigator(
      webViewNavigator: DefaultForumWebViewNavigator(),
    );

    test('resolves managed newthread url with fid into request', () {
      final request = navigator.resolveNewThread(
        'https://bbs.yamibo.com/forum.php?mod=post&action=newthread&fid=33&mobile=2',
      );

      expect(request, isNotNull);
      expect(request!.fid, '33');
      expect(request.sourceUri.queryParameters['fid'], '33');
      expect(request.sourceUri.queryParameters['mobile'], '2');
    });

    test('resolves html escaped ampersands in newthread url', () {
      final request = navigator.resolveNewThread(
        'forum.php?mod=post&amp;action=newthread&amp;fid=33&amp;mobile=2',
      );

      expect(request?.fid, '33');
    });

    test('returns null when fid is missing or blank', () {
      expect(
        navigator.resolveNewThread(
          'https://bbs.yamibo.com/forum.php?mod=post&action=newthread&mobile=2',
        ),
        isNull,
      );
      expect(
        navigator.resolveNewThread(
          'https://bbs.yamibo.com/forum.php?mod=post&action=newthread&fid=&mobile=2',
        ),
        isNull,
      );
    });

    test('returns null when mod or action does not match', () {
      // mod=post&action=reply 由 reply navigator 处理，post navigator 必须放行。
      expect(
        navigator.resolveNewThread(
          'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=33&tid=1',
        ),
        isNull,
      );
      // mod=forumdisplay 等其它路径完全不归 post navigator 管。
      expect(
        navigator.resolveNewThread(
          'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=33',
        ),
        isNull,
      );
    });

    test('returns null when host is not the managed site', () {
      expect(
        navigator.resolveNewThread(
          'https://example.com/forum.php?mod=post&action=newthread&fid=33',
        ),
        isNull,
      );
    });

    test('returns null when path is not /forum.php', () {
      expect(
        navigator.resolveNewThread(
          'https://bbs.yamibo.com/api/mobile/index.php?mod=post&action=newthread&fid=33',
        ),
        isNull,
      );
    });
  });
}

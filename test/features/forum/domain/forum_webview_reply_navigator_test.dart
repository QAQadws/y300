import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/domain/services/forum_webview_navigator.dart';
import 'package:y300/features/forum/domain/services/forum_webview_reply_navigator.dart';

void main() {
  group('ForumWebViewReplyNavigator', () {
    final navigator = ForumWebViewReplyNavigator(
      webViewNavigator: DefaultForumWebViewNavigator(),
    );

    test('resolves managed post reply url into composer args', () {
      final args = navigator.resolvePostReply(
        'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=33&tid=572063&repquote=41554317&mobile=2',
      );

      expect(args, isNotNull);
      expect(args!.fid, '33');
      expect(args.tid, '572063');
      expect(args.repquote, '41554317');
      expect(args.replyFormUri.queryParameters['repquote'], '41554317');
    });

    test('ignores missing repquote and non reply url', () {
      expect(
        navigator.resolvePostReply(
          'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=33&tid=572063&mobile=2',
        ),
        isNull,
      );
      expect(
        navigator.resolvePostReply(
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=572063&mobile=2',
        ),
        isNull,
      );
      expect(
        navigator.resolvePostReply(
          'https://example.com/forum.php?mod=post&action=reply&fid=33&tid=572063&repquote=41554317',
        ),
        isNull,
      );
    });

    test('resolves html escaped ampersands', () {
      final args = navigator.resolvePostReply(
        'forum.php?mod=post&amp;action=reply&amp;fid=33&amp;tid=572063&amp;repquote=41554317&amp;mobile=2',
      );

      expect(args?.fid, '33');
      expect(args?.tid, '572063');
      expect(args?.repquote, '41554317');
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/data/thread_post_comment_repository.dart';

void main() {
  group('ThreadPostCommentFormParser', () {
    test('parses desktop comment dialog form', () {
      final html = File('docs/html/帖子详细页/一个楼的点评功能.html').readAsStringSync();
      const parser = ThreadPostCommentFormParser();

      final form = parser.parse(
        html,
        fallbackCommentUrl:
            'https://bbs.yamibo.com/forum.php?mod=misc&action=comment&tid=572529&pid=41562047',
      );

      expect(form.actionUrl, contains('commentsubmit=yes'));
      expect(form.formHash, 'cba80c43');
      expect(form.handleKey, 'comment');
      expect(form.tid, '572529');
      expect(form.pid, '41562047');
      expect(form.referer, contains('viewthread'));
      expect(form.maxLength, 200);
    });
  });
}

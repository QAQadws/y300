import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/data/thread_post_rate_repository.dart';

void main() {
  group('ThreadPostRateFormParser', () {
    test('parses desktop rate dialog form', () {
      final html = File('docs/html/帖子详细页/一个楼的评分功能.html').readAsStringSync();
      const parser = ThreadPostRateFormParser();

      final form = parser.parse(
        html,
        fallbackRateUrl:
            'https://bbs.yamibo.com/forum.php?mod=misc&action=rate&tid=572529&pid=41562047',
      );

      expect(form.actionUrl, contains('ratesubmit=yes'));
      expect(form.formHash, 'cba80c43');
      expect(form.tid, '572529');
      expect(form.pid, '41562047');
      expect(form.referer, contains('viewthread'));
      expect(form.scoreName, 'score1');
      expect(form.scoreMin, 0);
      expect(form.scoreMax, 5);
      expect(form.todayRemaining, 10);
      expect(form.defaultScore, 5);
      expect(form.reasonOptions, <String>[
        '你太可爱',
        '好萌好萌好萌',
        '我很赞同',
        '精品文章',
        '原创内容',
      ]);
      expect(form.notifyAuthorDefault, isFalse);
    });
  });
}

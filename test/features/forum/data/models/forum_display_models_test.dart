import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/forum/data/models/forum_display_models.dart';

void main() {
  group('ForumDisplayData.fromVariables', () {
    test('parses forum_threadlist and tpp from forumdisplay response', () {
      final variables = <String, dynamic>{
        'forum': <String, dynamic>{
          'fid': '5',
          'name': '动漫区',
          'threads': '27956',
        },
        'page': '1',
        'tpp': '20',
        'forum_threadlist': <Map<String, dynamic>>[
          <String, dynamic>{
            'tid': '533721',
            'subject': '如何找回账号/如何修改密码',
            'author': 'hongyuny',
            'replies': '3',
            'views': '69864',
            'dateline': '2023-3-13 02:21',
          },
        ],
      };

      final data = ForumDisplayData.fromVariables(variables, page: 99);

      expect(data.fid, '5');
      expect(data.forumName, '动漫区');
      expect(data.currentPage, 1);
      expect(data.perPage, 20);
      expect(data.totalThreads, 27956);
      expect(data.threads, hasLength(1));
      expect(data.threads.first.tid, '533721');
      expect(data.threads.first.subject, '如何找回账号/如何修改密码');
      expect(data.threads.first.author, 'hongyuny');
      expect(data.threads.first.replies, 3);
      expect(data.threads.first.views, 69864);
      expect(data.threads.first.dateline, '2023-3-13 02:21');
    });

    test('supports fallback keys threadlist and perpage', () {
      final variables = <String, dynamic>{
        'forum': <String, dynamic>{
          'fid': '9',
          'name': '测试区',
          'threads': '1',
        },
        'perpage': '10',
        'threadlist': <Map<String, dynamic>>[
          <String, dynamic>{
            'tid': '100',
            'subject': '兼容字段',
            'authorname': 'fallback-author',
            'replies': '0',
            'views': '1',
            'dbdateline': '1700000000',
          },
        ],
      };

      final data = ForumDisplayData.fromVariables(variables, page: 2);

      expect(data.currentPage, 2);
      expect(data.perPage, 10);
      expect(data.threads, hasLength(1));
      expect(data.threads.first.author, 'fallback-author');
      expect(data.threads.first.dateline, '1700000000');
    });
  });
}

import 'package:y300/core/utils/parse_utils.dart';

/// Sanitized shape fixture based on a Discuz `viewthread` JSON response.
/// It intentionally contains no cookies, auth values or real user content.
JsonMap comicCommentPageVariables({required int page, int replyCount = 39}) {
  final start = page == 1 ? 1 : 21;
  final end = page == 1 ? 20 : 40;
  final posts = <JsonMap>[
    if (page == 1)
      _post(
        pid: '41519747',
        number: 1,
        first: true,
        author: 'thread-owner',
        authorId: '365616',
        message: '<p>首楼正文<img src="https://example.com/cover.jpg" /></p>',
      ),
    for (var number = start == 1 ? 2 : start; number <= end; number++)
      _post(
        pid: '415197${number.toString().padLeft(2, '0')}',
        number: number,
        author: number == 2 ? 'thread-owner' : 'reply-$number',
        authorId: number == 2
            ? '365616'
            : number == 20
            ? '422014'
            : number == 21
            ? '8'
            : '$number',
        message: number == 2
            ? '<p>楼主的后续回复 <img src="/static/image/smiley/test.gif" /></p>'
            : '<p>回帖 $number</p>',
      ),
  ];

  return <String, dynamic>{
    'fid': '30',
    'ppp': '20',
    'thread': <String, dynamic>{
      'tid': '570140',
      'fid': '30',
      'subject': '脱敏漫画帖子',
      'author': 'thread-owner',
      'authorid': '365616',
      'replies': '$replyCount',
      'views': '1',
    },
    'postlist': posts,
    // The loader must ignore these nested discussion entries.
    'comments': <String, dynamic>{'41519747': <dynamic>[]},
    'commentcount': <String, dynamic>{'41519747': null},
  };
}

JsonMap _post({
  required String pid,
  required int number,
  bool first = false,
  required String author,
  required String authorId,
  required String message,
}) {
  return <String, dynamic>{
    'pid': pid,
    'tid': '570140',
    'first': first ? '1' : '0',
    'author': author,
    'authorid': authorId,
    'dateline': '2026-07-$number 12:00',
    'message': message,
    'position': '$number',
    'number': '$number',
    'comments': <dynamic>['should not be rendered'],
  };
}

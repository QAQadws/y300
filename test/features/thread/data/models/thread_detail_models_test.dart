import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

void main() {
  group('ThreadDetailData.fromVariables', () {
    test('parses typeid from thread payload', () {
      final data = ThreadDetailData.fromVariables(
        <String, dynamic>{
          'fid': '30',
          'ppp': '20',
          'thread': <String, dynamic>{
            'tid': '100',
            'typeid': '398',
            'subject': '测试漫画',
            'author': 'alice',
            'replies': '0',
            'views': '12',
          },
          'postlist': const <Map<String, dynamic>>[],
        },
        page: 1,
      );

      expect(data.fid, '30');
      expect(data.typeid, '398');
    });

    test('falls back to variables typeid when thread typeid is absent', () {
      final data = ThreadDetailData.fromVariables(
        <String, dynamic>{
          'fid': '49',
          'typeid': '293',
          'thread': <String, dynamic>{
            'tid': '101',
            'subject': '测试小说',
          },
          'postlist': const <Map<String, dynamic>>[],
        },
        page: 1,
      );

      expect(data.typeid, '293');
    });

    test('keeps raw attachment metadata from postlist', () {
      final data = ThreadDetailData.fromVariables(
        <String, dynamic>{
          'fid': '30',
          'thread': <String, dynamic>{
            'tid': '476706',
            'subject': 'attachment comic',
          },
          'postlist': <Map<String, dynamic>>[
            <String, dynamic>{
              'pid': '39089696',
              'author': 'cc01205',
              'authorid': '246572',
              'message': 'text only',
              'number': '1',
              'first': '1',
              'dateline': '2018-2-16 00:29',
              'attachments': <String, dynamic>{
                '625902': <String, dynamic>{
                  'aid': '625902',
                  'filename': 'Screenshot.jpg',
                  'attachment': '201802/16/002909v4kga3k6tkh4mlap.jpg',
                  'url': 'data/attachment/forum/',
                  'attachimg': '1',
                  'ext': 'jpg',
                },
                '625903': <String, dynamic>{
                  'aid': '625903',
                  'filename': 'archive.zip',
                  'attachment': '201802/16/archive.zip',
                  'url': 'data/attachment/forum/',
                  'attachimg': '0',
                  'ext': 'zip',
                },
              },
            },
          ],
        },
        page: 1,
      );

      final attachments = data.posts.single.attachmentImages;
      expect(attachments.length, 2);
      expect(attachments.first.aid, '625902');
      expect(attachments.first.url, 'data/attachment/forum/');
      expect(attachments.first.attachment, '201802/16/002909v4kga3k6tkh4mlap.jpg');
      expect(attachments.first.attachimg, '1');
      expect(attachments.first.ext, 'jpg');
      expect(attachments.last.aid, '625903');
      expect(attachments.last.attachment, '201802/16/archive.zip');
      expect(attachments.last.ext, 'zip');
    });
  });
}

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
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/services/thread_floor_link_builder.dart';

void main() {
  group('ThreadFloorLinkBuilder', () {
    final builder = ThreadFloorLinkBuilder(
      siteBaseUri: Uri.parse('https://bbs.yamibo.com'),
    );

    test('builds a findpost redirect with a valid attribution uid', () {
      final uri = builder.build(
        tid: '573908',
        pid: '41585107',
        fromUid: '597454',
      );

      expect(
        uri?.toString(),
        'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&ptid=573908&pid=41585107&fromuid=597454',
      );
    });

    test('omits invalid or missing attribution uid without blocking copy', () {
      expect(
        builder.build(tid: '573908', pid: '41585107')?.queryParameters,
        isNot(contains('fromuid')),
      );
      expect(
        builder
            .build(tid: '573908', pid: '41585107', fromUid: '0')
            ?.queryParameters,
        isNot(contains('fromuid')),
      );
      expect(
        builder
            .build(tid: '573908', pid: '41585107', fromUid: 'user-1')
            ?.queryParameters,
        isNot(contains('fromuid')),
      );
    });

    test('rejects invalid thread and post identifiers', () {
      expect(builder.build(tid: '', pid: '1'), isNull);
      expect(builder.build(tid: '0', pid: '1'), isNull);
      expect(builder.build(tid: '-1', pid: '1'), isNull);
      expect(builder.build(tid: 'abc', pid: '1'), isNull);
      expect(builder.build(tid: '1', pid: ''), isNull);
      expect(builder.build(tid: '1', pid: '0'), isNull);
      expect(builder.build(tid: '1', pid: '-1'), isNull);
      expect(builder.build(tid: '1', pid: 'abc'), isNull);
    });
  });
}

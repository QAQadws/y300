import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_post_aggregation_service.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

void main() {
  group('ComicPostAggregationService', () {
    const service = ComicPostAggregationService();

    test(
      'merges floor1 and floor2 when second floor is same author and image-dominant',
      () {
        final result = service.build([
          ThreadPost(
            pid: 'p1',
            author: 'alice',
            authorId: '1',
            message: '<p>信息介绍</p><img src="a.jpg"/>',
            number: 1,
            isFirst: true,
            dateline: 'today',
          ),
          ThreadPost(
            pid: 'p2',
            author: 'alice',
            authorId: '1',
            message: '<img src="b.jpg"/><img src="c.jpg"/><p>正文</p>',
            number: 2,
            isFirst: false,
            dateline: 'today',
          ),
        ]);

        expect(result.usedSecondFloor, isTrue);
        expect(result.detectionMessage, contains('a.jpg'));
        expect(result.detectionMessage, contains('b.jpg'));
        expect(result.detectionMessage, contains('c.jpg'));
      },
    );

    test('does not merge second floor when author is different', () {
      final result = service.build([
        ThreadPost(
          pid: 'p1',
          author: 'alice',
          authorId: '1',
          message: '<img src="a.jpg"/>',
          number: 1,
          isFirst: true,
          dateline: 'today',
        ),
        ThreadPost(
          pid: 'p2',
          author: 'bob',
          authorId: '2',
          message: '<img src="b.jpg"/><img src="c.jpg"/>',
          number: 2,
          isFirst: false,
          dateline: 'today',
        ),
      ]);

      expect(result.usedSecondFloor, isFalse);
      expect(result.detectionMessage, contains('a.jpg'));
      expect(result.detectionMessage, isNot(contains('b.jpg')));
    });

    test('aggregates attachment images from merged OP floors', () {
      final result = service.build([
        ThreadPost(
          pid: 'p1',
          author: 'alice',
          authorId: '1',
          message: '<img src="a.jpg"/>',
          number: 1,
          isFirst: true,
          dateline: 'today',
          attachmentImages: const <ForumPostAttachmentImage>[
            ForumPostAttachmentImage(
              aid: '1',
              url: 'data/attachment/forum/',
              attachment: 'floor1.jpg',
              filename: 'floor1.jpg',
              attachimg: '1',
              ext: 'jpg',
            ),
          ],
        ),
        ThreadPost(
          pid: 'p2',
          author: 'alice',
          authorId: '1',
          message: '<img src="b.jpg"/><img src="c.jpg"/>',
          number: 2,
          isFirst: false,
          dateline: 'today',
          attachmentImages: const <ForumPostAttachmentImage>[
            ForumPostAttachmentImage(
              aid: '2',
              url: 'data/attachment/forum/',
              attachment: 'floor2.jpg',
              filename: 'floor2.jpg',
              attachimg: '1',
              ext: 'jpg',
            ),
          ],
        ),
      ]);

      expect(result.attachmentImageUrls, <String>[
        'https://bbs.yamibo.com/data/attachment/forum/floor1.jpg',
        'https://bbs.yamibo.com/data/attachment/forum/floor2.jpg',
      ]);
    });

    test('treats attachment-heavy second floor as image-dominant', () {
      final result = service.build([
        ThreadPost(
          pid: 'p1',
          author: 'alice',
          authorId: '1',
          message: '<p>info</p>',
          number: 1,
          isFirst: true,
          dateline: 'today',
        ),
        ThreadPost(
          pid: 'p2',
          author: 'alice',
          authorId: '1',
          message: '<p>pages in attachments</p>',
          number: 2,
          isFirst: false,
          dateline: 'today',
          attachmentImages: const <ForumPostAttachmentImage>[
            ForumPostAttachmentImage(
              aid: '2',
              url: 'data/attachment/forum/',
              attachment: 'a.jpg',
              filename: 'a.jpg',
              attachimg: '1',
              ext: 'jpg',
            ),
            ForumPostAttachmentImage(
              aid: '3',
              url: 'data/attachment/forum/',
              attachment: 'b.jpg',
              filename: 'b.jpg',
              attachimg: '1',
              ext: 'jpg',
            ),
          ],
        ),
      ]);

      expect(result.usedSecondFloor, isTrue);
      expect(result.attachmentImageUrls.length, 2);
    });
  });
}

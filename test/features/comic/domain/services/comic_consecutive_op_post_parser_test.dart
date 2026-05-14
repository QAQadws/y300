import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_consecutive_op_post_parser.dart';
import 'package:y300/features/comic/domain/services/comic_post_parsing_engine.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

void main() {
  group('ComicConsecutiveOpPostParser', () {
    test('parses consecutive OP posts from floor one and stops at first non-OP', () {
      final parser = ComicConsecutiveOpPostParser(
        engine: ComicPostParsingEngine(),
      );
      final posts = <ThreadPost>[
        ThreadPost(
          pid: '1',
          author: 'op',
          authorId: '100',
          message: '<a href="thread-100-1-1.html">01</a><img src="https://img.test/1.jpg" />',
          number: 1,
          isFirst: true,
          dateline: '',
        ),
        ThreadPost(
          pid: '2',
          author: 'op',
          authorId: '100',
          message: '<a href="thread-101-1-1.html">02</a><img src="https://img.test/2.jpg" />',
          number: 2,
          isFirst: false,
          dateline: '',
        ),
        ThreadPost(
          pid: '3',
          author: 'other',
          authorId: '200',
          message: '<a href="thread-999-1-1.html">99</a>',
          number: 3,
          isFirst: false,
          dateline: '',
        ),
      ];

      final result = parser.parse(
        tid: '500000',
        fid: '30',
        subject: 'subject',
        posts: posts,
      );

      expect(result.episodeLinks.length, 2);
      expect(result.episodeLinks.any((e) => e.url.contains('thread-999-1-1.html')), false);
      expect(result.imageUrls.length, 2);
    });

    test('extracts lazy-loaded images and filters forum chrome images', () {
      final parser = ComicConsecutiveOpPostParser(
        engine: ComicPostParsingEngine(),
      );
      final posts = <ThreadPost>[
        ThreadPost(
          pid: '1',
          author: 'op',
          authorId: '100',
          message: '''
<img data-src="https://img.test/lazy.jpg" />
<img file="https://img.test/file.jpg" />
<img src="https://bbs.yamibo.com/static/image/common/smile.gif" />
''',
          number: 1,
          isFirst: true,
          dateline: '',
        ),
      ];

      final result = parser.parse(
        tid: '500000',
        fid: '30',
        subject: 'subject',
        posts: posts,
      );

      expect(result.imageUrls, <String>['https://img.test/lazy.jpg', 'https://img.test/file.jpg']);
    });

    test('includes attachment images from consecutive OP posts', () {
      final parser = ComicConsecutiveOpPostParser(
        engine: ComicPostParsingEngine(),
      );
      final posts = <ThreadPost>[
        ThreadPost(
          pid: '1',
          author: 'op',
          authorId: '100',
          message: '<img src="https://img.test/dom.jpg" />',
          number: 1,
          isFirst: true,
          dateline: '',
          attachmentImages: const <ForumPostAttachmentImage>[
            ForumPostAttachmentImage(
              aid: '1',
              url: 'data/attachment/forum/',
              attachment: 'attachment.jpg',
              filename: 'attachment.jpg',
              attachimg: '1',
              ext: 'jpg',
            ),
          ],
        ),
      ];

      final result = parser.parse(
        tid: '500000',
        fid: '30',
        subject: 'subject',
        posts: posts,
      );

      expect(result.imageUrls, <String>[
        'https://img.test/dom.jpg',
        'https://bbs.yamibo.com/data/attachment/forum/attachment.jpg',
      ]);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/services/forum_attachment_image_extractor.dart';

void main() {
  group('ForumAttachmentImageExtractor', () {
    const extractor = ForumAttachmentImageExtractor();

    test('extracts image attachment urls from Discuz attachment metadata', () {
      final post = ThreadPost(
        pid: '39089696',
        author: 'cc01205',
        authorId: '246572',
        message: 'text only',
        number: 1,
        isFirst: true,
        dateline: '2018-2-16 00:29',
        attachmentImages: const <ForumPostAttachmentImage>[
          ForumPostAttachmentImage(
            aid: '625902',
            url: 'data/attachment/forum/',
            attachment: '201802/16/002909v4kga3k6tkh4mlap.jpg',
            filename: 'Screenshot_2017-12-24-23-23-05-1.jpg',
            attachimg: '1',
            ext: 'jpg',
          ),
        ],
      );

      expect(extractor.extractImageUrls(post), <String>[
        'https://bbs.yamibo.com/data/attachment/forum/201802/16/002909v4kga3k6tkh4mlap.jpg',
      ]);
    });

    test('keeps image extensions even when attachimg flag is absent', () {
      final post = ThreadPost(
        pid: '1',
        author: 'op',
        authorId: '100',
        message: '',
        number: 1,
        isFirst: true,
        dateline: '',
        attachmentImages: const <ForumPostAttachmentImage>[
          ForumPostAttachmentImage(
            aid: '1',
            url: 'data/attachment/forum',
            attachment: '201802/16/page.webp',
            filename: 'page.webp',
            attachimg: '0',
            ext: 'webp',
          ),
          ForumPostAttachmentImage(
            aid: '2',
            url: 'data/attachment/forum',
            attachment: '201802/16/archive.zip',
            filename: 'archive.zip',
            attachimg: '0',
            ext: 'zip',
          ),
        ],
      );

      expect(extractor.extractImageUrls(post), <String>[
        'https://bbs.yamibo.com/data/attachment/forum/201802/16/page.webp',
      ]);
    });

    test('deduplicates repeated attachment urls', () {
      final post = ThreadPost(
        pid: '1',
        author: 'op',
        authorId: '100',
        message: '',
        number: 1,
        isFirst: true,
        dateline: '',
        attachmentImages: const <ForumPostAttachmentImage>[
          ForumPostAttachmentImage(
            aid: '1',
            url: 'data/attachment/forum/',
            attachment: 'a.jpg',
            filename: 'a.jpg',
            attachimg: '1',
            ext: 'jpg',
          ),
          ForumPostAttachmentImage(
            aid: '2',
            url: 'data/attachment/forum',
            attachment: 'a.jpg',
            filename: 'a.jpg',
            attachimg: '1',
            ext: 'jpg',
          ),
        ],
      );

      expect(extractor.extractImageUrls(post), <String>[
        'https://bbs.yamibo.com/data/attachment/forum/a.jpg',
      ]);
    });
  });
}

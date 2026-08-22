import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/services/forum_post_dom_extractor.dart';
import 'package:y300/features/thread/domain/services/forum_post_image_source_collector.dart';

void main() {
  group('forum image source baseline', () {
    const domExtractor = ForumPostDomExtractor();
    const collector = ForumPostImageSourceCollector();

    test('collects common DOM attributes and keeps third-party images', () {
      final images = domExtractor.extractImageSources('''
<img src="data/attachment/forum/a.jpg">
<img data-src="//bbs.yamibo.com/data/attachment/forum/b.jpg">
<img data-original="https://img.example/c.jpg">
<img file="http://data/attachment/sinaimg/tid1/page.jpg">
''');

      expect(images, <String>[
        'https://bbs.yamibo.com/data/attachment/forum/a.jpg',
        'https://bbs.yamibo.com/data/attachment/forum/b.jpg',
        'https://img.example/c.jpg',
        'https://bbs.yamibo.com/data/attachment/sinaimg/tid1/page.jpg',
      ]);
    });

    test('filters forum chrome images by default', () {
      final images = domExtractor.extractImageSources('''
<img src="https://bbs.yamibo.com/static/image/common/smile.gif">
<img src="https://bbs.yamibo.com/uc_server/data/avatar/000/00/01.jpg">
<img src="https://img.example/content.jpg">
''');

      expect(images, <String>['https://img.example/content.jpg']);
    });

    test('merges DOM and attachment sources with stable deduplication', () {
      final post = ThreadPost(
        pid: '1',
        author: 'op',
        authorId: '100',
        message: '''
<img src="https://img.example/dom.jpg">
<img src="https://bbs.yamibo.com/data/attachment/forum/shared.jpg">
''',
        number: 1,
        isFirst: true,
        dateline: '',
        attachmentImages: const <ForumPostAttachmentImage>[
          ForumPostAttachmentImage(
            aid: '1',
            url: 'data/attachment/forum/',
            attachment: 'shared.jpg',
            filename: 'shared.jpg',
            attachimg: '1',
            ext: 'jpg',
          ),
          ForumPostAttachmentImage(
            aid: '2',
            url: 'data/attachment/forum/',
            attachment: 'attachment.webp',
            filename: 'attachment.webp',
            attachimg: '0',
            ext: 'webp',
          ),
        ],
      );

      expect(collector.collect(post), <String>[
        'https://img.example/dom.jpg',
        'https://bbs.yamibo.com/data/attachment/forum/shared.jpg',
        'https://bbs.yamibo.com/data/attachment/forum/attachment.webp',
      ]);
    });
  });
}

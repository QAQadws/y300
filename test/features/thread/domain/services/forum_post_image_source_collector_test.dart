import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/services/forum_post_image_source_collector.dart';

void main() {
  group('ForumPostImageSourceCollector', () {
    const collector = ForumPostImageSourceCollector();

    test('merges DOM and attachment image sources in post order', () {
      final post = ThreadPost(
        pid: '1',
        author: 'op',
        authorId: '100',
        message: '''
<img src="https://img.test/dom.jpg" />
<img src="https://bbs.yamibo.com/data/attachment/forum/shared.jpg" />
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
            attachment: 'attachment.jpg',
            filename: 'attachment.jpg',
            attachimg: '1',
            ext: 'jpg',
          ),
        ],
      );

      expect(collector.collect(post), <String>[
        'https://img.test/dom.jpg',
        'https://bbs.yamibo.com/data/attachment/forum/shared.jpg',
        'https://bbs.yamibo.com/data/attachment/forum/attachment.jpg',
      ]);
    });
  });
}

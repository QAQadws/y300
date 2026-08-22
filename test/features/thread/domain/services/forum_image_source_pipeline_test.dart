import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/services/forum_image_source_pipeline.dart';

void main() {
  group('DefaultForumImageSourcePipeline', () {
    const pipeline = DefaultForumImageSourcePipeline();

    test('collects DOM images with normalized urls and host kinds', () {
      final post = ThreadPost(
        pid: '1',
        author: 'op',
        authorId: '100',
        message: '''
<img src="data/attachment/forum/a.jpg">
<img data-src="//bbs.yamibo.com/static/forum/banner.png">
<img data-original="https://img.example/c.jpg">
<img file="http://data/attachment/sinaimg/tid1/page.jpg">
''',
        number: 1,
        isFirst: true,
        dateline: '',
      );

      final sources = pipeline.collectFromPost(post);

      expect(sources.map((source) => source.normalizedUrl).toList(), <String>[
        'https://bbs.yamibo.com/data/attachment/forum/a.jpg',
        'https://bbs.yamibo.com/static/forum/banner.png',
        'https://img.example/c.jpg',
        'https://bbs.yamibo.com/data/attachment/sinaimg/tid1/page.jpg',
      ]);
      expect(
        sources.map((source) => source.hostKind).toList(),
        <ForumImageHostKind>[
          ForumImageHostKind.yamiboAttachment,
          ForumImageHostKind.yamiboStatic,
          ForumImageHostKind.thirdParty,
          ForumImageHostKind.yamiboAttachment,
        ],
      );
      expect(
        sources.map((source) => source.origin).toList(),
        <ForumImageSourceOrigin>[
          ForumImageSourceOrigin.dom,
          ForumImageSourceOrigin.dom,
          ForumImageSourceOrigin.dom,
          ForumImageSourceOrigin.dom,
        ],
      );
      expect(sources.map((source) => source.position).toList(), <int>[
        0,
        1,
        2,
        3,
      ]);
    });

    test('filters forum chrome by default and can include it explicitly', () {
      final post = ThreadPost(
        pid: '1',
        author: 'op',
        authorId: '100',
        message: '''
<img src="https://bbs.yamibo.com/static/image/common/smile.gif">
<img src="https://img.example/content.jpg">
''',
        number: 1,
        isFirst: true,
        dateline: '',
      );

      final defaultSources = pipeline.collectFromPost(post);
      final includedSources = pipeline.collectFromPost(
        post,
        options: const ForumImageSourceOptions(includeForumChrome: true),
      );

      expect(
        defaultSources.map((source) => source.normalizedUrl).toList(),
        <String>['https://img.example/content.jpg'],
      );
      expect(
        includedSources.map((source) => source.normalizedUrl).toList(),
        <String>[
          'https://bbs.yamibo.com/static/image/common/smile.gif',
          'https://img.example/content.jpg',
        ],
      );
    });

    test(
      'supports attachment image recognition and includeAttachments flag',
      () {
        final post = ThreadPost(
          pid: '1',
          author: 'op',
          authorId: '100',
          message: '<p>attachment only</p>',
          number: 1,
          isFirst: true,
          dateline: '',
          attachmentImages: const <ForumPostAttachmentImage>[
            ForumPostAttachmentImage(
              aid: '1',
              url: 'data/attachment/forum/',
              attachment: 'page.webp',
              filename: 'page.webp',
              attachimg: '0',
              ext: 'webp',
            ),
            ForumPostAttachmentImage(
              aid: '2',
              url: 'data/attachment/forum/',
              attachment: 'archive.zip',
              filename: 'archive.zip',
              attachimg: '0',
              ext: 'zip',
            ),
          ],
        );

        final sources = pipeline.collectFromPost(post);
        final noAttachments = pipeline.collectFromPost(
          post,
          options: const ForumImageSourceOptions(includeAttachments: false),
        );

        expect(sources.length, 1);
        expect(sources.single.origin, ForumImageSourceOrigin.attachment);
        expect(
          sources.single.normalizedUrl,
          'https://bbs.yamibo.com/data/attachment/forum/page.webp',
        );
        expect(sources.single.aid, '1');
        expect(noAttachments, isEmpty);
      },
    );

    test(
      'deduplicates DOM and attachment urls with DOM metadata winning first',
      () {
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
              attachment: 'attachment.jpg',
              filename: 'attachment.jpg',
              attachimg: '1',
              ext: 'jpg',
            ),
          ],
        );

        final sources = pipeline.collectFromPost(post);

        expect(sources.map((source) => source.normalizedUrl).toList(), <String>[
          'https://img.example/dom.jpg',
          'https://bbs.yamibo.com/data/attachment/forum/shared.jpg',
          'https://bbs.yamibo.com/data/attachment/forum/attachment.jpg',
        ]);
        expect(sources[1].origin, ForumImageSourceOrigin.dom);
        expect(sources[1].aid, isNull);
        expect(sources[2].origin, ForumImageSourceOrigin.attachment);
        expect(sources[2].aid, '2');
      },
    );
  });
}

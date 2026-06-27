import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_resource_layout_hints.dart';
import 'package:y300/features/thread/domain/services/thread_post_resource_layout_hint_resolver.dart';

void main() {
  group('ThreadPostResourceLayoutHintResolver', () {
    test('uses html dimensions for block images and inline images', () {
      const blockImage = ThreadPostImageBlock(
        url: 'https://bbs.yamibo.com/a.jpg',
        rawUrl: 'a.jpg',
        index: 0,
        originalWidth: 800,
        originalHeight: 400,
      );
      const inlineImage = ThreadPostInlineImage(
        url: 'https://bbs.yamibo.com/static/image/smiley/default/1.gif',
        rawUrl: 'static/image/smiley/default/1.gif',
        originalWidth: 32,
        originalHeight: 18,
      );
      const document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[
          blockImage,
          ThreadPostTextBlock(
            runs: <ThreadPostTextRun>[
              ThreadPostTextRun(text: '表情 '),
              ThreadPostTextRun(text: '', inlineImage: inlineImage),
            ],
          ),
        ],
      );

      const resolver = ThreadPostResourceLayoutHintResolver(
        lockForCurrentBuild: true,
      );

      final hints = resolver.resolve(document);
      final blockHint = hints.blockImage(blockImage);
      final inlineHint = hints.inlineImage(inlineImage);

      expect(blockHint?.aspectRatio, 2.0);
      expect(
        blockHint?.source,
        ThreadPostResourceLayoutHintSource.htmlAttribute,
      );
      expect(blockHint?.lockForCurrentBuild, isTrue);
      expect(inlineHint?.width, 32);
      expect(inlineHint?.height, 18);
      expect(
        inlineHint?.source,
        ThreadPostResourceLayoutHintSource.htmlAttribute,
      );
      expect(inlineHint?.lockForCurrentBuild, isTrue);
    });

    test('uses content default for block image without dimensions', () {
      const blockImage = ThreadPostImageBlock(
        url: 'https://bbs.yamibo.com/a.jpg',
        rawUrl: 'a.jpg',
        index: 0,
      );
      const document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[blockImage],
      );

      const resolver = ThreadPostResourceLayoutHintResolver(
        defaultBlockImageAspectRatio: 0.7,
      );

      final hint = resolver.resolve(document).blockImage(blockImage);

      expect(hint?.aspectRatio, 0.7);
      expect(hint?.source, ThreadPostResourceLayoutHintSource.contentDefault);
    });

    test('collects resource hints inside quote blocks', () {
      const image = ThreadPostImageBlock(
        url: 'https://bbs.yamibo.com/quote.jpg',
        rawUrl: 'quote.jpg',
        index: 1,
        originalWidth: 300,
        originalHeight: 600,
      );
      const document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[
          ThreadPostQuoteBlock(blocks: <ThreadPostBodyBlock>[image]),
        ],
      );

      final hint = const ThreadPostResourceLayoutHintResolver()
          .resolve(document)
          .blockImage(image);

      expect(hint?.aspectRatio, 0.5);
      expect(hint?.source, ThreadPostResourceLayoutHintSource.htmlAttribute);
    });
  });
}

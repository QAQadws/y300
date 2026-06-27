import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/services/thread_post_body_document_normalizer.dart';

void main() {
  group('ThreadPostBodyDocumentNormalizer', () {
    test('splits long text blocks without changing text or style', () {
      const normalizer = ThreadPostBodyDocumentNormalizer(maxTextRunLength: 5);
      const document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[
          ThreadPostTextBlock(
            anchorId: 'text-original',
            runs: <ThreadPostTextRun>[
              ThreadPostTextRun(
                text: 'abcdefghijk',
                linkUrl: 'https://bbs.yamibo.com/thread-1-1-1.html',
                isBold: true,
                isItalic: true,
                isUnderline: true,
              ),
            ],
          ),
        ],
      );

      final normalized = normalizer.normalize(document);

      expect(normalized.blocks, hasLength(3));
      final blocks = normalized.blocks.cast<ThreadPostTextBlock>();
      expect(blocks.map((block) => block.plainText).join(), 'abcdefghijk');
      expect(blocks.first.continuesPrevious, isFalse);
      expect(blocks.skip(1).every((block) => block.continuesPrevious), isTrue);
      for (final block in blocks) {
        final run = block.runs.single;
        expect(run.linkUrl, 'https://bbs.yamibo.com/thread-1-1-1.html');
        expect(run.isBold, isTrue);
        expect(run.isItalic, isTrue);
        expect(run.isUnderline, isTrue);
        expect(run.inlineImage, isNull);
        expect(block.anchorId, startsWith('text-'));
      }
    });

    test('keeps inline smiley image dimensions untouched', () {
      const normalizer = ThreadPostBodyDocumentNormalizer(maxTextRunLength: 4);
      const smiley = ThreadPostInlineImage(
        url: 'https://bbs.yamibo.com/static/image/smiley/comcom/2.gif',
        rawUrl: 'static/image/smiley/comcom/2.gif',
        originalWidth: 32,
        originalHeight: 18,
      );
      const document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[
          ThreadPostTextBlock(
            runs: <ThreadPostTextRun>[
              ThreadPostTextRun(text: '喜欢'),
              ThreadPostTextRun(text: '', inlineImage: smiley),
              ThreadPostTextRun(text: '表情'),
            ],
          ),
        ],
      );

      final normalized = normalizer.normalize(document);

      final runs = normalized.blocks
          .whereType<ThreadPostTextBlock>()
          .expand((block) => block.runs)
          .toList(growable: false);
      final inlineImage = runs.singleWhere((run) => run.inlineImage != null);
      expect(inlineImage.inlineImage!.originalWidth, 32);
      expect(inlineImage.inlineImage!.originalHeight, 18);
    });

    test('normalizes quote children recursively', () {
      const normalizer = ThreadPostBodyDocumentNormalizer(maxTextRunLength: 3);
      const document = ThreadPostBodyDocument(
        blocks: <ThreadPostBodyBlock>[
          ThreadPostQuoteBlock(
            anchorId: 'quote-original',
            blocks: <ThreadPostBodyBlock>[
              ThreadPostTextBlock(
                runs: <ThreadPostTextRun>[ThreadPostTextRun(text: 'abcdef')],
              ),
            ],
          ),
        ],
      );

      final normalized = normalizer.normalize(document);

      final quote = normalized.blocks.single as ThreadPostQuoteBlock;
      expect(quote.anchorId, 'quote-original');
      expect(quote.blocks, hasLength(2));
      expect(
        quote.blocks.whereType<ThreadPostTextBlock>().map((block) {
          return block.plainText;
        }).join(),
        'abcdef',
      );
      expect(quote.blocks.last.continuesPrevious, isTrue);
    });
  });
}

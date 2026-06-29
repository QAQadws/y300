import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/rich_text/document/rich_document.dart';
import 'package:y300/features/reader_shared/domain/rich_text/document/rich_document_codec.dart';

void main() {
  group('RichDocument', () {
    test('images getter collects block images including nested quotes', () {
      const document = RichDocument(
        blocks: <RichBlock>[
          RichImageBlock(url: 'a', rawUrl: 'a', index: 0),
          RichTextBlock(runs: <RichRun>[RichRun(text: 'hi')]),
          RichQuoteBlock(
            blocks: <RichBlock>[
              RichImageBlock(url: 'b', rawUrl: 'b', index: 1),
            ],
          ),
        ],
      );

      expect(document.images.map((image) => image.url), <String>['a', 'b']);
    });

    test('text block reports heading and plain text', () {
      const heading = RichTextBlock(
        runs: <RichRun>[RichRun(text: 'Title')],
        headingLevel: 2,
      );
      const body = RichTextBlock(
        runs: <RichRun>[RichRun(text: 'a'), RichRun(text: 'b')],
      );

      expect(heading.isHeading, isTrue);
      expect(body.isHeading, isFalse);
      expect(body.plainText, 'ab');
    });
  });

  group('RichDocumentCodec', () {
    const codec = RichDocumentCodec();

    test('round-trips a document with every block type', () {
      const document = RichDocument(
        blocks: <RichBlock>[
          RichTextBlock(
            anchorId: 'text-1',
            headingLevel: 1,
            runs: <RichRun>[
              RichRun(
                text: 'bold link',
                linkUrl: 'https://example.com',
                linkTid: '42',
                isBold: true,
                color: '#ff0000',
              ),
              RichRun(
                text: '',
                inlineImage: RichInlineImage(
                  url: 'https://img/smiley.gif',
                  rawUrl: 'smiley.gif',
                  aid: 'aid-9',
                  altText: ':)',
                  originalWidth: 20,
                  originalHeight: 20,
                ),
              ),
            ],
          ),
          RichQuoteBlock(
            anchorId: 'quote-1',
            blocks: <RichBlock>[
              RichTextBlock(runs: <RichRun>[RichRun(text: 'quoted')]),
            ],
          ),
          RichImageBlock(
            anchorId: 'image-1',
            url: 'https://img/full.jpg',
            rawUrl: 'full.jpg',
            index: 3,
            aid: 'aid-1',
            altText: 'pic',
            originalWidth: 800,
            originalHeight: 1200,
            continuesPrevious: true,
          ),
          RichDividerBlock(anchorId: 'divider-1'),
          RichSpacerBlock(anchorId: 'spacer-1'),
        ],
      );

      final decoded = codec.decodeDocument(codec.encodeDocument(document));

      expect(decoded.blocks.length, 5);

      final text = decoded.blocks[0] as RichTextBlock;
      expect(text.anchorId, 'text-1');
      expect(text.headingLevel, 1);
      expect(text.runs.first.linkTid, '42');
      expect(text.runs.first.isBold, isTrue);
      expect(text.runs.first.color, '#ff0000');
      final inline = text.runs[1].inlineImage!;
      expect(inline.aid, 'aid-9');
      expect(inline.originalWidth, 20);

      final quote = decoded.blocks[1] as RichQuoteBlock;
      expect((quote.blocks.single as RichTextBlock).runs.single.text, 'quoted');

      final image = decoded.blocks[2] as RichImageBlock;
      expect(image.aid, 'aid-1');
      expect(image.altText, 'pic');
      expect(image.originalHeight, 1200);
      expect(image.continuesPrevious, isTrue);

      expect(decoded.blocks[3], isA<RichDividerBlock>());
      expect(decoded.blocks[4], isA<RichSpacerBlock>());
    });

    test('tolerates string-keyed maps produced by isolate transport', () {
      final encoded = codec.encodeDocument(
        const RichDocument(
          blocks: <RichBlock>[
            RichTextBlock(runs: <RichRun>[RichRun(text: 'x')]),
          ],
        ),
      );
      // Simulate the Object?/Object? keying isolate boundaries can introduce.
      final reKeyed = <Object?, Object?>{...encoded};
      final decoded = codec.decodeDocument(
        reKeyed.map((key, value) => MapEntry(key.toString(), value)),
      );

      expect((decoded.blocks.single as RichTextBlock).runs.single.text, 'x');
    });

    test('falls back to empty text block on unknown type', () {
      final decoded = codec.decodeBlock(<String, Object?>{'type': 'mystery'});
      expect(decoded, isA<RichTextBlock>());
      expect((decoded as RichTextBlock).runs, isEmpty);
    });
  });
}

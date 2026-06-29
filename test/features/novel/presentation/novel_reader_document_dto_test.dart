import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_document_dto.dart';

void main() {
  test('document dto round trip preserves nested blocks and metadata', () {
    const document = NovelReaderDocument(
      episodeId: 'novel:49:100:5001',
      rawHtmlHash: 'hash-1',
      body: RichDocument(
        blocks: <RichBlock>[
          RichTextBlock(
            anchorId: 'node-0',
            headingLevel: 1,
            runs: <RichRun>[RichRun(text: '标题', isBold: true)],
          ),
          RichTextBlock(
            anchorId: 'node-1',
            runs: <RichRun>[
              RichRun(text: '正文 '),
              RichRun(
                text: '跳转原帖',
                linkUrl:
                    'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100',
                linkTid: '100',
                isItalic: true,
                color: '#ff0000',
              ),
            ],
          ),
          RichImageBlock(
            anchorId: 'node-2',
            url: 'https://example.com/image.jpg',
            rawUrl: 'image.jpg',
            index: 0,
            aid: '4567',
            altText: '插图',
          ),
        ],
      ),
      plainText: '标题\n正文 跳转原帖',
      wordCount: 8,
    );

    final roundTripped = NovelReaderDocumentDto.fromDocument(document)
        .toMap()
        .let(NovelReaderDocumentDto.fromMap)
        .toDocument();

    expect(roundTripped.episodeId, document.episodeId);
    expect(roundTripped.rawHtmlHash, document.rawHtmlHash);
    expect(roundTripped.plainText, document.plainText);
    expect(roundTripped.wordCount, document.wordCount);
    expect(roundTripped.blocks, hasLength(3));

    final heading = roundTripped.blocks[0] as RichTextBlock;
    expect(heading.isHeading, isTrue);
    expect(heading.runs.single.isBold, isTrue);

    final paragraph = roundTripped.blocks[1] as RichTextBlock;
    expect(paragraph.runs.last.linkTid, '100');
    expect(paragraph.runs.last.isItalic, isTrue);
    expect(paragraph.runs.last.color, '#ff0000');

    final image = roundTripped.blocks[2] as RichImageBlock;
    expect(image.aid, '4567');
    expect(image.altText, '插图');
  });
}

extension on Map<String, Object?> {
  T let<T>(T Function(Map<String, Object?> value) transform) {
    return transform(this);
  }
}

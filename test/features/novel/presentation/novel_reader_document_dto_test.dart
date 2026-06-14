import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_document_dto.dart';

void main() {
  test('document dto round trip preserves nested nodes and metadata', () {
    final document = NovelReaderDocument(
      episodeId: 'novel:49:100:5001',
      rawHtmlHash: 'hash-1',
      nodes: <NovelReaderNode>[
        NovelReaderNode(
          id: 'node-0',
          type: NovelReaderNodeType.heading,
          text: '标题',
          style: const NovelReaderInlineStyle(bold: true),
        ),
        NovelReaderNode(
          id: 'node-1',
          type: NovelReaderNodeType.paragraph,
          text: '正文',
          children: const <NovelReaderNode>[
            NovelReaderNode(
              id: 'node-1-0',
              type: NovelReaderNodeType.link,
              text: '跳转原帖',
              link: NovelReaderLink(
                url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100',
                text: '跳转原帖',
                tid: '100',
              ),
              style: NovelReaderInlineStyle(
                italic: true,
                color: '#ff0000',
              ),
            ),
          ],
        ),
        const NovelReaderNode(
          id: 'node-2',
          type: NovelReaderNodeType.image,
          image: NovelReaderImage(
            url: 'https://example.com/image.jpg',
            altText: '插图',
          ),
        ),
      ],
      plainText: '标题\n正文\n跳转原帖',
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
    expect(roundTripped.nodes, hasLength(3));
    expect(roundTripped.nodes[0].type, NovelReaderNodeType.heading);
    expect(roundTripped.nodes[0].style.bold, isTrue);
    expect(roundTripped.nodes[1].children.single.link?.tid, '100');
    expect(roundTripped.nodes[1].children.single.style.italic, isTrue);
    expect(roundTripped.nodes[1].children.single.style.color, '#ff0000');
    expect(roundTripped.nodes[2].image?.altText, '插图');
  });
}

extension on Map<String, Object?> {
  T let<T>(T Function(Map<String, Object?> value) transform) {
    return transform(this);
  }
}

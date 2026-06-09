import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/services/novel_reader_search_service.dart';

void main() {
  const service = NovelReaderSearchService();

  test('search finds Chinese keyword in source order with snippets', () {
    final results = service.search(
      document: _document(
        nodes: const <NovelReaderNode>[
          NovelReaderNode(
            id: 'n1',
            type: NovelReaderNodeType.paragraph,
            text: '这是第一段，关键词出现。',
          ),
          NovelReaderNode(
            id: 'n2',
            type: NovelReaderNodeType.paragraph,
            text: '关键词再次出现。',
          ),
        ],
      ),
      keyword: '关键词',
    );

    expect(results, hasLength(2));
    expect(results.first.nodeId, 'n1');
    expect(results.last.nodeId, 'n2');
    expect(results.first.snippet, contains('关键词'));
    expect(results.first.anchor.episodeId, 'episode-1');
    expect(results.first.anchor.nodeId, 'n1');
    expect(results.first.anchor.textOffset, greaterThanOrEqualTo(0));
  });

  test('search is case insensitive and returns empty for blank keyword', () {
    final document = _document(
      nodes: const <NovelReaderNode>[
        NovelReaderNode(
          id: 'n1',
          type: NovelReaderNodeType.paragraph,
          text: 'Alpha beta ALPHA',
        ),
      ],
    );

    expect(service.search(document: document, keyword: 'alpha'), hasLength(2));
    expect(service.search(document: document, keyword: '   '), isEmpty);
    expect(service.search(document: document, keyword: 'missing'), isEmpty);
  });
}

NovelReaderDocument _document({
  required List<NovelReaderNode> nodes,
}) {
  return NovelReaderDocument(
    episodeId: 'episode-1',
    rawHtmlHash: 'hash',
    nodes: nodes,
    plainText: nodes.map((node) => node.text ?? '').join('\n'),
    wordCount: 0,
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_anchor_format.dart';
import 'package:y300/features/novel/domain/models/novel_reader_document.dart';
import 'package:y300/features/novel/domain/services/novel_reader_search_service.dart';

void main() {
  const service = NovelReaderSearchService();

  test('search finds Chinese keyword in source order with snippets', () {
    final results = service.search(
      document: _document(
        blocks: const <RichBlock>[
          RichTextBlock(
            anchorId: 'n1',
            runs: <RichRun>[RichRun(text: '这是第一段，关键词出现。')],
          ),
          RichTextBlock(
            anchorId: 'n2',
            runs: <RichRun>[RichRun(text: '关键词再次出现。')],
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
      blocks: const <RichBlock>[
        RichTextBlock(
          anchorId: 'n1',
          runs: <RichRun>[RichRun(text: 'Alpha beta ALPHA')],
        ),
      ],
    );

    expect(service.search(document: document, keyword: 'alpha'), hasLength(2));
    expect(service.search(document: document, keyword: '   '), isEmpty);
    expect(service.search(document: document, keyword: 'missing'), isEmpty);
  });

  test(
    'search anchors use source code points while match ranges use UTF-16',
    () {
      const text = '  😀关键词  ';
      final results = service.search(
        document: _textDocument(text),
        keyword: '关键词',
      );
      final result = results.single;
      expect(result.matchStart, 4);
      expect(result.matchEnd, 7);
      expect(text.substring(result.matchStart, result.matchEnd), '关键词');
      expect(result.anchor.textOffset, 3);
      expect(
        result.anchor.formatVersion,
        NovelReaderAnchorFormat.semanticCodePoints,
      );
      expect(
        result.anchor.textIdentity,
        NovelReaderAnchorFormat.textIdentity(text),
      );
      expect(
        result.anchor.textIdentity,
        isNot(NovelReaderAnchorFormat.textIdentity(text.trim())),
      );
      expect(result.snippet, text);
    },
  );

  test('case conversion before a match cannot shift the source range', () {
    const text = 'İ beta BETA';
    final results = service.search(
      document: _textDocument(text),
      keyword: 'beta',
    );
    expect(
      results.map((result) => (result.matchStart, result.matchEnd)),
      <(int, int)>[(2, 6), (7, 11)],
    );
    expect(
      results.map(
        (result) => text.substring(result.matchStart, result.matchEnd),
      ),
      <String>['beta', 'BETA'],
    );
  });

  test('Unicode case folding and literal metacharacters use original text', () {
    final folded = service.search(
      document: _textDocument('K k K'),
      keyword: 'k',
    );
    expect(folded.map((result) => result.matchStart), <int>[0, 2, 4]);
    final literal = service.search(
      document: _textDocument('a.b axb a.b'),
      keyword: ' a.b ',
    );
    expect(
      literal.map((result) => (result.matchStart, result.matchEnd)),
      <(int, int)>[(0, 3), (8, 11)],
    );
    expect(literal.map((result) => result.keyword), everyElement('a.b'));
  });

  test('search spans rich runs without changing semantic node coordinates', () {
    const text = '😀跨样式关键词';
    final results = service.search(
      document: _document(
        blocks: const <RichBlock>[
          RichTextBlock(
            anchorId: 'n1',
            runs: <RichRun>[
              RichRun(text: '😀跨样式关'),
              RichRun(text: '键'),
              RichRun(text: '词'),
            ],
          ),
        ],
      ),
      keyword: '关键词',
    );
    final result = results.single;
    expect((result.matchStart, result.matchEnd), (5, 8));
    expect(result.anchor.textOffset, 4);
    expect(
      result.anchor.textIdentity,
      NovelReaderAnchorFormat.textIdentity(text),
    );
    expect(result.nodeId, 'n1');
  });

  test(
    'search snippet keeps whole Unicode context and a partial grapheme match',
    () {
      const family = '👩‍👩‍👧‍👦';
      final context = service
          .search(
            document: _textDocument('x${family}Ke\u0301z'),
            keyword: 'K',
            contextLength: 1,
          )
          .single;
      expect(context.snippet, '...${family}Ke\u0301...');
      final flag = service
          .search(
            document: _textDocument('x🇨🇳y'),
            keyword: '🇨',
            contextLength: 0,
          )
          .single;
      expect((flag.matchStart, flag.matchEnd), (1, 3));
      expect(flag.anchor.textOffset, 1);
      expect(flag.snippet, '...🇨🇳...');
    },
  );
}

NovelReaderDocument _textDocument(String text) => _document(
  blocks: <RichBlock>[
    RichTextBlock(
      anchorId: 'n1',
      runs: <RichRun>[RichRun(text: text)],
    ),
  ],
);

NovelReaderDocument _document({required List<RichBlock> blocks}) {
  return NovelReaderDocument(
    episodeId: 'episode-1',
    rawHtmlHash: 'hash',
    body: RichDocument(blocks: blocks),
    plainText: '',
    wordCount: 0,
  );
}

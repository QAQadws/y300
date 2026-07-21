import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_block_pagination.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_slice.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_flowable_complex_pagination.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_layout_policy_resolver.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_text_pagination.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_page_composer.dart';

void main() {
  test('counts only additional consecutive breaks as blank-line height', () {
    final composer = NovelReaderPaginationPageComposer(
      pageHeight: 100,
      lineHeight: 20,
    );

    composer.appendTextChunk(
      _textChunk('first', usedHeight: 60),
      participatesInInlineFlow: true,
    );
    composer.appendTextChunk(_breakChunk());
    composer.appendTextChunk(_breakChunk());
    composer.appendTextChunk(
      _textChunk('second', usedHeight: 20),
      participatesInInlineFlow: true,
    );

    final pages = composer.finish();

    expect(pages, hasLength(1));
    expect(pages.single.usedHeight, 100);
    expect(pages.single.html, 'first<br><br>second');
  });

  test('counts every break adjacent to a block boundary', () {
    final composer = NovelReaderPaginationPageComposer(
      pageHeight: 100,
      lineHeight: 20,
    );

    composer.appendTextChunk(
      _textChunk('inline', usedHeight: 60),
      participatesInInlineFlow: true,
    );
    composer.appendTextChunk(_breakChunk());
    composer.appendTextChunk(_textChunk('block', usedHeight: 20));

    final pages = composer.finish();

    expect(pages, hasLength(1));
    expect(pages.single.usedHeight, 100);
    expect(pages.single.html, 'inline<br>block');
  });

  test('drops trailing structural breaks instead of overflowing the page', () {
    final composer = NovelReaderPaginationPageComposer(
      pageHeight: 100,
      lineHeight: 20,
    );

    composer.appendTextChunk(_textChunk('first', usedHeight: 90));
    composer.appendTextChunk(_breakChunk());

    final pages = composer.finish();

    expect(pages, hasLength(1));
    expect(pages.single.html, 'first');
    expect(pages.single.usedHeight, 90);
  });

  test('does not publish a page for leading structural breaks', () {
    final composer = NovelReaderPaginationPageComposer(
      pageHeight: 100,
      lineHeight: 20,
    );

    composer.appendTextChunk(_breakChunk());

    expect(composer.finish(), isEmpty);
  });

  test('uses measured composition height and keeps the page open', () {
    final composer = NovelReaderPaginationPageComposer(
      pageHeight: 100,
      lineHeight: 20,
    );
    composer.appendTextChunk(_textChunk('safe', usedHeight: 20));

    composer.appendFlowableComplexChunk(
      _complexChunk('complex', start: 5, end: 12, composedHeight: 55),
    );
    composer.appendTextChunk(_textChunk('tail', usedHeight: 30));
    final pages = composer.finish();

    expect(pages, hasLength(1));
    expect(pages.single.html, 'safecomplextail');
    expect(pages.single.usedHeight, 85);
    expect(pages.single.anchorRanges, hasLength(3));
  });

  test('includes pending structural HTML in a complex page snapshot', () {
    final composer = NovelReaderPaginationPageComposer(
      pageHeight: 100,
      lineHeight: 20,
    );
    composer.appendTextChunk(_textChunk('safe', usedHeight: 20));
    composer.appendTextChunk(_breakChunk());

    expect(composer.flowableComplexPageContext.bufferedHtml, 'safe<br>');
    composer.appendFlowableComplexChunk(
      _complexChunk('complex', start: 5, end: 12, composedHeight: 60),
    );

    final page = composer.finish().single;
    expect(page.html, 'safe<br>complex');
    expect(page.usedHeight, 60);
  });

  test('flushes around every dedicated table block', () {
    final composer = NovelReaderPaginationPageComposer(
      pageHeight: 100,
      lineHeight: 20,
    );
    composer.appendTextChunk(_textChunk('before', usedHeight: 20));
    composer.appendDedicatedBlock(_tableAtom(), _tableBlock());
    composer.appendTextChunk(_textChunk('after', usedHeight: 20));

    final pages = composer.finish();
    expect(pages, hasLength(3));
    expect(pages[0].html, 'before');
    expect(pages[1].html, '<table><tr><td>x</td></tr></table>');
    expect(pages[1].gapReason, NovelReaderPageGapReason.dedicatedTable);
    expect(pages[2].html, 'after');
  });
}

NovelReaderFlowableComplexChunk _complexChunk(
  String html, {
  required int start,
  required int end,
  required double composedHeight,
}) {
  return NovelReaderFlowableComplexChunk(
    slice: NovelReaderComplexHtmlSlice(
      html: html,
      startAnchor: NovelReaderTextAnchor(
        episodeId: 'composer-test',
        nodeId: 'complex',
        textOffset: start,
      ),
      endAnchor: NovelReaderTextAnchor(
        episodeId: 'composer-test',
        nodeId: 'complex',
        textOffset: end,
      ),
      startOffset: start,
      endOffset: end,
      hasRenderableContent: true,
    ),
    composedHeight: composedHeight,
    requiresFreshPage: false,
    flushAfterAppend: false,
  );
}

NovelReaderClassifiedPaginationAtom _tableAtom() {
  final atom = NovelReaderPaginationAtom(
    atomId: 'table',
    kind: NovelReaderPaginationAtomKind.atomicWidget,
    html: '<table><tr><td>x</td></tr></table>',
    startAnchor: const NovelReaderTextAnchor(
      episodeId: 'composer-test',
      nodeId: 'table',
    ),
    endAnchor: const NovelReaderTextAnchor(
      episodeId: 'composer-test',
      nodeId: 'table',
      textOffset: 1,
    ),
    textLength: 1,
    imageIndices: const <int>[],
    breakability: NovelReaderFlowUnitBreakability.atomicWidget,
    imagePagePolicy: NovelReaderImagePagePolicy.inline,
  );
  return NovelReaderClassifiedPaginationAtom(
    atom: atom,
    route: NovelReaderPaginationRoute.tableBlock,
    reason: NovelReaderPaginationRouteReason.containsTable,
    layoutPolicy: const DefaultNovelReaderPaginationLayoutPolicyResolver()
        .resolve(NovelReaderPaginationRoute.tableBlock),
  );
}

NovelReaderComplexBlockPage _tableBlock() {
  return const NovelReaderComplexBlockPage(
    html: '<table><tr><td>x</td></tr></table>',
    startAnchor: NovelReaderTextAnchor(
      episodeId: 'composer-test',
      nodeId: 'table',
    ),
    endAnchor: NovelReaderTextAnchor(
      episodeId: 'composer-test',
      nodeId: 'table',
      textOffset: 1,
    ),
    metrics: NovelReaderComplexBlockMetrics(
      height: 30,
      route: NovelReaderPaginationRoute.tableBlock,
      isOversized: false,
      requiresInnerScroll: false,
      measurementCacheHit: false,
      frameWaitCount: 0,
    ),
  );
}

NovelReaderTextPageChunk _textChunk(String html, {required double usedHeight}) {
  return NovelReaderTextPageChunk(
    html: html,
    startAnchor: const NovelReaderTextAnchor(
      episodeId: 'composer-test',
      nodeId: 'text',
    ),
    endAnchor: const NovelReaderTextAnchor(
      episodeId: 'composer-test',
      nodeId: 'text',
      textOffset: 5,
    ),
    sourceStart: 0,
    sourceEnd: 5,
    usedHeight: usedHeight,
    isOversized: false,
    hasRenderableContent: true,
  );
}

NovelReaderTextPageChunk _breakChunk() {
  return const NovelReaderTextPageChunk(
    html: '<br>',
    startAnchor: NovelReaderTextAnchor(
      episodeId: 'composer-test',
      nodeId: 'break',
    ),
    endAnchor: NovelReaderTextAnchor(
      episodeId: 'composer-test',
      nodeId: 'break',
    ),
    sourceStart: 0,
    sourceEnd: 0,
    usedHeight: 0,
    isOversized: false,
    hasRenderableContent: false,
    structuralBreakCount: 1,
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
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

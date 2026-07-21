import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_slice.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_boundary_indexer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_text_range_slicer.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_fragment_codec.dart';

void main() {
  test('indexes once and rebuilds closed nested wrappers for every slice', () {
    final codec = _CountingFragmentCodec();
    final session =
        DefaultNovelReaderComplexHtmlBoundaryIndexer(
          fragmentCodec: codec,
        ).prepare(
          html:
              '<article data-legacy="1"><strong>甲</strong>'
              '<font face="Uninstalled Fantasy Font" color="red">乙</font>'
              '<span style="background-color:#ffeeaa">丙</span>'
              '<a href="thread-1-1-1.html">丁</a>'
              '<legacy-wrap data-value="kept">戊</legacy-wrap>'
              '<ruby>鬼<rp>(</rp><rt>おに</rt><rp>)</rp></ruby>己</article>',
          startAnchor: _anchor,
        );

    final slices = _consecutiveSlices(session);
    final combinedText = slices
        .map((slice) => html_parser.parseFragment(slice.html).text ?? '')
        .join();

    expect(codec.parseCount, 1);
    expect(combinedText, '甲乙丙丁戊鬼(おに)己');
    expect(
      slices.any((slice) => slice.html.contains('<strong>甲</strong>')),
      isTrue,
    );
    expect(slices.any((slice) => slice.html.contains('color="red"')), isTrue);
    expect(
      slices.any((slice) => slice.html.contains('background-color')),
      isTrue,
    );
    expect(
      slices.any((slice) => slice.html.contains('thread-1-1-1.html')),
      isTrue,
    );
    expect(
      slices.any((slice) => slice.html.contains('data-value="kept"')),
      isTrue,
    );
    expect(
      slices.where((slice) => slice.html.contains('<ruby>')),
      hasLength(1),
    );
    for (var index = 1; index < slices.length; index += 1) {
      expect(
        slices[index - 1].endAnchor.textOffset,
        slices[index].startAnchor.textOffset,
      );
      expect(slices[index - 1].endOffset, slices[index].startOffset);
    }
    for (final slice in slices) {
      expect(html_parser.parseFragment(slice.html).nodes, isNotEmpty);
    }
    expect(codec.parseCount, 1);
  });

  test('uses grapheme offsets for emoji and combining characters', () {
    final session = const DefaultNovelReaderComplexHtmlBoundaryIndexer()
        .prepare(
          html: '<p>A👩‍👩‍👧‍👦e\u0301中</p>',
          startAnchor: _anchor.copyWith(textOffset: 7),
        );

    expect(session.textLength, 4);
    expect(session.boundaries.map((boundary) => boundary.textOffset), <int>[
      1,
      2,
      3,
      4,
    ]);
    final slices = <NovelReaderComplexHtmlSlice>[
      session.slice(startOffset: 0, endOffset: 1),
      session.slice(startOffset: 1, endOffset: 2),
      session.slice(startOffset: 2, endOffset: 3),
      session.slice(startOffset: 3, endOffset: 4),
    ];

    expect(
      slices.map((slice) => html_parser.parseFragment(slice.html).text),
      <String>['A', '👩‍👩‍👧‍👦', 'e\u0301', '中'],
    );
    expect(slices.first.startAnchor.textOffset, 7);
    expect(slices.first.endAnchor.textOffset, 8);
    expect(slices.last.endAnchor.textOffset, 11);
    expect(
      slices.every((slice) => slice.startAnchor.nodeId == 'node-1'),
      isTrue,
    );
  });

  test('keeps an HTML entity as one decoded grapheme and re-escapes it', () {
    final session = const DefaultNovelReaderComplexHtmlBoundaryIndexer()
        .prepare(html: '<p>A&amp;B</p>', startAnchor: _anchor);

    expect(session.textLength, 3);
    final entity = session.slice(startOffset: 1, endOffset: 2);
    expect(entity.html, contains('&amp;'));
    expect(html_parser.parseFragment(entity.html).text, '&');
  });

  test('protects complete ruby base rt and rp content from split points', () {
    final session = const DefaultNovelReaderComplexHtmlBoundaryIndexer()
        .prepare(
          html: '<p>前<ruby>鬼魂<rp>(</rp><rt>Ghost</rt><rp>)</rp></ruby>后</p>',
          startAnchor: _anchor,
        );
    final range = session.protectedRanges.single;

    expect(range.kind, NovelReaderComplexProtectedRangeKind.ruby);
    expect(range.startOffset, 1);
    expect(range.endOffset, greaterThan(range.startOffset + 1));
    expect(
      session.boundaries.any(
        (boundary) => range.containsInteriorOffset(boundary.textOffset),
      ),
      isFalse,
    );
    expect(session.isLegalBoundary(range.startOffset), isTrue);
    expect(session.isLegalBoundary(range.endOffset), isTrue);

    final ruby = session.slice(
      startOffset: range.startOffset,
      endOffset: range.endOffset,
    );
    final fragment = html_parser.parseFragment(ruby.html);
    expect(fragment.querySelectorAll('ruby'), hasLength(1));
    expect(fragment.querySelectorAll('rt'), hasLength(1));
    expect(fragment.querySelectorAll('rp'), hasLength(2));
    expect(fragment.text, '鬼魂(Ghost)');
    expect(
      () => session.slice(
        startOffset: range.startOffset,
        endOffset: range.startOffset + 1,
      ),
      throwsArgumentError,
    );
  });

  test('treats a known smiley as one protected inline placeholder', () {
    final session = const DefaultNovelReaderComplexHtmlBoundaryIndexer()
        .prepare(
          html:
              '<p>前<img class="smilie" '
              'src="static/image/smiley/default/smile.gif" '
              'width="24" height="24">后</p>',
          startAnchor: _anchor,
        );
    final range = session.protectedRanges.single;

    expect(session.textLength, 3);
    expect(range.startOffset, 1);
    expect(range.endOffset, 2);
    expect(range.kind, NovelReaderComplexProtectedRangeKind.inlineWidget);
    expect(
      session.boundaries
          .singleWhere((boundary) => boundary.textOffset == 2)
          .anchor
          .textOffset,
      1,
      reason: 'Synthetic inline placeholders must not advance text anchors.',
    );
    final smiley = session.slice(startOffset: 1, endOffset: 2);
    expect(smiley.hasRenderableContent, isTrue);
    expect(
      html_parser.parseFragment(smiley.html).querySelectorAll('img'),
      hasLength(1),
    );

    final slices = _consecutiveSlices(session);
    expect(
      slices
          .expand(
            (slice) =>
                html_parser.parseFragment(slice.html).querySelectorAll('img'),
          )
          .length,
      1,
    );
    expect(
      slices.map((slice) => html_parser.parseFragment(slice.html).text).join(),
      '前后',
    );
  });

  test('does not protect an asynchronously sized smiley', () {
    final session = const DefaultNovelReaderComplexHtmlBoundaryIndexer()
        .prepare(
          html: '<p>前<img src="static/image/smiley/default/smile.gif">后</p>',
          startAnchor: _anchor,
        );

    expect(session.protectedRanges, isEmpty);
    expect(session.textLength, 2);
  });

  test('deduplicates offsets using semantic boundary preference', () {
    final session = const DefaultNovelReaderComplexHtmlBoundaryIndexer()
        .prepare(html: '<p>句。<br>后</p><p>尾</p>', startAnchor: _anchor);
    final atBreak = session.boundaries.singleWhere(
      (boundary) => boundary.textOffset == 2,
    );
    final firstBlockEnd = session.boundaries.singleWhere(
      (boundary) => boundary.textOffset == 3,
    );
    final atomEnd = session.boundaries.last;

    expect(atBreak.kind, NovelReaderComplexBoundaryKind.hardBreak);
    expect(firstBlockEnd.kind, NovelReaderComplexBoundaryKind.blockEnd);
    expect(atomEnd.textOffset, session.textLength);
    expect(atomEnd.kind, NovelReaderComplexBoundaryKind.atomEnd);
    final offsets = session.boundaries
        .map((boundary) => boundary.textOffset)
        .toList();
    expect(offsets, orderedEquals(offsets.toSet().toList()..sort()));
  });

  test('marks whitespace and zero-text ranges as non-renderable', () {
    final whitespace = const DefaultNovelReaderComplexHtmlBoundaryIndexer()
        .prepare(
          html: '<div> \n&nbsp;　</div><br><div></div><p>正文</p>',
          startAnchor: _anchor,
        );
    final firstBlockEnd = whitespace.boundaries.firstWhere(
      (boundary) => boundary.kind == NovelReaderComplexBoundaryKind.blockEnd,
    );
    final blank = whitespace.slice(
      startOffset: 0,
      endOffset: firstBlockEnd.textOffset,
    );

    expect(blank.hasRenderableContent, isFalse);
    expect(html_parser.parseFragment(blank.html).text?.trim(), isEmpty);

    final empty = const DefaultNovelReaderComplexHtmlBoundaryIndexer().prepare(
      html: '<div></div><br>',
      startAnchor: _anchor,
    );
    expect(empty.textLength, 0);
    expect(
      empty.boundaries.single.kind,
      NovelReaderComplexBoundaryKind.atomEnd,
    );
    final emptySlice = empty.slice(startOffset: 0, endOffset: 0);
    expect(emptySlice.html, isEmpty);
    expect(emptySlice.hasRenderableContent, isFalse);
  });

  test('existing rune slicer delegates to one shared DOM parse', () {
    final codec = _CountingFragmentCodec();
    final session = NovelReaderHtmlTextRangeSlicer(
      fragmentCodec: codec,
    ).prepare('<p><strong>甲乙</strong><br><span>丙丁</span></p>');

    final first = session.slice(start: 0, end: 2);
    final second = session.slice(start: 2, end: 4);

    expect(codec.parseCount, 1);
    expect(html_parser.parseFragment(first).text, '甲乙');
    expect(html_parser.parseFragment(second).text, '丙丁');
    expect(second, contains('<br>'));
    expect(session.slice(start: 4, end: 99), isEmpty);
    expect(codec.parseCount, 1);
  });

  test('generated nested wrapper matrix never loses graphemes', () {
    const wrappers = <(String, String)>[
      ('<strong>', '</strong>'),
      ('<font face="Uninstalled Fantasy Font">', '</font>'),
      ('<span style="background-color:#ffeeaa">', '</span>'),
      ('<a href="thread-1-1-1.html">', '</a>'),
      ('<legacy-wrap data-value="1">', '</legacy-wrap>'),
    ];
    const text = '甲👩‍👩‍👧‍👦e\u0301乙';

    for (var mask = 1; mask < (1 << wrappers.length); mask += 1) {
      var open = '';
      var close = '';
      for (var index = 0; index < wrappers.length; index += 1) {
        if (mask & (1 << index) == 0) {
          continue;
        }
        open += wrappers[index].$1;
        close = '${wrappers[index].$2}$close';
      }
      final html = '<div>$open$text$close</div>';
      final session = const DefaultNovelReaderComplexHtmlBoundaryIndexer()
          .prepare(html: html, startAnchor: _anchor);
      final slices = _consecutiveSlices(session);
      final reconstructed = slices
          .map((slice) => html_parser.parseFragment(slice.html).text ?? '')
          .join();

      expect(reconstructed, text, reason: 'mask=$mask');
      expect(session.textLength, 4, reason: 'mask=$mask');
      for (final slice in slices) {
        expect(html_parser.parseFragment(slice.html).nodes, isNotEmpty);
      }
    }
  });
}

List<NovelReaderComplexHtmlSlice> _consecutiveSlices(
  NovelReaderComplexHtmlSliceSession session,
) {
  final offsets = <int>{
    0,
    ...session.boundaries.map((boundary) => boundary.textOffset),
  }.toList()..sort();
  return <NovelReaderComplexHtmlSlice>[
    for (var index = 1; index < offsets.length; index += 1)
      session.slice(startOffset: offsets[index - 1], endOffset: offsets[index]),
  ];
}

final class _CountingFragmentCodec implements ForumHtmlFragmentCodec {
  final HtmlPackageForumHtmlFragmentCodec _delegate =
      const HtmlPackageForumHtmlFragmentCodec();
  int parseCount = 0;

  @override
  html_dom.DocumentFragment parse(String html) {
    parseCount += 1;
    return _delegate.parse(html);
  }

  @override
  String serialize(html_dom.DocumentFragment fragment) {
    return _delegate.serialize(fragment);
  }
}

const _anchor = NovelReaderTextAnchor(episodeId: 'episode-1', nodeId: 'node-1');

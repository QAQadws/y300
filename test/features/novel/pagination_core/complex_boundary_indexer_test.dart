import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/html_pagination_core/html_pagination_core.dart';

void main() {
  test('indexes once and rebuilds closed nested wrappers for every slice', () {
    final codec = _CountingFragmentParser();
    final session = DefaultHtmlComplexBoundaryIndexer(fragmentParser: codec)
        .prepare(
          html:
              '<article data-legacy="1"><strong>甲</strong>'
              '<font face="Uninstalled Fantasy Font" color="red">乙</font>'
              '<span style="background-color:#ffeeaa">丙</span>'
              '<a href="thread-1-1-1.html">丁</a>'
              '<legacy-wrap data-value="kept">戊</legacy-wrap>'
              '<ruby>鬼<rp>(</rp><rt>おに</rt><rp>)</rp></ruby>己</article>',
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
      expect(slices[index - 1].sourceRuneEnd, slices[index].sourceRuneStart);
      expect(slices[index - 1].endOffset, slices[index].startOffset);
    }
    for (final slice in slices) {
      expect(html_parser.parseFragment(slice.html).nodes, isNotEmpty);
      expect(slice.domNodeCount, _serializedDomNodeCount(slice.html));
    }
    expect(codec.parseCount, 1);
  });

  test('segments combining and ZWJ text across inline wrappers together', () {
    const text = 'Ae\u0301👩‍👩‍👧‍👦Z';
    final session = const DefaultHtmlComplexBoundaryIndexer().prepare(
      html:
          '<p>A<strong data-part="base">e</strong><i>\u0301</i>'
          '<span>👩</span><span>\u200d👩\u200d</span>'
          '<em>👧\u200d👦</em>Z</p>',
    );
    final slices = _consecutiveSlices(session);

    expect(session.textLength, 4);
    expect(
      slices.map((slice) => html_parser.parseFragment(slice.html).text),
      <String>['A', 'e\u0301', '👩‍👩‍👧‍👦', 'Z'],
    );
    expect(slices[1].html, contains('data-part="base"'));
    expect(slices[1].html, contains('<i>\u0301</i>'));
    expect(slices.map((slice) => slice.sourceRuneEnd), <int>[1, 3, 10, 11]);
    expect(session.sourceRuneLength, text.runes.length);
  });

  test('counts BR in the source axis but not a textless inline widget', () {
    final index =
        const HtmlTextRangeSlicer(
          protectedInlinePredicate: _protectDeclaredInline,
        ).prepare(
          '<p>A<br><span><img data-protected-inline="1" '
          'src="inline.png" width="24" height="24">'
          '<img data-protected-inline="1" src="inline.png" '
          'width="24" height="24"></span>B</p>',
        );

    expect(index.runeLength, 3);
    expect(index.graphemeLength, 5);
    expect(List<int>.generate(6, index.sourceRuneAtGraphemeBoundary), <int>[
      0,
      1,
      2,
      2,
      2,
      3,
    ]);
    expect(index.sliceRunes(start: 1, end: 2).html, contains('<br>'));
    expect(
      html_parser
          .parseFragment(index.sliceGraphemes(start: 2, end: 3).html)
          .querySelectorAll('img'),
      hasLength(1),
      reason: 'Zero-source widgets in one wrapper still own separate ranges.',
    );
  });

  test('empty inline siblings do not hide protected widgets in a wrapper', () {
    const image =
        '<img data-protected-inline="1" '
        'src="inline.png" width="24" height="24">';
    for (final (children, expectedImages) in <(String, int)>[
      ('<em></em>$image', 1),
      ('$image<em></em>', 1),
      ('<em></em>$image<i></i>$image<b></b>', 2),
    ]) {
      final session = const DefaultHtmlComplexBoundaryIndexer(
        protectedInlinePredicate: _protectDeclaredInline,
      ).prepare(html: '<p>A<span data-wrapper="kept">$children</span>B</p>');
      final slices = _consecutiveSlices(session);
      expect(
        slices
            .map((slice) => html_parser.parseFragment(slice.html).text)
            .join(),
        'AB',
        reason: children,
      );
      expect(
        slices.expand(
          (slice) =>
              html_parser.parseFragment(slice.html).querySelectorAll('img'),
        ),
        hasLength(expectedImages),
        reason: children,
      );
      for (var offset = 1; offset <= expectedImages; offset += 1) {
        final slice = session.slice(startOffset: offset, endOffset: offset + 1);
        final fragment = html_parser.parseFragment(slice.html);
        expect(
          fragment.querySelectorAll('img'),
          hasLength(1),
          reason: children,
        );
        expect(
          fragment.querySelector('span')?.attributes['data-wrapper'],
          'kept',
        );
      }
    }
  });

  test('keeps an HTML entity as one decoded grapheme and re-escapes it', () {
    final session = const DefaultHtmlComplexBoundaryIndexer().prepare(
      html: '<p>A&amp;B</p>',
    );

    expect(session.textLength, 3);
    final entity = session.slice(startOffset: 1, endOffset: 2);
    expect(entity.html, contains('&amp;'));
    expect(html_parser.parseFragment(entity.html).text, '&');
  });

  test('protects complete ruby base rt and rp content from split points', () {
    final session = const DefaultHtmlComplexBoundaryIndexer().prepare(
      html: '<p>前<ruby>鬼魂<rp>(</rp><rt>Ghost</rt><rp>)</rp></ruby>后</p>',
    );
    final range = session.protectedRanges.single;

    expect(range.kind, HtmlComplexProtectedRangeKind.ruby);
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
    expect(ruby.domNodeCount, 9);
    expect(
      () => session.slice(
        startOffset: range.startOffset,
        endOffset: range.startOffset + 1,
      ),
      throwsArgumentError,
    );
  });

  test('deduplicates offsets using semantic boundary preference', () {
    final session = const DefaultHtmlComplexBoundaryIndexer().prepare(
      html: '<p>句。<br>后</p><p>尾</p>',
    );
    final atBreak = session.boundaries.singleWhere(
      (boundary) => boundary.textOffset == 2,
    );
    final firstBlockEnd = session.boundaries.singleWhere(
      (boundary) => boundary.textOffset == 4,
    );
    final atomEnd = session.boundaries.last;

    expect(atBreak.kind, HtmlComplexBoundaryKind.hardBreak);
    expect(firstBlockEnd.kind, HtmlComplexBoundaryKind.blockEnd);
    expect(atomEnd.textOffset, session.textLength);
    expect(atomEnd.kind, HtmlComplexBoundaryKind.atomEnd);
    final offsets = session.boundaries
        .map((boundary) => boundary.textOffset)
        .toList();
    expect(offsets, orderedEquals(offsets.toSet().toList()..sort()));
  });

  test(
    'looks up a sorted immutable boundary range without copying a suffix',
    () {
      final text = List<String>.filled(1024, '甲').join();
      final session = const DefaultHtmlComplexBoundaryIndexer().prepare(
        html:
            '<p>$text<strong>e</strong><i>\u0301</i><br>'
            '<ruby>字<rt>じ</rt></ruby><img data-protected-inline="1" '
            'src="inline.png" '
            'width="24" height="24">尾</p>',
      );
      final boundaries = session.boundaries;
      final offsets = boundaries
          .map((boundary) => boundary.textOffset)
          .toList();

      expect(offsets, orderedEquals(offsets.toSet().toList()..sort()));
      expect(
        boundaries.every(
          (boundary) => session.isLegalBoundary(boundary.textOffset),
        ),
        isTrue,
      );
      expect(boundaries.last.textOffset, session.textLength);
      expect(() => boundaries.clear(), throwsUnsupportedError);
      for (final offset in <int>{
        0,
        1,
        511,
        1023,
        ...List<int>.generate(
          session.textLength - 1024 + 1,
          (index) => 1024 + index,
        ),
      }) {
        final reference = boundaries.indexWhere(
          (boundary) => boundary.textOffset > offset,
        );
        expect(
          session.firstBoundaryIndexAfter(offset),
          reference == -1 ? boundaries.length : reference,
          reason: 'offset=$offset',
        );
      }
      expect(identical(session.boundaries, boundaries), isTrue);
      expect(() => session.firstBoundaryIndexAfter(-1), throwsRangeError);
      expect(
        () => session.firstBoundaryIndexAfter(session.textLength + 1),
        throwsRangeError,
      );

      final empty = const DefaultHtmlComplexBoundaryIndexer().prepare(html: '');
      expect(empty.firstBoundaryIndexAfter(0), empty.boundaries.length);
    },
  );

  test('counts retained clone nodes without parsing each candidate again', () {
    final codec = _CountingFragmentParser();
    final index =
        HtmlTextRangeSlicer(
          fragmentParser: codec,
          protectedInlinePredicate: _protectDeclaredInline,
        ).prepare(
          '<div>A<!--kept--><script>opaque</script>'
          '<span>e</span><i>\u0301</i><br>'
          '<ruby>字<rt>じ</rt></ruby><img data-protected-inline="1" '
          'src="inline.png" '
          'width="24" height="24">B</div>',
        );
    final complex = index.sliceGraphemes(start: 1, end: 2);

    // The opaque script's child is retained by a deep clone even though the
    // source text index deliberately ignores that subtree.
    expect(complex.html, contains('<script>opaque</script>'));
    expect(complex.html, contains('<!--kept-->'));
    expect(complex.domNodeCount, 8);
    expect(complex.domNodeCount, _serializedDomNodeCount(complex.html));
    for (final slice in <HtmlDomTextSlice>[
      index.sliceRunes(start: 1, end: 3),
      index.sliceRunes(start: 0, end: index.runeLength),
      index.sliceGraphemes(start: 0, end: index.graphemeLength),
      index.sliceGraphemes(start: 3, end: index.graphemeLength),
      index.sliceGraphemes(start: 2, end: 2),
    ]) {
      expect(slice.domNodeCount, _serializedDomNodeCount(slice.html));
    }
    expect(index.sliceGraphemes(start: 2, end: 2).domNodeCount, 0);
    expect(codec.parseCount, 1);
  });

  test('marks whitespace and zero-text ranges as non-renderable', () {
    final whitespace = const DefaultHtmlComplexBoundaryIndexer().prepare(
      html: '<div> \n&nbsp;　</div><br><div></div><p>正文</p>',
    );
    final firstBlockEnd = whitespace.boundaries.firstWhere(
      (boundary) => boundary.kind == HtmlComplexBoundaryKind.blockEnd,
    );
    final blank = whitespace.slice(
      startOffset: 0,
      endOffset: firstBlockEnd.textOffset,
    );

    expect(blank.hasRenderableContent, isFalse);
    expect(html_parser.parseFragment(blank.html).text?.trim(), isEmpty);

    final empty = const DefaultHtmlComplexBoundaryIndexer().prepare(
      html: '<div></div>',
    );
    expect(empty.textLength, 0);
    expect(empty.boundaries.single.kind, HtmlComplexBoundaryKind.atomEnd);
    final emptySlice = empty.slice(startOffset: 0, endOffset: 0);
    expect(emptySlice.html, isEmpty);
    expect(emptySlice.hasRenderableContent, isFalse);
    expect(emptySlice.domNodeCount, 0);
  });

  test('existing rune slicer delegates to one shared DOM parse', () {
    final codec = _CountingFragmentParser();
    final session = HtmlTextRangeSlicer(
      fragmentParser: codec,
    ).prepare('<p><strong>甲乙</strong><br><span>丙丁</span></p>');

    final first = session.slice(start: 0, end: 2);
    final second = session.slice(start: 2, end: 5);

    expect(codec.parseCount, 1);
    expect(html_parser.parseFragment(first).text, '甲乙');
    expect(html_parser.parseFragment(second).text, '丙丁');
    expect(second, contains('<br>'));
    expect(session.slice(start: 5, end: 99), isEmpty);
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
      final open = StringBuffer();
      final closingTags = <String>[];
      for (var index = 0; index < wrappers.length; index += 1) {
        if (mask & (1 << index) == 0) {
          continue;
        }
        open.write(wrappers[index].$1);
        closingTags.add(wrappers[index].$2);
      }
      final close = closingTags.reversed.join();
      final html = '<div>$open$text$close</div>';
      final session = const DefaultHtmlComplexBoundaryIndexer().prepare(
        html: html,
      );
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

  test('preserves the distinct top-level and nested comment serialization', () {
    final session = const HtmlTextRangeSlicer().prepare(
      '<!--lead--><p>A<!--nested-->B</p><!--tail-->',
    );
    expect(session.runeLength, 2);
    expect(session.graphemeLength, 2);
    for (final slice in [
      session.sliceRunes(start: 0, end: 2),
      session.sliceGraphemes(start: 0, end: 2),
    ]) {
      // Top-level opaque comments use node.text; nested comments use outerHtml.
      // The trailing zero-source comment belongs outside the half-open range.
      expect(slice.html, 'lead<p>A<!--nested-->B</p>');
      expect(slice.domNodeCount, 5);
      expect(slice.hasRenderableContent, isTrue);
    }
    expect(session.slice(start: 1, end: 2), '<p><!--nested-->B</p>');
    expect(session.sliceRunes(start: 2, end: 2).html, isEmpty);
  });
}

List<HtmlComplexSlice> _consecutiveSlices(HtmlComplexSliceSession session) {
  final offsets = <int>{
    0,
    ...session.boundaries.map((boundary) => boundary.textOffset),
  }.toList()..sort();
  return <HtmlComplexSlice>[
    for (var index = 1; index < offsets.length; index += 1)
      session.slice(startOffset: offsets[index - 1], endOffset: offsets[index]),
  ];
}

int _serializedDomNodeCount(String html) {
  int count(html_dom.Node node) =>
      1 + node.nodes.fold<int>(0, (total, child) => total + count(child));
  return html_parser
      .parseFragment(html)
      .nodes
      .fold<int>(0, (total, node) => total + count(node));
}

bool _protectDeclaredInline(html_dom.Element element) =>
    element.attributes.containsKey('data-protected-inline');

final class _CountingFragmentParser implements HtmlFragmentParser {
  int parseCount = 0;

  @override
  html_dom.DocumentFragment parse(String html) {
    parseCount += 1;
    return html_parser.parseFragment(html);
  }
}

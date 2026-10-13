import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/domain/models/novel_reader_anchor_format.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_dom_source_text.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_flow_unit_extractor.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

void main() {
  const extractor = DefaultNovelReaderHtmlFlowUnitExtractor();

  test('projects decoded spaces, BR and ruby onto the exact semantic node', () {
    const html =
        '<p>A&nbsp;&nbsp;👩‍👩‍👧‍👦<span>e\u0301</span><br>中<ruby>漢<rt>かん</rt></ruby>末</p>';
    final semantic = const DiscuzNovelReaderDocumentParser().parse(
      episodeId: 'semantic',
      rawHtml: html,
      fallbackParagraphs: const <String>[],
    );
    final unit = extractor
        .extract(
          episodeId: 'semantic',
          renderDocument: _prepare(html),
          semanticDocument: semantic,
        )
        .single;
    final projection = unit.sourceAnchorProjection!;
    final source = NovelReaderDomSourceText.read(
      html_parser.parseFragment(unit.html),
    );
    expect(unit.startAnchor.nodeId, semantic.blocks.single.anchorId);
    expect(
      unit.startAnchor.formatVersion,
      NovelReaderAnchorFormat.semanticCodePoints,
    );
    expect(
      unit.endAnchor.textOffset,
      'A 👩‍👩‍👧‍👦e\u0301\n中漢かん末'.runes.length,
    );
    expect(projection.sourceRuneLength, source.runes.length);
    expect(
      projection
          .anchorAtSourceRune(
            source.substring(0, source.indexOf('中')).runes.length,
          )
          .textOffset,
      'A 👩‍👩‍👧‍👦e\u0301\n'.runes.length,
    );
    expect(
      unit.startAnchor.textIdentity,
      NovelReaderAnchorFormat.textIdentity('A 👩‍👩‍👧‍👦e\u0301\n中漢かん末'),
    );
  });

  test('uses the actual nonzero semantic substring origin', () {
    final semantic = const DiscuzNovelReaderDocumentParser().parse(
      episodeId: 'substring',
      rawHtml: '<p>前👩‍👩‍👧‍👦中尾后</p>',
      fallbackParagraphs: const <String>[],
    );
    final unit = extractor
        .extract(
          episodeId: 'substring',
          renderDocument: _prepare('<span>中尾</span>'),
          semanticDocument: semantic,
        )
        .single;
    expect(unit.startAnchor.nodeId, semantic.blocks.single.anchorId);
    expect(unit.startAnchor.textOffset, 8);
    expect(unit.endAnchor.textOffset, 10);
    expect(unit.sourceAnchorProjection!.anchorAtSourceRune(1).textOffset, 9);
  });

  test('unit identity uses DOM text while source boundaries retain BR', () {
    final first = extractor
        .extract(
          episodeId: 'text-axes',
          renderDocument: _prepare('<p>甲<br>乙</p>'),
        )
        .single;
    final second = extractor
        .extract(episodeId: 'text-axes', renderDocument: _prepare('<p>甲乙</p>'))
        .single;

    // These nodes have equal DOM text, but different slicing text and layouts.
    expect(first.unitId, second.unitId);
    expect(first.endAnchor.textOffset, 3);
    expect(second.endAnchor.textOffset, 2);
    expect(first.sourceAnchorProjection!.sourceRuneLength, 3);
    expect(second.sourceAnchorProjection!.sourceRuneLength, 2);
    expect(
      first.startAnchor.textIdentity,
      isNot(second.startAnchor.textIdentity),
    );
  });

  test(
    'a root link retains normalized semantic boundaries and source runes',
    () {
      final semantic = const DiscuzNovelReaderDocumentParser().parse(
        episodeId: 'link-projection',
        rawHtml: '<p>中 👩‍👩‍👧‍👦<br>末</p>',
        fallbackParagraphs: const <String>[],
      );
      final unit = extractor
          .extract(
            episodeId: 'link-projection',
            renderDocument: _prepare(
              '<a href="#target">  中&nbsp;&nbsp;👩‍👩‍👧‍👦<br>末 </a>',
            ),
            semanticDocument: semantic,
          )
          .single;

      expect(unit.breakability, NovelReaderFlowUnitBreakability.inlineText);
      expect(unit.startAnchor.nodeId, semantic.blocks.single.anchorId);
      expect(unit.endAnchor.textOffset, 11);
      expect(unit.sourceAnchorProjection!.sourceRuneLength, 15);
      expect(
        unit.sourceAnchorProjection!.semanticOffsetsBySourceRuneBoundary,
        <int>[0, 0, 0, 1, 2, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 11],
      );
    },
  );

  test('local summaries never reuse a previous semantic matching result', () {
    final rendered = _prepare('<p>正文</p>');
    final unique = const DiscuzNovelReaderDocumentParser().parse(
      episodeId: 'semantic-context',
      rawHtml: '<p>正文</p>',
      fallbackParagraphs: const <String>[],
    );
    final ambiguous = const DiscuzNovelReaderDocumentParser().parse(
      episodeId: 'semantic-context',
      rawHtml: '<p>正文</p><p>正文</p>',
      fallbackParagraphs: const <String>[],
    );
    final first = extractor
        .extract(
          episodeId: 'semantic-context',
          renderDocument: rendered,
          semanticDocument: unique,
        )
        .single;
    final second = extractor
        .extract(
          episodeId: 'semantic-context',
          renderDocument: rendered,
          semanticDocument: ambiguous,
        )
        .single;
    final third = extractor
        .extract(
          episodeId: 'semantic-context',
          renderDocument: rendered,
          semanticDocument: unique,
        )
        .single;

    expect(first.startAnchor.nodeId, unique.blocks.single.anchorId);
    expect(second.startAnchor.nodeId, startsWith('novel-html-'));
    expect(third.startAnchor.nodeId, first.startAnchor.nodeId);
    expect(third.startAnchor.textIdentity, first.startAnchor.textIdentity);
    expect(first.unitId, second.unitId);
  });

  test(
    'ambiguous, multi-node and converted text use an exact layout identity',
    () {
      for (final sample in <(String, String)>[
        ('<p>重复</p><p>重复</p>', '<p>重复</p>'),
        ('<p>重复</p><p>前重复后</p>', '<p>重复</p>'),
        (
          '<span>甲<strong>乙</strong>丙</span>',
          '<span>甲<strong>乙</strong>丙</span>',
        ),
        ('<p>國</p>', '<p>国</p>'),
      ]) {
        final semantic = const DiscuzNovelReaderDocumentParser().parse(
          episodeId: 'fallback',
          rawHtml: sample.$1,
          fallbackParagraphs: const <String>[],
        );
        final rendered = _prepare(sample.$2);
        final unit = extractor
            .extract(
              episodeId: 'fallback',
              renderDocument: rendered,
              semanticDocument: semantic,
            )
            .single;
        final source = NovelReaderDomSourceText.read(
          html_parser.parseFragment(unit.html),
        );
        expect(unit.startAnchor.nodeId, startsWith('novel-html-'));
        expect(
          unit.startAnchor.textIdentity,
          NovelReaderAnchorFormat.layoutTextIdentity(
            source,
            NovelReaderAnchorFormat.textIdentity(rendered.preparedHtml),
          ),
        );
        expect(unit.endAnchor.textOffset, source.runes.length);
      }
    },
  );

  test('extracts stable semantic units from the prepared HTML document', () {
    final document = _prepare(
      '<p id="first">第一<strong>段</strong>'
      '<a href="thread-101-1-1.html">链接</a></p>'
      '<blockquote>引用正文</blockquote>'
      '<hr>'
      '<table><tbody><tr><td>表格正文</td></tr></tbody></table>',
    );

    final units = extractor.extract(
      episodeId: 'episode-1',
      renderDocument: document,
    );

    expect(units, hasLength(4));
    expect(units.first.unitId, 'episode-1:novel-html-id-first-0');
    expect(units.first.breakability, NovelReaderFlowUnitBreakability.text);
    expect(units.first.html, contains('<strong>段</strong>'));
    expect(units.first.html, contains('thread-101-1-1.html'));
    expect(units.first.startAnchor.nodeId, units.first.endAnchor.nodeId);
    expect(units.first.startAnchor.textOffset, 0);
    expect(units.first.endAnchor.textOffset, '第一段链接'.runes.length);
    expect(units[1].breakability, NovelReaderFlowUnitBreakability.text);
    expect(units[2].breakability, NovelReaderFlowUnitBreakability.atomicWidget);
    expect(units[3].breakability, NovelReaderFlowUnitBreakability.atomicWidget);
    for (final unit in units) {
      expect(
        html_parser.parseFragment(unit.html).nodes,
        isNotEmpty,
        reason: unit.unitId,
      );
    }
  });

  test('layout-only anchors invalidate when the display context changes', () {
    final first = extractor.extract(
      episodeId: 'layout',
      renderDocument: _prepare('<p>重复</p><p>重复</p>'),
    );
    final changed = extractor.extract(
      episodeId: 'layout',
      renderDocument: _prepare('<p>插入</p><p>重复</p><p>重复</p>'),
    );
    expect(first.first.startAnchor.nodeId, changed[1].startAnchor.nodeId);
    expect(
      first.first.startAnchor.textIdentity,
      isNot(changed[1].startAnchor.textIdentity),
    );
  });

  test('keeps whole-chapter readable image indices after unit extraction', () {
    final document = _prepare(
      '<p>正文前'
      '<img src="data/attachment/forum/first.jpg">正文后</p>'
      '<img src="data/attachment/forum/second.jpg">'
      '<img src="static/image/smiley/default/smile.gif">',
    );

    final units = extractor.extract(
      episodeId: 'episode-images',
      renderDocument: document,
    );
    final extractedIndices = units
        .expand((unit) => unit.imageIndices)
        .toList(growable: false);

    expect(document.sequence.entries, hasLength(2));
    expect(document.sequence.entries.map((entry) => entry.index), <int>[0, 1]);
    expect(extractedIndices, <int>[0, 1]);
    expect(units.first.imageIndices, <int>[0]);
    expect(units[1].breakability, NovelReaderFlowUnitBreakability.blockImage);
    expect(units[1].imageIndices, <int>[1]);
    expect(units.last.imageIndices, isEmpty);
  });

  test('image presence remains independent of readable image membership', () {
    final document = _prepare(
      '<div><img src="static/image/smiley/default/smile.gif"></div>'
      '<a href="#image"><img src="data:image/png;base64,AA"></a>'
      '<img src="data/attachment/forum/first.jpg">'
      '<table><tbody><tr><td>'
      '<img src="data/attachment/forum/second.jpg">'
      '</td></tr></tbody></table>',
    );
    final units = extractor.extract(
      episodeId: 'image-membership',
      renderDocument: document,
    );

    expect(units, hasLength(4));
    expect(document.sequence.entries, hasLength(2));
    expect(units[0].breakability, NovelReaderFlowUnitBreakability.blockImage);
    expect(units[0].imageIndices, isEmpty);
    expect(units[1].breakability, NovelReaderFlowUnitBreakability.blockImage);
    expect(units[1].imageIndices, isEmpty);
    expect(units[2].breakability, NovelReaderFlowUnitBreakability.blockImage);
    expect(units[2].imageIndices, <int>[0]);
    expect(units[3].breakability, NovelReaderFlowUnitBreakability.atomicWidget);
    expect(units[3].imageIndices, <int>[1]);
    for (final unit in units) {
      expect(unit.sourceAnchorProjection!.sourceRuneLength, 0);
      expect(unit.endAnchor.textOffset, 0);
    }
  });

  test('readable indices stay valid, distinct, sorted and immutable', () {
    final document =
        _prepare(
          '<img src="data/attachment/forum/first.jpg">'
          '<img src="data/attachment/forum/second.jpg">',
        ).copyWith(
          preparedHtml:
              '<div id="images">'
              '<img data-y300-readable-image-index="1">'
              '<img data-y300-readable-image-index="1">'
              '<img data-y300-readable-image-index="0">'
              '<img data-y300-readable-image-index="-1">'
              '<img data-y300-readable-image-index="not-an-index">'
              '<img data-y300-readable-image-index="20">'
              '</div>',
        );
    final unit = extractor
        .extract(episodeId: 'indices', renderDocument: document)
        .single;

    expect(unit.breakability, NovelReaderFlowUnitBreakability.blockImage);
    expect(unit.imageIndices, <int>[0, 1]);
    expect(() => unit.imageIndices.add(0), throwsUnsupportedError);
  });

  test('duplicate blocks receive deterministic occurrence identities', () {
    final document = _prepare('<p>重复正文</p><p>重复正文</p>');

    final first = extractor.extract(
      episodeId: 'episode-duplicates',
      renderDocument: document,
    );
    final second = extractor.extract(
      episodeId: 'episode-duplicates',
      renderDocument: document,
    );

    expect(first.map((unit) => unit.unitId), second.map((unit) => unit.unitId));
    expect(first[0].unitId, endsWith('-0'));
    expect(first[1].unitId, endsWith('-1'));
    expect(first[0].unitId, isNot(first[1].unitId));
  });

  test('empty prepared HTML creates one deterministic empty unit', () {
    final document = _prepare('<p>   </p>');

    final units = extractor.extract(
      episodeId: 'episode-empty',
      renderDocument: document,
    );

    expect(units, hasLength(1));
    expect(units.single.unitId, 'episode-empty:empty');
    expect(units.single.html, isEmpty);
    expect(units.single.imageIndices, isEmpty);
  });

  test('non-rendered markup does not become a flow unit', () {
    final document = _prepare(
      '<p>正文</p><style>.showcollapse_content{display:none}</style>'
      '<script>fixtureCallback();</script><!-- fixture comment -->',
    );
    final units = extractor.extract(
      episodeId: 'episode-metadata',
      renderDocument: document,
    );

    expect(units, hasLength(1));
    expect(units.single.html, '<p>正文</p>');
    // Filtering belongs to the local layout projection, not stored HTML.
    expect(document.preparedHtml, contains('<style>'));
    expect(document.preparedHtml, contains('<script>'));
  });

  test('nested metadata does not affect visible offsets or identity', () {
    final withMetadata = _prepare(
      '<div>前文<style>.fixture{color:red}</style>'
      '<span><!-- fixture comment -->后文</span>'
      '<script>fixtureCallback();</script></div>',
    );
    final withoutMetadata = _prepare('<div>前文<span>后文</span></div>');
    final units = extractor.extract(
      episodeId: 'episode-metadata',
      renderDocument: withMetadata,
    );
    final expected = extractor.extract(
      episodeId: 'episode-metadata',
      renderDocument: withoutMetadata,
    );

    expect(units.single.html, expected.single.html);
    expect(units.single.unitId, expected.single.unitId);
    expect(units.single.startAnchor.nodeId, expected.single.startAnchor.nodeId);
    expect(units.single.startAnchor.textOffset, 0);
    expect(units.single.endAnchor.textOffset, '前文后文'.runes.length);
  });

  test('a metadata-only document uses the existing empty input', () {
    final units = extractor.extract(
      episodeId: 'episode-empty',
      renderDocument: _prepare(
        '<div><style>.fixture{color:red}</style>'
        '<script>fixtureCallback();</script><!-- fixture --></div>',
      ),
    );

    expect(units, hasLength(1));
    expect(units.single.unitId, 'episode-empty:empty');
    expect(units.single.html, isEmpty);
  });

  test('keeps visible escaped markup, spacing and non-text content', () {
    final units = extractor.extract(
      episodeId: 'episode-visible',
      renderDocument: _prepare(
        '<p>&lt;style&gt;示例&lt;/style&gt;</p><br><br>'
        '<style>.fixture{color:red}</style>'
        '<p><font color="#ff0000">后文</font></p><hr>'
        '<img src="data/attachment/forum/fixture.jpg">'
        '<div class="showcollapse_box">'
        '<div class="showcollapse_title">目录</div>'
        '<div class="showcollapse_content">折叠正文</div></div>',
      ),
    );

    expect(units, hasLength(7));
    expect(units.first.html, '<p>&lt;style&gt;示例&lt;/style&gt;</p>');
    expect(units[1].html, '<br>');
    expect(units[2].html, '<br>');
    expect(units[3].html, contains('color:'));
    expect(units[3].html, contains('后文'));
    expect(units[4].html, '<hr>');
    expect(units[5].imageIndices, <int>[0]);
    expect(units.last.html, contains('折叠正文'));
  });
}

ForumHtmlPreparedRenderDocument _prepare(String html) {
  return const DefaultForumHtmlRenderPreparer().prepare(
    html: html,
    preferences: ForumHtmlReaderPreferences.defaults(),
    theme: _theme,
    sourceId: 'flow-unit-test',
    threadId: '100',
    imageCacheOwnerId: '100',
  );
}

const _theme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.light,
  surface: Color(0xFFF4EAD7),
  foreground: Color(0xFF4C3A21),
  link: Color(0xFF6A55A3),
  quoteSurface: Color(0xFFE8D8B8),
  quoteForeground: Color(0xFF8B7355),
  codeSurface: Color(0xFFEFE0C4),
  codeForeground: Color(0xFF4C3A21),
);

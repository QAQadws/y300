import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_reader_anchor_format.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_slice.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_source_anchor_projection.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_complex_html_boundary_indexer.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

void main() {
  test('slices by graphemes while legacy fixture anchors use source runes', () {
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
    expect(slices.map((slice) => slice.endAnchor.textOffset), <int>[
      8,
      15,
      17,
      18,
    ]);
    expect(
      slices.every((slice) => slice.startAnchor.nodeId == 'node-1'),
      isTrue,
    );
  });

  test(
    'projects a substring and collapsed whitespace without cutting by anchors',
    () {
      const semanticText = '前文前文前A e\u0301B';
      final anchor = _anchor.copyWith(
        textOffset: 5,
        formatVersion: NovelReaderAnchorFormat.semanticCodePoints,
        textIdentity: NovelReaderAnchorFormat.textIdentity(semanticText),
      );
      final session = const DefaultNovelReaderComplexHtmlBoundaryIndexer()
          .prepare(
            html: '<p>A  <span>e\u0301</span>B</p>',
            startAnchor: anchor,
            sourceAnchorProjection: NovelReaderSourceAnchorProjection(
              baseAnchor: anchor,
              semanticOffsetsBySourceRuneBoundary: const [5, 6, 7, 7, 8, 9, 10],
            ),
          );
      final slices = _consecutiveSlices(session);

      expect(
        slices
            .map((slice) => html_parser.parseFragment(slice.html).text)
            .join(),
        'A  e\u0301B',
      );
      expect(slices.first.startAnchor.textOffset, 5);
      expect(slices.map((slice) => slice.endAnchor.textOffset), <int>[
        6,
        7,
        7,
        9,
        10,
      ]);
      expect(
        slices.every((slice) => slice.endAnchor.hasCanonicalTextOffset),
        isTrue,
      );
      for (var index = 1; index < slices.length; index += 1) {
        expect(
          slices[index].startAnchor.textOffset,
          slices[index - 1].endAnchor.textOffset,
        );
      }
    },
  );

  test('rejects an incomplete projection instead of clamping its anchors', () {
    expect(
      () => const DefaultNovelReaderComplexHtmlBoundaryIndexer().prepare(
        html: '<p>A<br>B</p>',
        startAnchor: _anchor,
        sourceAnchorProjection: NovelReaderSourceAnchorProjection(
          baseAnchor: _anchor,
          semanticOffsetsBySourceRuneBoundary: const [0, 1, 2],
        ),
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
    expect(smiley.domNodeCount, 2);
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

  test('standalone BR keeps zero semantic offsets in the Host projection', () {
    final spacerAnchor = _anchor.copyWith(
      formatVersion: NovelReaderAnchorFormat.semanticCodePoints,
      textIdentity: NovelReaderAnchorFormat.textIdentity(''),
    );
    final spacer = const DefaultNovelReaderComplexHtmlBoundaryIndexer()
        .prepare(
          html: '<br>',
          startAnchor: spacerAnchor,
          sourceAnchorProjection: NovelReaderSourceAnchorProjection(
            baseAnchor: spacerAnchor,
            semanticOffsetsBySourceRuneBoundary: const [0, 0],
          ),
        )
        .slice(startOffset: 0, endOffset: 1);
    expect(spacer.html, '<br>');
    expect(spacer.hasRenderableContent, isFalse);
    expect(spacer.domNodeCount, 1);
    expect(spacer.startAnchor.textOffset, 0);
    expect(spacer.endAnchor.textOffset, 0);
  });

  test('projects an existing core slice without parsing or cloning again', () {
    final codec = _CountingFragmentCodec();
    final anchor = _anchor.copyWith(
      textOffset: 5,
      pageIndex: 12,
      scrollOffset: 3.5,
      progressPercent: 0.4,
      isProgressPercentValid: false,
      formatVersion: NovelReaderAnchorFormat.semanticCodePoints,
      textIdentity: NovelReaderAnchorFormat.textIdentity('前文前文前A\nB'),
    );
    final session =
        DefaultNovelReaderComplexHtmlBoundaryIndexer(
          fragmentCodec: codec,
        ).prepare(
          html: '<p>A<br>B</p>',
          startAnchor: anchor,
          sourceAnchorProjection: NovelReaderSourceAnchorProjection(
            baseAnchor: anchor,
            semanticOffsetsBySourceRuneBoundary: const [5, 6, 7, 8],
          ),
        );
    final core = session.coreSession;
    expect(core.sourceRuneLength, 3);
    expect(core.boundaries.map((boundary) => boundary.sourceRuneOffset), [
      1,
      3,
    ]);
    expect(session.boundaries.map((boundary) => boundary.anchor.textOffset), [
      6,
      8,
    ]);
    final sourceSlice = core.slice(startOffset: 1, endOffset: 3);
    final projected = session.projectSlice(sourceSlice);
    expect(projected.html, same(sourceSlice.html));
    expect(projected.startOffset, sourceSlice.startOffset);
    expect(projected.endOffset, sourceSlice.endOffset);
    expect(
      [projected.startAnchor.textOffset, projected.endAnchor.textOffset],
      [6, 8],
    );
    for (final point in [projected.startAnchor, projected.endAnchor]) {
      expect(
        (
          point.episodeId,
          point.nodeId,
          point.formatVersion,
          point.textIdentity,
          point.pageIndex,
          point.scrollOffset,
          point.progressPercent,
          point.isProgressPercentValid,
        ),
        (
          anchor.episodeId,
          anchor.nodeId,
          anchor.formatVersion,
          anchor.textIdentity,
          anchor.pageIndex,
          anchor.scrollOffset,
          anchor.progressPercent,
          anchor.isProgressPercentValid,
        ),
      );
    }
    expect(projected.sourceRuneLength, 2);
    expect(projected.domNodeCount, sourceSlice.domNodeCount);
    expect(projected.hasRenderableContent, sourceSlice.hasRenderableContent);
    expect(codec.parseCount, 1);
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

import 'package:html/dom.dart' as html_dom;
import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_html_slice.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_source_anchor_projection.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_protected_inline_node_adapter.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

abstract interface class NovelReaderComplexHtmlBoundaryIndexer {
  NovelReaderComplexHtmlSliceSession prepare({
    required String html,
    required NovelReaderTextAnchor startAnchor,
    NovelReaderSourceAnchorProjection? sourceAnchorProjection,
  });
}

/// Projects the pure DOM source coordinates into this reader's canonical anchors.
final class DefaultNovelReaderComplexHtmlBoundaryIndexer
    implements NovelReaderComplexHtmlBoundaryIndexer {
  const DefaultNovelReaderComplexHtmlBoundaryIndexer({
    ForumHtmlFragmentCodec fragmentCodec =
        const HtmlPackageForumHtmlFragmentCodec(),
    this.protectedInlineNodeAdapter =
        const DefaultNovelReaderProtectedInlineNodeAdapter(),
  }) : _fragmentCodec = fragmentCodec;

  final ForumHtmlFragmentCodec _fragmentCodec;
  final NovelReaderProtectedInlineNodeAdapter protectedInlineNodeAdapter;

  @override
  NovelReaderComplexHtmlSliceSession prepare({
    required String html,
    required NovelReaderTextAnchor startAnchor,
    NovelReaderSourceAnchorProjection? sourceAnchorProjection,
  }) {
    final adapter = protectedInlineNodeAdapter;
    final core = DefaultHtmlComplexBoundaryIndexer(
      fragmentParser: _ForumFragmentParser(_fragmentCodec),
      protectedInlinePredicate: (element) => adapter.assess(element).isStable,
    ).prepare(html: html);
    if (sourceAnchorProjection != null &&
        sourceAnchorProjection.sourceRuneLength != core.sourceRuneLength) {
      throw ArgumentError('Source anchor projection does not cover the HTML.');
    }
    return _NovelReaderComplexHtmlSliceSession(
      coreSession: core,
      startAnchor: startAnchor,
      sourceAnchorProjection: sourceAnchorProjection,
    );
  }
}

final class _NovelReaderComplexHtmlSliceSession
    implements NovelReaderComplexHtmlSliceSession {
  _NovelReaderComplexHtmlSliceSession({
    required this.coreSession,
    required this.startAnchor,
    required this.sourceAnchorProjection,
  }) {
    boundaries = List<NovelReaderComplexHtmlBoundary>.unmodifiable(
      coreSession.boundaries.map(
        (boundary) => NovelReaderComplexHtmlBoundary(
          textOffset: boundary.textOffset,
          anchor: _anchorAtSourceRune(boundary.sourceRuneOffset),
          kind: boundary.kind,
          preference: boundary.preference,
        ),
      ),
    );
  }

  @override
  final HtmlComplexSliceSession coreSession;
  final NovelReaderTextAnchor startAnchor;
  final NovelReaderSourceAnchorProjection? sourceAnchorProjection;

  @override
  int get textLength => coreSession.textLength;

  @override
  late final List<NovelReaderComplexHtmlBoundary> boundaries;

  @override
  List<NovelReaderComplexHtmlProtectedRange> get protectedRanges =>
      coreSession.protectedRanges;

  @override
  bool isLegalBoundary(int textOffset) =>
      coreSession.isLegalBoundary(textOffset);

  @override
  int firstBoundaryIndexAfter(int startOffset) =>
      coreSession.firstBoundaryIndexAfter(startOffset);

  @override
  NovelReaderComplexHtmlSlice slice({
    required int startOffset,
    required int endOffset,
  }) => projectSlice(
    coreSession.slice(startOffset: startOffset, endOffset: endOffset),
  );

  @override
  NovelReaderComplexHtmlSlice projectSlice(HtmlComplexSlice slice) =>
      NovelReaderComplexHtmlSlice(
        html: slice.html,
        startAnchor: _anchorAtSourceRune(slice.sourceRuneStart),
        endAnchor: _anchorAtSourceRune(slice.sourceRuneEnd),
        startOffset: slice.startOffset,
        endOffset: slice.endOffset,
        hasRenderableContent: slice.hasRenderableContent,
        domNodeCount: slice.domNodeCount,
        sourceRuneLength: slice.sourceRuneLength,
      );

  NovelReaderTextAnchor _anchorAtSourceRune(int sourceRune) =>
      // Null projections retain legacy fixtures' local source-rune coordinates.
      sourceAnchorProjection?.anchorAtSourceRune(sourceRune) ??
      startAnchor.copyWith(textOffset: startAnchor.textOffset + sourceRune);
}

final class _ForumFragmentParser implements HtmlFragmentParser {
  const _ForumFragmentParser(this.codec);
  final ForumHtmlFragmentCodec codec;

  @override
  html_dom.DocumentFragment parse(String html) => codec.parse(html);
}

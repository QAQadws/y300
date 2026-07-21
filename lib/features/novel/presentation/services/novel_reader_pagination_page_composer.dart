import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_complex_block_pagination.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_page_fragment.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_text_pagination.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';

final class NovelReaderPaginationPageComposer {
  NovelReaderPaginationPageComposer({
    required this.pageHeight,
    required this.lineHeight,
    this.maxPages = 5000,
  }) {
    if (!pageHeight.isFinite ||
        pageHeight <= 0 ||
        !lineHeight.isFinite ||
        lineHeight <= 0 ||
        maxPages <= 0) {
      throw ArgumentError('Composer bounds and page budget must be positive.');
    }
  }

  final double pageHeight;
  final double lineHeight;
  final int maxPages;
  final List<NovelReaderPageFragment> _pages = <NovelReaderPageFragment>[];
  _ComposedPageBuffer? _buffer;
  StringBuffer? _pendingStructuralHtml;
  NovelReaderTextAnchor? _pendingStructuralStart;
  NovelReaderTextAnchor? _pendingStructuralEnd;
  int _pendingStructuralBreakCount = 0;
  bool? _pendingBreakFollowsInlineFlow;
  bool _bufferEndsInlineFlow = false;

  bool get hasBufferedContent => _buffer != null;
  double get remainingHeight =>
      (pageHeight - (_buffer?.usedHeight ?? 0)).clamp(0, pageHeight);
  String get bufferedHtml => _buffer?.html ?? '';
  List<NovelReaderPageFragment> get pages =>
      List<NovelReaderPageFragment>.unmodifiable(_pages);

  bool canAppendComplexBlock(NovelReaderComplexBlockPage block) {
    return hasBufferedContent &&
        !block.metrics.isOversized &&
        block.metrics.height <= remainingHeight;
  }

  void appendTextChunk(
    NovelReaderTextPageChunk chunk, {
    bool contributesRenderableContent = true,
    bool participatesInInlineFlow = false,
  }) {
    if (chunk.html.trim().isEmpty && chunk.sourceEnd <= chunk.sourceStart) {
      return;
    }
    if (chunk.isStructuralBreak) {
      _rememberStructuralBreak(chunk);
      return;
    }
    if (chunk.isOversized) {
      flush(gapReason: NovelReaderPageGapReason.algorithmBoundary);
      final buffer = _ComposedPageBuffer()
        ..append(
          html: chunk.html,
          start: chunk.startAnchor,
          end: chunk.endAnchor,
          usedHeight: chunk.usedHeight,
          overflowState: NovelReaderPageOverflowState.minimumTextFragment,
          contributesRenderableContent: contributesRenderableContent,
        );
      _emit(
        buffer,
        gapReason: NovelReaderPageGapReason.oversizedWidget,
        requiresInnerScroll: true,
      );
      _bufferEndsInlineFlow = false;
      return;
    }
    final pendingBreakHeight = _pendingStructuralBreakHeight(
      nextParticipatesInInlineFlow: participatesInInlineFlow,
    );
    if (hasBufferedContent &&
        chunk.usedHeight + pendingBreakHeight > remainingHeight) {
      flush(gapReason: NovelReaderPageGapReason.algorithmBoundary);
    }
    _appendPendingStructuralBreaks(
      nextParticipatesInInlineFlow: participatesInInlineFlow,
    );
    final buffer = _buffer ??= _ComposedPageBuffer();
    buffer.append(
      html: chunk.html,
      start: chunk.startAnchor,
      end: chunk.endAnchor,
      usedHeight: chunk.usedHeight,
      contributesRenderableContent: contributesRenderableContent,
    );
    _bufferEndsInlineFlow = participatesInInlineFlow;
    if (remainingHeight <= 0.01) {
      flush(gapReason: NovelReaderPageGapReason.algorithmBoundary);
    }
  }

  void appendComplexBlock(
    NovelReaderClassifiedPaginationAtom atom,
    NovelReaderComplexBlockPage block, {
    bool combineWithBufferedContent = false,
    bool keepPageOpen = false,
  }) {
    _discardPendingStructuralBreaks();
    if (!combineWithBufferedContent) {
      flush(gapReason: _gapReasonFor(atom.route));
    } else if (!canAppendComplexBlock(block)) {
      throw StateError('Complex block does not fit the buffered page.');
    }
    final buffer = _buffer ?? _ComposedPageBuffer();
    _buffer = null;
    buffer.append(
      html: block.html,
      start: block.startAnchor,
      end: block.endAnchor,
      usedHeight: block.metrics.height,
      overflowState: block.metrics.requiresInnerScroll
          ? NovelReaderPageOverflowState.atomicWidget
          : NovelReaderPageOverflowState.none,
      imageIndices: atom.atom.imageIndices,
    );
    _bufferEndsInlineFlow = false;
    if (keepPageOpen &&
        !block.metrics.isOversized &&
        !block.metrics.requiresInnerScroll) {
      _buffer = buffer;
      return;
    }
    _emit(
      buffer,
      gapReason: block.metrics.isOversized
          ? NovelReaderPageGapReason.oversizedWidget
          : _gapReasonFor(atom.route),
      requiresInnerScroll: block.metrics.requiresInnerScroll,
    );
  }

  void appendIsolatedImage({
    required NovelReaderClassifiedPaginationAtom atom,
    required double measuredHeight,
    bool requiresInnerScroll = false,
  }) {
    flush(gapReason: NovelReaderPageGapReason.isolatedImage);
    final oversized = measuredHeight > pageHeight;
    final buffer = _ComposedPageBuffer()
      ..append(
        html: atom.atom.html,
        start: atom.atom.startAnchor,
        end: atom.atom.endAnchor,
        usedHeight: measuredHeight,
        overflowState: oversized
            ? NovelReaderPageOverflowState.atomicWidget
            : NovelReaderPageOverflowState.none,
        imageIndices: atom.atom.imageIndices,
        containsIsolatedImage: true,
      );
    _emit(
      buffer,
      gapReason: oversized
          ? NovelReaderPageGapReason.oversizedWidget
          : NovelReaderPageGapReason.isolatedImage,
      requiresInnerScroll: requiresInnerScroll || oversized,
    );
  }

  void flush({required NovelReaderPageGapReason gapReason}) {
    _discardPendingStructuralBreaks();
    final buffer = _buffer;
    _buffer = null;
    _bufferEndsInlineFlow = false;
    if (buffer == null || !buffer.hasRenderableContent) {
      return;
    }
    _emit(buffer, gapReason: gapReason);
  }

  List<NovelReaderPageFragment> finish() {
    flush(gapReason: NovelReaderPageGapReason.naturalEnd);
    return pages;
  }

  void _emit(
    _ComposedPageBuffer buffer, {
    required NovelReaderPageGapReason gapReason,
    bool requiresInnerScroll = false,
  }) {
    if (!buffer.hasRenderableContent) {
      return;
    }
    if (_pages.length >= maxPages) {
      throw const NovelReaderPaginationException(
        code: 'pageLimitExceeded',
        message: 'Pagination page budget was exceeded.',
      );
    }
    _pages.add(
      NovelReaderPageFragment(
        index: _pages.length,
        html: buffer.html,
        startAnchor: buffer.startAnchor!,
        endAnchor: buffer.endAnchor!,
        imageIndices: buffer.imageIndices,
        anchorRanges: buffer.anchorRanges,
        overflowState: buffer.overflowState,
        requiresInnerScroll:
            requiresInnerScroll ||
            buffer.overflowState != NovelReaderPageOverflowState.none,
        usedHeight: buffer.usedHeight,
        availableHeight: pageHeight,
        gapReason: gapReason,
        containsIsolatedImage: buffer.containsIsolatedImage,
      ),
    );
  }

  NovelReaderPageGapReason _gapReasonFor(NovelReaderPaginationRoute route) {
    return switch (route) {
      NovelReaderPaginationRoute.isolatedImage =>
        NovelReaderPageGapReason.isolatedImage,
      NovelReaderPaginationRoute.safeText =>
        NovelReaderPageGapReason.algorithmBoundary,
      _ => NovelReaderPageGapReason.atomicWidget,
    };
  }

  double _pendingStructuralBreakHeight({
    required bool nextParticipatesInInlineFlow,
  }) {
    final sharesInlineParagraph =
        _pendingBreakFollowsInlineFlow == true && nextParticipatesInInlineFlow;
    final includedSeparatorCount = sharesInlineParagraph ? 1 : 0;
    if (_pendingStructuralBreakCount <= includedSeparatorCount) {
      return 0;
    }
    return (_pendingStructuralBreakCount - includedSeparatorCount) * lineHeight;
  }

  void _rememberStructuralBreak(NovelReaderTextPageChunk chunk) {
    // Leading breaks and breaks after an already full page are layout noise;
    // the page boundary itself already separates the following content.
    if (!hasBufferedContent || !_buffer!.hasRenderableContent) {
      return;
    }
    final html = _pendingStructuralHtml ??= StringBuffer();
    html.write(chunk.html);
    _pendingBreakFollowsInlineFlow ??= _bufferEndsInlineFlow;
    _pendingStructuralStart ??= chunk.startAnchor;
    _pendingStructuralEnd = chunk.endAnchor;
    _pendingStructuralBreakCount += chunk.structuralBreakCount;
  }

  void _appendPendingStructuralBreaks({
    required bool nextParticipatesInInlineFlow,
  }) {
    if (_pendingStructuralBreakCount == 0) {
      return;
    }
    final buffer = _buffer;
    final start = _pendingStructuralStart;
    final end = _pendingStructuralEnd;
    if (buffer == null || start == null || end == null) {
      _discardPendingStructuralBreaks();
      return;
    }
    buffer.append(
      html: _pendingStructuralHtml!.toString(),
      start: start,
      end: end,
      usedHeight: _pendingStructuralBreakHeight(
        nextParticipatesInInlineFlow: nextParticipatesInInlineFlow,
      ),
      contributesRenderableContent: false,
    );
    _discardPendingStructuralBreaks();
  }

  void _discardPendingStructuralBreaks() {
    _pendingStructuralHtml = null;
    _pendingStructuralStart = null;
    _pendingStructuralEnd = null;
    _pendingStructuralBreakCount = 0;
    _pendingBreakFollowsInlineFlow = null;
  }
}

final class _ComposedPageBuffer {
  final StringBuffer _html = StringBuffer();
  final Set<int> _imageIndices = <int>{};
  final List<NovelReaderPageAnchorRange> _anchorRanges =
      <NovelReaderPageAnchorRange>[];
  NovelReaderTextAnchor? startAnchor;
  NovelReaderTextAnchor? endAnchor;
  double usedHeight = 0;
  NovelReaderPageOverflowState overflowState =
      NovelReaderPageOverflowState.none;
  bool containsIsolatedImage = false;
  bool hasRenderableContent = false;

  String get html => _html.toString();
  List<int> get imageIndices {
    final values = _imageIndices.toList()..sort();
    return List<int>.unmodifiable(values);
  }

  List<NovelReaderPageAnchorRange> get anchorRanges =>
      List<NovelReaderPageAnchorRange>.unmodifiable(_anchorRanges);

  void append({
    required String html,
    required NovelReaderTextAnchor start,
    required NovelReaderTextAnchor end,
    required double usedHeight,
    NovelReaderPageOverflowState overflowState =
        NovelReaderPageOverflowState.none,
    Iterable<int> imageIndices = const <int>[],
    bool containsIsolatedImage = false,
    bool contributesRenderableContent = true,
  }) {
    startAnchor ??= start;
    endAnchor = end;
    _html.write(html);
    _anchorRanges.add(NovelReaderPageAnchorRange(start: start, end: end));
    _imageIndices.addAll(imageIndices);
    this.usedHeight += usedHeight;
    if (overflowState != NovelReaderPageOverflowState.none) {
      this.overflowState = overflowState;
    }
    this.containsIsolatedImage =
        this.containsIsolatedImage || containsIsolatedImage;
    hasRenderableContent = hasRenderableContent || contributesRenderableContent;
  }
}

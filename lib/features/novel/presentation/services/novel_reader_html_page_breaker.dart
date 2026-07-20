import 'dart:convert';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_page_fragment.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_atom_extractor.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_prepared_render_document.dart';

abstract interface class NovelReaderPageBreaker {
  Future<NovelReaderPaginationPlan> paginate(
    NovelReaderPreparedChapter chapter,
    NovelReaderPaginationKey key,
  );
}

/// Builds pages from Phase 1 flow units and validates candidate heights using
/// an injected presentation adapter. It has no Widget or progress state.
final class NovelReaderHtmlPageBreaker implements NovelReaderPageBreaker {
  NovelReaderHtmlPageBreaker({
    required NovelReaderPaginationMeasureAdapter measureAdapter,
    this.atomExtractor = const NovelReaderPaginationAtomExtractor(),
    NovelReaderPaginationMeasureSessionFactory? measureSessionFactory,
    this.measureCacheCapacity = 512,
    this.maxMeasurements = 4096,
    this.maxPages = 5000,
    this.maxSplitSearchIterations = 12,
    this.cooperativeYieldInterval = 32,
  }) : _measureSessionFactory =
           measureSessionFactory ??
           (measureAdapter is NovelReaderPaginationMeasureSessionFactory
               ? measureAdapter as NovelReaderPaginationMeasureSessionFactory
               : NovelReaderAdapterMeasureSessionFactory(measureAdapter));

  final NovelReaderPaginationMeasureSessionFactory _measureSessionFactory;
  final int measureCacheCapacity;
  final NovelReaderPaginationAtomExtractor atomExtractor;
  final int maxMeasurements;
  final int maxPages;
  final int maxSplitSearchIterations;
  final int cooperativeYieldInterval;

  late NovelReaderPreparedChapter _chapter;
  late NovelReaderPaginationKey _key;
  int _measurementCount = 0;
  int _measurementCacheHitCount = 0;
  Duration _measurementDuration = Duration.zero;
  List<NovelReaderPaginationMeasurementSample> _measurementSamples =
      <NovelReaderPaginationMeasurementSample>[];
  _PageBuffer? _buffer;
  List<NovelReaderPageFragment> _pages = <NovelReaderPageFragment>[];
  late NovelReaderPaginationMeasureSession _measureSession;

  @override
  Future<NovelReaderPaginationPlan> paginate(
    NovelReaderPreparedChapter chapter,
    NovelReaderPaginationKey key,
  ) async {
    _validateInput(chapter, key);
    _chapter = chapter;
    _key = key;
    _measurementCount = 0;
    _measurementCacheHitCount = 0;
    _measurementDuration = Duration.zero;
    _measurementSamples = <NovelReaderPaginationMeasurementSample>[];
    _buffer = null;
    _pages = <NovelReaderPageFragment>[];
    final atoms = atomExtractor.extract(chapter);
    final atomKindCounts = <NovelReaderPaginationAtomKind, int>{};
    final session = NovelReaderCachingPaginationMeasureSession(
      delegate: _measureSessionFactory.create(chapter: chapter, key: key),
      cache: NovelReaderPaginationMeasureCache(capacity: measureCacheCapacity),
    );
    _measureSession = session;

    try {
      for (final atom in atoms) {
        atomKindCounts.update(
          atom.kind,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
        await _appendAtom(atom);
      }
      _flushBuffer(gapReason: NovelReaderPageGapReason.naturalEnd);
      return NovelReaderPaginationPlan(
        key: key,
        episodeId: chapter.episodeId,
        pages: _pages,
        atomCount: atoms.length,
        measurementCount: _measurementCount,
        measurementCacheHitCount: _measurementCacheHitCount,
        measurementDuration: _measurementDuration,
        atomKindCounts: atomKindCounts,
        measurementSamples: _measurementSamples,
      );
    } finally {
      await session.dispose();
    }
  }

  void _validateInput(
    NovelReaderPreparedChapter chapter,
    NovelReaderPaginationKey key,
  ) {
    if (chapter.episodeId != key.episodeId) {
      throw const NovelReaderPaginationException(
        code: 'episodeMismatch',
        message:
            'Prepared chapter and pagination key refer to different episodes.',
      );
    }
    if (key.viewportWidthPx <= 0 || key.viewportHeightPx <= 0) {
      throw const NovelReaderPaginationException(
        code: 'invalidViewport',
        message: 'Pagination requires a positive viewport width and height.',
      );
    }
    if (maxMeasurements <= 0 ||
        measureCacheCapacity <= 0 ||
        maxPages <= 0 ||
        maxSplitSearchIterations <= 0) {
      throw const NovelReaderPaginationException(
        code: 'invalidBudget',
        message: 'Pagination budgets must be positive.',
      );
    }
    if (cooperativeYieldInterval <= 0) {
      throw const NovelReaderPaginationException(
        code: 'invalidBudget',
        message: 'Pagination cooperative yield interval must be positive.',
      );
    }
  }

  Future<void> _appendAtom(NovelReaderPaginationAtom atom) async {
    if (atom.isIsolatedImage) {
      await _appendIsolatedImage(atom);
      return;
    }
    final textLength = atom.textLength;
    final isBreakable =
        atom.breakability == NovelReaderFlowUnitBreakability.text ||
        atom.breakability == NovelReaderFlowUnitBreakability.inlineText;
    final whole = _pieceFor(atom, 0, textLength, atom.html);

    final wholeMeasurement = await _measure(whole);
    if (_fitsHeight(wholeMeasurement.height)) {
      _appendPiece(whole, measuredHeight: wholeMeasurement.height);
      return;
    }
    var acceptedMeasurement = wholeMeasurement;
    if (_buffer != null) {
      _flushBuffer(gapReason: _gapReasonFor(atom));
      final retryMeasurement = await _measure(whole);
      acceptedMeasurement = retryMeasurement;
      if (_fitsHeight(retryMeasurement.height)) {
        _appendPiece(whole, measuredHeight: retryMeasurement.height);
        return;
      }
    }
    if (!isBreakable || textLength == 0) {
      _appendOverflow(
        whole,
        NovelReaderPageOverflowState.atomicWidget,
        measuredHeight: acceptedMeasurement.height,
      );
      _flushBuffer(
        gapReason: acceptedMeasurement.height > _key.viewportHeightPx
            ? NovelReaderPageGapReason.oversizedWidget
            : NovelReaderPageGapReason.atomicWidget,
      );
      return;
    }
    await _appendBreakableAtom(atom, textLength);
  }

  Future<void> _appendBreakableAtom(
    NovelReaderPaginationAtom atom,
    int textLength,
  ) async {
    var offset = 0;
    while (offset < textLength) {
      final result = await _largestFittingEnd(atom, offset, textLength);
      if (result.end > offset) {
        _appendPiece(
          _pieceFor(
            atom,
            offset,
            result.end,
            _sliceHtml(atom.html, offset, result.end),
          ),
          measuredHeight: result.height,
        );
        offset = result.end;
        continue;
      }
      if (_buffer != null) {
        _flushBuffer(gapReason: NovelReaderPageGapReason.algorithmBoundary);
        continue;
      }
      final remainder = _pieceFor(
        atom,
        offset,
        textLength,
        _sliceHtml(atom.html, offset, textLength),
      );
      final remainderMeasurement = await _measure(remainder);
      _appendOverflow(
        remainder,
        NovelReaderPageOverflowState.minimumTextFragment,
        measuredHeight: remainderMeasurement.height,
      );
      offset = textLength;
      _flushBuffer(gapReason: NovelReaderPageGapReason.algorithmBoundary);
    }
  }

  Future<_FitResult> _largestFittingEnd(
    NovelReaderPaginationAtom atom,
    int start,
    int end,
  ) async {
    var low = start + 1;
    var high = end;
    var best = start;
    var bestHeight = 0.0;
    var iterations = 0;
    while (low <= high && iterations < maxSplitSearchIterations) {
      iterations += 1;
      final candidateEnd = (low + high) ~/ 2;
      final piece = _pieceFor(
        atom,
        start,
        candidateEnd,
        _sliceHtml(atom.html, start, candidateEnd),
      );
      final measurement = await _measure(piece);
      if (_fitsHeight(measurement.height)) {
        best = candidateEnd;
        bestHeight = measurement.height;
        low = candidateEnd + 1;
      } else {
        high = candidateEnd - 1;
      }
    }
    return _FitResult(end: best, height: bestHeight);
  }

  Future<NovelReaderPaginationMeasureResult> _measure(_PagePiece piece) async {
    _measurementCount += 1;
    if (_measurementCount > maxMeasurements) {
      throw const NovelReaderPaginationException(
        code: 'candidateLimitExceeded',
        message: 'Pagination candidate measurement budget was exceeded.',
      );
    }
    if (_measurementCount % cooperativeYieldInterval == 0) {
      // Keep large chapters responsive when the injected measurement adapter
      // completes synchronously in tests or on a cached renderer path.
      await Future<void>.delayed(Duration.zero);
    }
    final candidate = '${_buffer?.html ?? ''}${piece.html}';
    final stopwatch = Stopwatch()..start();
    final result = await _measureSession.measure(
      NovelReaderPaginationMeasureRequest(
        html: candidate,
        chapter: _chapter,
        key: _key,
        atomId: piece.atomId,
        startOffset: piece.startOffset,
        endOffset: piece.endOffset,
      ),
    );
    stopwatch.stop();
    _measurementDuration += stopwatch.elapsed;
    if (result.fromCache) {
      _measurementCacheHitCount += 1;
    }
    if (_measurementSamples.length < 64) {
      _measurementSamples.add(
        NovelReaderPaginationMeasurementSample(
          atomId: piece.atomId,
          atomKind: piece.atomKind,
          height: result.height,
          duration: stopwatch.elapsed,
          fromCache: result.fromCache,
        ),
      );
    }
    if (!result.height.isFinite || result.height < 0) {
      throw const NovelReaderPaginationException(
        code: 'invalidMeasurement',
        message: 'HTML renderer returned an invalid pagination height.',
      );
    }
    return result;
  }

  bool _fitsHeight(double height) => height <= _key.viewportHeightPx;

  NovelReaderPageGapReason _gapReasonFor(NovelReaderPaginationAtom atom) {
    if (atom.isIsolatedImage) {
      return NovelReaderPageGapReason.isolatedImage;
    }
    if (atom.kind == NovelReaderPaginationAtomKind.atomicWidget) {
      return NovelReaderPageGapReason.atomicWidget;
    }
    return NovelReaderPageGapReason.algorithmBoundary;
  }

  Future<void> _appendIsolatedImage(NovelReaderPaginationAtom atom) async {
    _flushBuffer(gapReason: NovelReaderPageGapReason.isolatedImage);
    final piece = _pieceFor(atom, 0, atom.textLength, atom.html);
    final measurement = await _measure(piece);
    if (_pages.length >= maxPages) {
      throw const NovelReaderPaginationException(
        code: 'pageLimitExceeded',
        message: 'Pagination page budget was exceeded.',
      );
    }
    final overflow = !_fitsHeight(measurement.height);
    _pages.add(
      NovelReaderPageFragment(
        index: _pages.length,
        html: piece.html,
        startAnchor: piece.startAnchor,
        endAnchor: piece.endAnchor,
        imageIndices: piece.imageIndices,
        anchorRanges: <NovelReaderPageAnchorRange>[
          NovelReaderPageAnchorRange(
            start: piece.startAnchor,
            end: piece.endAnchor,
          ),
        ],
        overflowState: overflow
            ? NovelReaderPageOverflowState.atomicWidget
            : NovelReaderPageOverflowState.none,
        requiresInnerScroll: overflow,
        usedHeight: measurement.height,
        availableHeight: _key.viewportHeightPx.toDouble(),
        gapReason: overflow
            ? NovelReaderPageGapReason.oversizedWidget
            : NovelReaderPageGapReason.isolatedImage,
        containsIsolatedImage: true,
      ),
    );
  }

  _PagePiece _pieceFor(
    NovelReaderPaginationAtom atom,
    int start,
    int end,
    String html,
  ) {
    final baseOffset = atom.startAnchor.textOffset;
    return _PagePiece(
      atomId: atom.atomId,
      atomKind: atom.kind,
      html: html,
      startOffset: start,
      endOffset: end,
      startAnchor: atom.startAnchor.copyWith(
        textOffset: baseOffset + start,
        pageIndex: 0,
        scrollOffset: 0,
        progressPercent: 0,
      ),
      endAnchor: atom.endAnchor.copyWith(
        textOffset: baseOffset + end,
        pageIndex: 0,
        scrollOffset: 0,
        progressPercent: 0,
      ),
      imageIndices: atom.imageIndices.isEmpty
          ? _imageIndices(html)
          : atom.imageIndices,
    );
  }

  void _appendPiece(_PagePiece piece, {required double measuredHeight}) {
    final buffer = _buffer ??= _PageBuffer();
    buffer.append(piece, measuredHeight: measuredHeight);
  }

  void _appendOverflow(
    _PagePiece piece,
    NovelReaderPageOverflowState state, {
    required double measuredHeight,
  }) {
    final buffer = _buffer ??= _PageBuffer();
    buffer.append(
      _PagePiece(
        atomId: piece.atomId,
        atomKind: piece.atomKind,
        html: piece.html,
        startOffset: piece.startOffset,
        endOffset: piece.endOffset,
        startAnchor: piece.startAnchor,
        endAnchor: piece.endAnchor,
        imageIndices: piece.imageIndices,
        overflowState: state,
      ),
      measuredHeight: measuredHeight,
    );
  }

  void _flushBuffer({
    NovelReaderPageGapReason gapReason = NovelReaderPageGapReason.none,
  }) {
    final buffer = _buffer;
    if (buffer == null || buffer.html.trim().isEmpty) {
      _buffer = null;
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
            buffer.overflowState != NovelReaderPageOverflowState.none,
        usedHeight: buffer.usedHeight,
        availableHeight: _key.viewportHeightPx.toDouble(),
        gapReason: gapReason,
        containsIsolatedImage: buffer.containsIsolatedImage,
      ),
    );
    _buffer = null;
  }

  List<int> _imageIndices(String html) {
    final fragment = html_parser.parseFragment(html);
    final images = <html_dom.Element>[];
    for (final node in fragment.nodes) {
      if (node is html_dom.Element && node.localName == 'img') {
        images.add(node);
      }
      if (node is html_dom.Element) {
        images.addAll(node.querySelectorAll('img'));
      }
    }
    final indices = <int>{};
    for (final image in images) {
      final index = int.tryParse(
        image.attributes[forumHtmlReadableImageIndexAttribute] ?? '',
      );
      if (index != null &&
          _chapter.renderDocument.sequence.entryAt(index) != null) {
        indices.add(index);
      }
    }
    final result = indices.toList()..sort();
    return List<int>.unmodifiable(result);
  }

  String _sliceHtml(String html, int start, int end) {
    final fragment = html_parser.parseFragment(html);
    final cursor = _TextCursor();
    final output = <html_dom.Node>[];
    for (final node in fragment.nodes) {
      final sliced = _sliceNode(node, start, end, cursor);
      if (sliced != null) {
        output.add(sliced);
      }
    }
    return output.map(_serializeNode).join();
  }

  html_dom.Node? _sliceNode(
    html_dom.Node node,
    int start,
    int end,
    _TextCursor cursor,
  ) {
    if (node is html_dom.Text) {
      final runes = node.data.runes.toList(growable: false);
      final nodeStart = cursor.value;
      cursor.value += runes.length;
      final from = (start - nodeStart).clamp(0, runes.length).toInt();
      final to = (end - nodeStart).clamp(0, runes.length).toInt();
      if (from >= to) {
        return null;
      }
      return html_dom.Text(String.fromCharCodes(runes.sublist(from, to)));
    }
    if (node is! html_dom.Element) {
      return null;
    }

    final clone = node.clone(false);
    for (final child in node.nodes) {
      final childLength = _textLengthOfNode(child);
      if (childLength == 0) {
        if (cursor.value >= start && cursor.value < end) {
          clone.append(child.clone(true));
        }
        continue;
      }
      final childStart = cursor.value;
      final childEnd = childStart + childLength;
      if (childEnd <= start || childStart >= end) {
        cursor.value = childEnd;
        continue;
      }
      final sliced = _sliceNode(child, start, end, cursor);
      if (sliced != null) {
        clone.append(sliced);
      }
    }
    return clone.nodes.isEmpty ? null : clone;
  }

  int _textLengthOfNode(html_dom.Node node) {
    if (node is html_dom.Text) {
      return node.data.runes.length;
    }
    return (node.text ?? '').runes.length;
  }

  String _serializeNode(html_dom.Node node) {
    if (node is html_dom.Element) {
      return node.outerHtml;
    }
    if (node is html_dom.Text) {
      return const HtmlEscape().convert(node.data);
    }
    return node.toString();
  }
}

class _TextCursor {
  int value = 0;
}

class _FitResult {
  const _FitResult({required this.end, required this.height});

  final int end;
  final double height;
}

class _PagePiece {
  const _PagePiece({
    required this.atomId,
    required this.atomKind,
    required this.html,
    required this.startOffset,
    required this.endOffset,
    required this.startAnchor,
    required this.endAnchor,
    required this.imageIndices,
    this.overflowState = NovelReaderPageOverflowState.none,
  });

  final String atomId;
  final NovelReaderPaginationAtomKind atomKind;
  final String html;
  final int startOffset;
  final int endOffset;
  final NovelReaderTextAnchor startAnchor;
  final NovelReaderTextAnchor endAnchor;
  final List<int> imageIndices;
  final NovelReaderPageOverflowState overflowState;
}

class _PageBuffer {
  final StringBuffer _html = StringBuffer();
  final Set<int> _imageIndices = <int>{};
  final List<NovelReaderPageAnchorRange> _anchorRanges =
      <NovelReaderPageAnchorRange>[];
  NovelReaderTextAnchor? startAnchor;
  NovelReaderTextAnchor? endAnchor;
  NovelReaderPageOverflowState overflowState =
      NovelReaderPageOverflowState.none;
  double usedHeight = 0;
  bool containsIsolatedImage = false;

  String get html => _html.toString();

  List<int> get imageIndices {
    final result = _imageIndices.toList()..sort();
    return List<int>.unmodifiable(result);
  }

  List<NovelReaderPageAnchorRange> get anchorRanges =>
      List<NovelReaderPageAnchorRange>.unmodifiable(_anchorRanges);

  void append(_PagePiece piece, {required double measuredHeight}) {
    startAnchor ??= piece.startAnchor;
    endAnchor = piece.endAnchor;
    _anchorRanges.add(
      NovelReaderPageAnchorRange(
        start: piece.startAnchor,
        end: piece.endAnchor,
      ),
    );
    _html.write(piece.html);
    _imageIndices.addAll(piece.imageIndices);
    usedHeight = measuredHeight;
    if (piece.overflowState != NovelReaderPageOverflowState.none) {
      overflowState = piece.overflowState;
    }
  }
}

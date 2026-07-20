import 'dart:convert';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_page_fragment.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';
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
    this.maxMeasurements = 512,
    this.maxPages = 5000,
    this.maxSplitSearchIterations = 12,
  }) : _measureAdapter = measureAdapter;

  final NovelReaderPaginationMeasureAdapter _measureAdapter;
  final int maxMeasurements;
  final int maxPages;
  final int maxSplitSearchIterations;

  late NovelReaderPreparedChapter _chapter;
  late NovelReaderPaginationKey _key;
  int _measurementCount = 0;
  _PageBuffer? _buffer;
  List<NovelReaderPageFragment> _pages = <NovelReaderPageFragment>[];

  @override
  Future<NovelReaderPaginationPlan> paginate(
    NovelReaderPreparedChapter chapter,
    NovelReaderPaginationKey key,
  ) async {
    _validateInput(chapter, key);
    _chapter = chapter;
    _key = key;
    _measurementCount = 0;
    _buffer = null;
    _pages = <NovelReaderPageFragment>[];

    for (final unit in chapter.flowUnits) {
      if (unit.html.trim().isNotEmpty) {
        await _appendUnit(unit);
      }
    }
    _flushBuffer();
    return NovelReaderPaginationPlan(
      key: key,
      episodeId: chapter.episodeId,
      pages: _pages,
    );
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
        maxPages <= 0 ||
        maxSplitSearchIterations <= 0) {
      throw const NovelReaderPaginationException(
        code: 'invalidBudget',
        message: 'Pagination budgets must be positive.',
      );
    }
  }

  Future<void> _appendUnit(NovelReaderFlowUnit unit) async {
    final textLength = _textLength(unit.html);
    final isBreakable =
        unit.breakability == NovelReaderFlowUnitBreakability.text ||
        unit.breakability == NovelReaderFlowUnitBreakability.inlineText;
    final whole = _pieceFor(unit, 0, textLength, unit.html);

    if (await _fits(whole)) {
      _appendPiece(whole);
      return;
    }
    if (_buffer != null) {
      _flushBuffer();
      if (await _fits(whole)) {
        _appendPiece(whole);
        return;
      }
    }
    if (!isBreakable || textLength == 0) {
      _appendOverflow(whole, NovelReaderPageOverflowState.atomicWidget);
      _flushBuffer();
      return;
    }
    await _appendBreakableUnit(unit, textLength);
  }

  Future<void> _appendBreakableUnit(
    NovelReaderFlowUnit unit,
    int textLength,
  ) async {
    var offset = 0;
    while (offset < textLength) {
      final bestEnd = await _largestFittingEnd(unit, offset, textLength);
      if (bestEnd > offset) {
        _appendPiece(
          _pieceFor(
            unit,
            offset,
            bestEnd,
            _sliceHtml(unit.html, offset, bestEnd),
          ),
        );
        offset = bestEnd;
        continue;
      }
      if (_buffer != null) {
        _flushBuffer();
        continue;
      }
      _appendOverflow(
        _pieceFor(
          unit,
          offset,
          textLength,
          _sliceHtml(unit.html, offset, textLength),
        ),
        NovelReaderPageOverflowState.minimumTextFragment,
      );
      offset = textLength;
      _flushBuffer();
    }
  }

  Future<int> _largestFittingEnd(
    NovelReaderFlowUnit unit,
    int start,
    int end,
  ) async {
    var low = start + 1;
    var high = end;
    var best = start;
    var iterations = 0;
    while (low <= high && iterations < maxSplitSearchIterations) {
      iterations += 1;
      final candidateEnd = (low + high) ~/ 2;
      final piece = _pieceFor(
        unit,
        start,
        candidateEnd,
        _sliceHtml(unit.html, start, candidateEnd),
      );
      if (await _fits(piece)) {
        best = candidateEnd;
        low = candidateEnd + 1;
      } else {
        high = candidateEnd - 1;
      }
    }
    return best;
  }

  Future<bool> _fits(_PagePiece piece) async {
    final candidate = '${_buffer?.html ?? ''}${piece.html}';
    final result = await _measureAdapter.measure(
      NovelReaderPaginationMeasureRequest(
        html: candidate,
        chapter: _chapter,
        key: _key,
      ),
    );
    _measurementCount += 1;
    if (_measurementCount > maxMeasurements) {
      throw const NovelReaderPaginationException(
        code: 'candidateLimitExceeded',
        message: 'Pagination candidate measurement budget was exceeded.',
      );
    }
    if (!result.height.isFinite || result.height < 0) {
      throw const NovelReaderPaginationException(
        code: 'invalidMeasurement',
        message: 'HTML renderer returned an invalid pagination height.',
      );
    }
    return result.height <= _key.viewportHeightPx;
  }

  _PagePiece _pieceFor(
    NovelReaderFlowUnit unit,
    int start,
    int end,
    String html,
  ) {
    final baseOffset = unit.startAnchor.textOffset;
    return _PagePiece(
      html: html,
      startAnchor: unit.startAnchor.copyWith(
        textOffset: baseOffset + start,
        pageIndex: 0,
        scrollOffset: 0,
        progressPercent: 0,
      ),
      endAnchor: unit.endAnchor.copyWith(
        textOffset: baseOffset + end,
        pageIndex: 0,
        scrollOffset: 0,
        progressPercent: 0,
      ),
      imageIndices: _imageIndices(html),
    );
  }

  void _appendPiece(_PagePiece piece) {
    final buffer = _buffer ??= _PageBuffer();
    buffer.append(piece);
  }

  void _appendOverflow(_PagePiece piece, NovelReaderPageOverflowState state) {
    final buffer = _buffer ??= _PageBuffer();
    buffer.append(
      _PagePiece(
        html: piece.html,
        startAnchor: piece.startAnchor,
        endAnchor: piece.endAnchor,
        imageIndices: piece.imageIndices,
        overflowState: state,
      ),
    );
  }

  void _flushBuffer() {
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
        overflowState: buffer.overflowState,
        requiresInnerScroll:
            buffer.overflowState != NovelReaderPageOverflowState.none,
      ),
    );
    _buffer = null;
  }

  int _textLength(String html) {
    return (html_parser.parseFragment(html).text ?? '').runes.length;
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

class _PagePiece {
  const _PagePiece({
    required this.html,
    required this.startAnchor,
    required this.endAnchor,
    required this.imageIndices,
    this.overflowState = NovelReaderPageOverflowState.none,
  });

  final String html;
  final NovelReaderTextAnchor startAnchor;
  final NovelReaderTextAnchor endAnchor;
  final List<int> imageIndices;
  final NovelReaderPageOverflowState overflowState;
}

class _PageBuffer {
  final StringBuffer _html = StringBuffer();
  final Set<int> _imageIndices = <int>{};
  NovelReaderTextAnchor? startAnchor;
  NovelReaderTextAnchor? endAnchor;
  NovelReaderPageOverflowState overflowState =
      NovelReaderPageOverflowState.none;

  String get html => _html.toString();

  List<int> get imageIndices {
    final result = _imageIndices.toList()..sort();
    return List<int>.unmodifiable(result);
  }

  void append(_PagePiece piece) {
    startAnchor ??= piece.startAnchor;
    endAnchor = piece.endAnchor;
    _html.write(piece.html);
    _imageIndices.addAll(piece.imageIndices);
    if (piece.overflowState != NovelReaderPageOverflowState.none) {
      overflowState = piece.overflowState;
    }
  }
}

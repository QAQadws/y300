import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_atom.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_text_run.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_text_pagination.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_html_text_range_slicer.dart';

abstract interface class NovelReaderTextPaginationEngine {
  NovelReaderTextPaginationResult paginate({
    required NovelReaderClassifiedPaginationAtom atom,
    required List<NovelReaderPaginationTextRun> runs,
    required double width,
    required double pageHeight,
    double? firstPageHeight,
    required double paragraphSpacing,
    required String typographySignature,
    TextDirection textDirection = TextDirection.ltr,
    TextAlign textAlign = TextAlign.start,
    TextScaler textScaler = TextScaler.noScaling,
  });
}

/// Aligns TextPainter metrics with the block sizing used by the final HTML
/// renderer.
///
/// flutter_widget_from_html_core composes text into RenderParagraph blocks
/// whose logical height is rounded up. Summing unrounded per-atom metrics can
/// otherwise underestimate a dense page by several pixels.
abstract final class NovelReaderPaginationLineHeightPolicy {
  static const double _floatingPointTolerance = 0.000001;

  static double alignToRenderer(double value) {
    if (!value.isFinite || value <= 0) {
      return value;
    }
    return (value - _floatingPointTolerance).ceilToDouble();
  }
}

final class NovelReaderTextMetricsCache {
  NovelReaderTextMetricsCache({this.capacity = 128}) {
    if (capacity <= 0) {
      throw ArgumentError.value(capacity, 'capacity', 'must be positive');
    }
  }

  final int capacity;
  final LinkedHashMap<_TextMetricsKey, NovelReaderTextLayoutMetrics> _entries =
      LinkedHashMap<_TextMetricsKey, NovelReaderTextLayoutMetrics>();

  int get length => _entries.length;

  NovelReaderTextLayoutMetrics? _get(_TextMetricsKey key) {
    final value = _entries.remove(key);
    if (value != null) {
      _entries[key] = value;
    }
    return value;
  }

  void _put(_TextMetricsKey key, NovelReaderTextLayoutMetrics metrics) {
    _entries.remove(key);
    _entries[key] = metrics;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() => _entries.clear();
}

final class DefaultNovelReaderTextPaginationEngine
    implements NovelReaderTextPaginationEngine {
  DefaultNovelReaderTextPaginationEngine({
    NovelReaderTextMetricsCache? metricsCache,
    this.rangeSlicer = const NovelReaderHtmlTextRangeSlicer(),
  }) : metricsCache = metricsCache ?? NovelReaderTextMetricsCache();

  final NovelReaderTextMetricsCache metricsCache;
  final NovelReaderHtmlTextRangeSlicer rangeSlicer;

  @override
  NovelReaderTextPaginationResult paginate({
    required NovelReaderClassifiedPaginationAtom atom,
    required List<NovelReaderPaginationTextRun> runs,
    required double width,
    required double pageHeight,
    double? firstPageHeight,
    required double paragraphSpacing,
    required String typographySignature,
    TextDirection textDirection = TextDirection.ltr,
    TextAlign textAlign = TextAlign.start,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    if (atom.route != NovelReaderPaginationRoute.safeText) {
      throw ArgumentError.value(
        atom.route,
        'atom',
        'Text pagination accepts safe text atoms only.',
      );
    }
    final resolvedFirstPageHeight = firstPageHeight ?? pageHeight;
    if (!width.isFinite ||
        width <= 0 ||
        !pageHeight.isFinite ||
        pageHeight <= 0 ||
        !resolvedFirstPageHeight.isFinite ||
        resolvedFirstPageHeight <= 0) {
      throw ArgumentError('Text pagination requires positive finite bounds.');
    }
    if (atom.atom.kind == NovelReaderPaginationAtomKind.spacer) {
      final structuralBreakCount = runs
          .where((run) => run.isParagraphBreak)
          .length;
      final metrics = NovelReaderTextLayoutMetrics(
        runId: atom.atom.atomId,
        lineRanges: const <NovelReaderTextLineRange>[],
        totalHeight: 0,
        width: width,
        typographySignature: typographySignature,
      );
      return NovelReaderTextPaginationResult(
        chunks: <NovelReaderTextPageChunk>[
          NovelReaderTextPageChunk(
            html: atom.atom.html,
            startAnchor: atom.atom.startAnchor,
            endAnchor: atom.atom.endAnchor,
            sourceStart: 0,
            sourceEnd: 0,
            usedHeight: 0,
            isOversized: false,
            hasRenderableContent: false,
            structuralBreakCount: structuralBreakCount,
          ),
        ],
        metrics: metrics,
        metricsCacheHit: false,
        layoutCount: 0,
      );
    }
    final key = _TextMetricsKey(
      atomId: atom.atom.atomId,
      contentSignature: _contentSignature(atom.atom.html, runs),
      widthMilli: (width * 1000).round(),
      typographySignature: typographySignature,
      direction: textDirection,
      textAlign: textAlign,
      textScaleMilli: (textScaler.scale(1000)).round(),
    );
    var metrics = metricsCache._get(key);
    final cacheHit = metrics != null;
    var layoutCount = 0;
    metrics ??= _layout(
      atom: atom,
      runs: runs,
      width: width,
      typographySignature: typographySignature,
      textDirection: textDirection,
      textAlign: textAlign,
      textScaler: textScaler,
    );
    if (!cacheHit) {
      layoutCount = 1;
      metricsCache._put(key, metrics);
    }
    final chunks = _composeChunks(
      atom: atom,
      metrics: metrics,
      pageHeight: pageHeight,
      firstPageHeight: resolvedFirstPageHeight,
      paragraphSpacing: paragraphSpacing,
    );
    return NovelReaderTextPaginationResult(
      chunks: chunks,
      metrics: metrics,
      metricsCacheHit: cacheHit,
      layoutCount: layoutCount,
    );
  }

  NovelReaderTextLayoutMetrics _layout({
    required NovelReaderClassifiedPaginationAtom atom,
    required List<NovelReaderPaginationTextRun> runs,
    required double width,
    required String typographySignature,
    required TextDirection textDirection,
    required TextAlign textAlign,
    required TextScaler textScaler,
  }) {
    final flattened = _flattenRuns(atom, runs);
    final painter = TextPainter(
      text: TextSpan(children: flattened.spans),
      textDirection: textDirection,
      textAlign: textAlign,
      textScaler: textScaler,
    );
    try {
      painter.layout(maxWidth: width);
      final lineMetrics = painter.computeLineMetrics();
      final ranges = <NovelReaderTextLineRange>[];
      var layoutOffset = 0;
      var top = 0.0;
      for (var index = 0; index < lineMetrics.length; index += 1) {
        final metric = lineMetrics[index];
        TextRange layoutRange;
        if (layoutOffset < flattened.text.length) {
          layoutRange = painter.getLineBoundary(
            TextPosition(offset: layoutOffset),
          );
          if (layoutRange.end <= layoutOffset) {
            layoutRange = TextRange(
              start: layoutOffset,
              end: (layoutOffset + 1).clamp(0, flattened.text.length),
            );
          }
        } else {
          layoutRange = TextRange.empty;
        }
        final start = layoutRange.start.clamp(0, flattened.text.length);
        final end = layoutRange.end.clamp(start, flattened.text.length);
        final lineHeight =
            NovelReaderPaginationLineHeightPolicy.alignToRenderer(
              metric.height,
            );
        final bottom = top + lineHeight;
        ranges.add(
          NovelReaderTextLineRange(
            layoutStart: start,
            layoutEnd: end,
            sourceStart: flattened.sourceOffsets[start],
            sourceEnd: flattened.sourceOffsets[end],
            top: top,
            bottom: bottom,
            hardBreak: metric.hardBreak,
            hasRenderableContent: _hasRenderableText(
              flattened.text.substring(start, end),
            ),
          ),
        );
        top = bottom;
        layoutOffset = _nextLineLayoutOffset(
          flattened.text,
          boundaryEnd: end,
          currentOffset: layoutOffset,
        );
      }
      return NovelReaderTextLayoutMetrics(
        runId: atom.atom.atomId,
        lineRanges: ranges,
        totalHeight: top,
        width: width,
        typographySignature: typographySignature,
      );
    } finally {
      painter.dispose();
    }
  }

  List<NovelReaderTextPageChunk> _composeChunks({
    required NovelReaderClassifiedPaginationAtom atom,
    required NovelReaderTextLayoutMetrics metrics,
    required double pageHeight,
    required double firstPageHeight,
    required double paragraphSpacing,
  }) {
    final sliceSession = rangeSlicer.prepare(atom.atom.html);
    if (metrics.lineRanges.isEmpty || atom.atom.textLength == 0) {
      return <NovelReaderTextPageChunk>[
        _chunk(
          atom: atom,
          sliceSession: sliceSession,
          start: 0,
          end: atom.atom.textLength,
          usedHeight: metrics.totalHeight + paragraphSpacing,
          isOversized: metrics.totalHeight + paragraphSpacing > pageHeight,
          hasRenderableContent: metrics.lineRanges.any(
            (line) => line.hasRenderableContent,
          ),
        ),
      ];
    }
    if (atom.atom.kind.name == 'heading') {
      final height = metrics.totalHeight + paragraphSpacing;
      return <NovelReaderTextPageChunk>[
        _chunk(
          atom: atom,
          sliceSession: sliceSession,
          start: 0,
          end: atom.atom.textLength,
          usedHeight: height,
          isOversized: height > pageHeight,
          hasRenderableContent: metrics.lineRanges.any(
            (line) => line.hasRenderableContent,
          ),
        ),
      ];
    }

    final chunks = <NovelReaderTextPageChunk>[];
    var firstLine = 0;
    var usedHeight = 0.0;
    var hasRenderableContent = false;
    for (var index = 0; index < metrics.lineRanges.length; index += 1) {
      final line = metrics.lineRanges[index];
      final isLastLine = index == metrics.lineRanges.length - 1;
      final addition = line.height + (isLastLine ? paragraphSpacing : 0);
      final currentBudget = chunks.isEmpty ? firstPageHeight : pageHeight;
      if (usedHeight > 0 && usedHeight + addition > currentBudget) {
        final previous = metrics.lineRanges[index - 1];
        chunks.add(
          _chunk(
            atom: atom,
            sliceSession: sliceSession,
            start: metrics.lineRanges[firstLine].sourceStart,
            end: previous.sourceEnd,
            usedHeight: usedHeight,
            isOversized: false,
            hasRenderableContent: hasRenderableContent,
          ),
        );
        firstLine = index;
        usedHeight = 0;
        hasRenderableContent = false;
      }
      usedHeight += addition;
      hasRenderableContent = hasRenderableContent || line.hasRenderableContent;
      final lineBudget = chunks.isEmpty ? firstPageHeight : pageHeight;
      if (usedHeight > lineBudget && firstLine == index) {
        chunks.add(
          _chunk(
            atom: atom,
            sliceSession: sliceSession,
            start: line.sourceStart,
            end: line.sourceEnd,
            usedHeight: usedHeight,
            isOversized: true,
            hasRenderableContent: hasRenderableContent,
          ),
        );
        firstLine = index + 1;
        usedHeight = 0;
        hasRenderableContent = false;
      }
    }
    if (firstLine < metrics.lineRanges.length) {
      chunks.add(
        _chunk(
          atom: atom,
          sliceSession: sliceSession,
          start: metrics.lineRanges[firstLine].sourceStart,
          end: metrics.lineRanges.last.sourceEnd,
          usedHeight: usedHeight,
          isOversized: usedHeight > pageHeight,
          hasRenderableContent: hasRenderableContent,
        ),
      );
    }
    return List<NovelReaderTextPageChunk>.unmodifiable(chunks);
  }

  NovelReaderTextPageChunk _chunk({
    required NovelReaderClassifiedPaginationAtom atom,
    required NovelReaderHtmlTextRangeSliceSession sliceSession,
    required int start,
    required int end,
    required double usedHeight,
    required bool isOversized,
    required bool hasRenderableContent,
  }) {
    final safeStart = start.clamp(0, atom.atom.textLength);
    final safeEnd = end.clamp(safeStart, atom.atom.textLength);
    final baseOffset = atom.atom.startAnchor.textOffset;
    return NovelReaderTextPageChunk(
      html: sliceSession.slice(start: safeStart, end: safeEnd),
      startAnchor: atom.atom.startAnchor.copyWith(
        textOffset: baseOffset + safeStart,
      ),
      endAnchor: atom.atom.endAnchor.copyWith(textOffset: baseOffset + safeEnd),
      sourceStart: safeStart,
      sourceEnd: safeEnd,
      usedHeight: usedHeight,
      isOversized: isOversized,
      hasRenderableContent: hasRenderableContent,
    );
  }

  bool _hasRenderableText(String text) {
    return _renderableTextPattern.hasMatch(text);
  }

  int _nextLineLayoutOffset(
    String text, {
    required int boundaryEnd,
    required int currentOffset,
  }) {
    var next = boundaryEnd.clamp(0, text.length);
    if (next < text.length) {
      final codeUnit = text.codeUnitAt(next);
      if (codeUnit == 0x0D &&
          next + 1 < text.length &&
          text.codeUnitAt(next + 1) == 0x0A) {
        next += 2;
      } else if (codeUnit == 0x0A ||
          codeUnit == 0x0D ||
          codeUnit == 0x2028 ||
          codeUnit == 0x2029) {
        next += 1;
      }
    }
    if (next <= currentOffset && currentOffset < text.length) {
      return currentOffset + 1;
    }
    return next;
  }

  static final RegExp _renderableTextPattern = RegExp(
    r'[^\s\u00A0\u200B\u2060\u3000\uFEFF]',
  );

  _FlattenedText _flattenRuns(
    NovelReaderClassifiedPaginationAtom atom,
    List<NovelReaderPaginationTextRun> runs,
  ) {
    final buffer = StringBuffer();
    final spans = <InlineSpan>[];
    final sourceOffsets = <int>[0];
    final atomBase = atom.atom.startAnchor.textOffset;
    var currentSource = 0;
    for (final run in runs) {
      currentSource = (run.startAnchor.textOffset - atomBase).clamp(
        currentSource,
        atom.atom.textLength,
      );
      final spanText = StringBuffer();
      final runes = run.text.runes.toList(growable: false);
      for (var index = 0; index < runes.length; index += 1) {
        final sourceStart = currentSource;
        if (run.isParagraphBreak) {
          _appendLayoutText(
            text: String.fromCharCode(runes[index]),
            sourceStart: sourceStart,
            sourceEnd: sourceStart,
            documentBuffer: buffer,
            spanBuffer: spanText,
            sourceOffsets: sourceOffsets,
          );
          continue;
        }
        if (_isCollapsibleHtmlWhitespace(runes[index])) {
          do {
            currentSource = (currentSource + 1).clamp(0, atom.atom.textLength);
            index += 1;
          } while (index < runes.length &&
              _isCollapsibleHtmlWhitespace(runes[index]));
          index -= 1;
          _appendLayoutText(
            text: ' ',
            sourceStart: sourceStart,
            sourceEnd: currentSource,
            documentBuffer: buffer,
            spanBuffer: spanText,
            sourceOffsets: sourceOffsets,
          );
          continue;
        }
        currentSource = (currentSource + 1).clamp(0, atom.atom.textLength);
        _appendLayoutText(
          text: String.fromCharCode(runes[index]),
          sourceStart: sourceStart,
          sourceEnd: currentSource,
          documentBuffer: buffer,
          spanBuffer: spanText,
          sourceOffsets: sourceOffsets,
        );
      }
      if (spanText.isNotEmpty) {
        spans.add(TextSpan(text: spanText.toString(), style: run.style));
      }
    }
    return _FlattenedText(
      buffer.toString(),
      List<int>.unmodifiable(sourceOffsets),
      List<InlineSpan>.unmodifiable(spans),
    );
  }

  void _appendLayoutText({
    required String text,
    required int sourceStart,
    required int sourceEnd,
    required StringBuffer documentBuffer,
    required StringBuffer spanBuffer,
    required List<int> sourceOffsets,
  }) {
    documentBuffer.write(text);
    spanBuffer.write(text);
    for (var unit = 0; unit < text.length; unit += 1) {
      sourceOffsets.add(unit == text.length - 1 ? sourceEnd : sourceStart);
    }
  }

  bool _isCollapsibleHtmlWhitespace(int rune) {
    return rune == 0x09 ||
        rune == 0x0A ||
        rune == 0x0C ||
        rune == 0x0D ||
        rune == 0x20;
  }

  String _contentSignature(
    String html,
    List<NovelReaderPaginationTextRun> runs,
  ) {
    final buffer = StringBuffer(html);
    for (final run in runs) {
      final style = run.style;
      buffer
        ..write('|${run.text}')
        ..write('|${style.color?.toARGB32()}')
        ..write('|${style.backgroundColor?.toARGB32()}')
        ..write('|${style.fontSize}')
        ..write('|${style.height}')
        ..write('|${style.fontWeight?.value}')
        ..write('|${style.fontStyle?.index}')
        ..write('|${style.fontFamily}')
        ..write('|${style.decoration}')
        ..write('|${run.href}');
    }
    return _stableHash(buffer.toString());
  }

  String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

final class _FlattenedText {
  const _FlattenedText(this.text, this.sourceOffsets, this.spans);

  final String text;
  final List<int> sourceOffsets;
  final List<InlineSpan> spans;
}

final class _TextMetricsKey {
  const _TextMetricsKey({
    required this.atomId,
    required this.contentSignature,
    required this.widthMilli,
    required this.typographySignature,
    required this.direction,
    required this.textAlign,
    required this.textScaleMilli,
  });

  final String atomId;
  final String contentSignature;
  final int widthMilli;
  final String typographySignature;
  final TextDirection direction;
  final TextAlign textAlign;
  final int textScaleMilli;

  @override
  bool operator ==(Object other) {
    return other is _TextMetricsKey &&
        other.atomId == atomId &&
        other.contentSignature == contentSignature &&
        other.widthMilli == widthMilli &&
        other.typographySignature == typographySignature &&
        other.direction == direction &&
        other.textAlign == textAlign &&
        other.textScaleMilli == textScaleMilli;
  }

  @override
  int get hashCode => Object.hash(
    atomId,
    contentSignature,
    widthMilli,
    typographySignature,
    direction,
    textAlign,
    textScaleMilli,
  );
}

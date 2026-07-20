import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_classified_pagination_atom.dart';
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
      text: TextSpan(
        children: runs
            .map((run) => TextSpan(text: run.text, style: run.style))
            .toList(growable: false),
      ),
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
        final bottom = top + metric.height;
        ranges.add(
          NovelReaderTextLineRange(
            layoutStart: start,
            layoutEnd: end,
            sourceStart: flattened.sourceOffsets[start],
            sourceEnd: flattened.sourceOffsets[end],
            top: top,
            bottom: bottom,
            hardBreak: metric.hardBreak,
          ),
        );
        top = bottom;
        layoutOffset = end > layoutOffset ? end : layoutOffset + 1;
      }
      return NovelReaderTextLayoutMetrics(
        runId: atom.atom.atomId,
        lineRanges: ranges,
        totalHeight: painter.height,
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
    if (metrics.lineRanges.isEmpty || atom.atom.textLength == 0) {
      return <NovelReaderTextPageChunk>[
        _chunk(
          atom: atom,
          start: 0,
          end: atom.atom.textLength,
          usedHeight: metrics.totalHeight + paragraphSpacing,
          isOversized: metrics.totalHeight + paragraphSpacing > pageHeight,
        ),
      ];
    }
    if (atom.atom.kind.name == 'heading') {
      final height = metrics.totalHeight + paragraphSpacing;
      return <NovelReaderTextPageChunk>[
        _chunk(
          atom: atom,
          start: 0,
          end: atom.atom.textLength,
          usedHeight: height,
          isOversized: height > pageHeight,
        ),
      ];
    }

    final chunks = <NovelReaderTextPageChunk>[];
    var firstLine = 0;
    var usedHeight = 0.0;
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
            start: metrics.lineRanges[firstLine].sourceStart,
            end: previous.sourceEnd,
            usedHeight: usedHeight,
            isOversized: false,
          ),
        );
        firstLine = index;
        usedHeight = 0;
      }
      usedHeight += addition;
      final lineBudget = chunks.isEmpty ? firstPageHeight : pageHeight;
      if (usedHeight > lineBudget && firstLine == index) {
        chunks.add(
          _chunk(
            atom: atom,
            start: line.sourceStart,
            end: line.sourceEnd,
            usedHeight: usedHeight,
            isOversized: true,
          ),
        );
        firstLine = index + 1;
        usedHeight = 0;
      }
    }
    if (firstLine < metrics.lineRanges.length) {
      chunks.add(
        _chunk(
          atom: atom,
          start: metrics.lineRanges[firstLine].sourceStart,
          end: metrics.lineRanges.last.sourceEnd,
          usedHeight: usedHeight,
          isOversized: usedHeight > pageHeight,
        ),
      );
    }
    return List<NovelReaderTextPageChunk>.unmodifiable(chunks);
  }

  NovelReaderTextPageChunk _chunk({
    required NovelReaderClassifiedPaginationAtom atom,
    required int start,
    required int end,
    required double usedHeight,
    required bool isOversized,
  }) {
    final safeStart = start.clamp(0, atom.atom.textLength);
    final safeEnd = end.clamp(safeStart, atom.atom.textLength);
    final baseOffset = atom.atom.startAnchor.textOffset;
    return NovelReaderTextPageChunk(
      html: rangeSlicer.slice(
        html: atom.atom.html,
        start: safeStart,
        end: safeEnd,
      ),
      startAnchor: atom.atom.startAnchor.copyWith(
        textOffset: baseOffset + safeStart,
      ),
      endAnchor: atom.atom.endAnchor.copyWith(textOffset: baseOffset + safeEnd),
      sourceStart: safeStart,
      sourceEnd: safeEnd,
      usedHeight: usedHeight,
      isOversized: isOversized,
    );
  }

  _FlattenedText _flattenRuns(
    NovelReaderClassifiedPaginationAtom atom,
    List<NovelReaderPaginationTextRun> runs,
  ) {
    final buffer = StringBuffer();
    final sourceOffsets = <int>[0];
    final atomBase = atom.atom.startAnchor.textOffset;
    var currentSource = 0;
    for (final run in runs) {
      currentSource = (run.startAnchor.textOffset - atomBase).clamp(
        currentSource,
        atom.atom.textLength,
      );
      for (final rune in run.text.runes) {
        final text = String.fromCharCode(rune);
        buffer.write(text);
        final nextSource = run.isParagraphBreak
            ? currentSource
            : (currentSource + 1).clamp(0, atom.atom.textLength);
        for (var unit = 0; unit < text.length; unit += 1) {
          sourceOffsets.add(
            unit == text.length - 1 ? nextSource : currentSource,
          );
        }
        currentSource = nextSource;
      }
    }
    return _FlattenedText(
      buffer.toString(),
      List<int>.unmodifiable(sourceOffsets),
    );
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
  const _FlattenedText(this.text, this.sourceOffsets);

  final String text;
  final List<int> sourceOffsets;
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

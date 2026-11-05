import 'package:characters/characters.dart';

enum HtmlDisplayWhiteSpace {
  normal,
  pre,
  preWrap,
  preLine,

  /// Explicit format-level normalization, including BR, Unicode whitespace
  /// and nonbreaking spaces. Ordinary HTML text keeps its CSS whitespace rules.
  singleLine,
}

enum HtmlProjectionAffinity { upstream, downstream }

/// One text node (or explicit BR) in source order. Offsets count source runes.
final class HtmlDisplayTextRun {
  const HtmlDisplayTextRun({
    required this.text,
    required this.sourceRuneStart,
    this.whiteSpace = HtmlDisplayWhiteSpace.normal,
    this.hardBreak = false,
  });
  final String text;
  final int sourceRuneStart;
  final HtmlDisplayWhiteSpace whiteSpace;
  final bool hardBreak;
}

/// The original run index preserves style/interaction ownership after collapse.
final class HtmlDisplayTextPart {
  const HtmlDisplayTextPart(this.runIndex, this.text, this.utf16Start);
  final int runIndex;
  final String text;
  final int utf16Start;
}

/// An independently formatted child, with explicit parent style-run ownership.
/// Ordinary adjacent style spans should still be built as one run sequence.
final class HtmlDisplayTextSegment {
  const HtmlDisplayTextSegment(
    this.projection, {
    this.runIndexOffset = 0,
    this.runIndexMap,
  });
  final HtmlDisplayTextProjection projection;
  final int runIndexOffset;

  /// Explicit ownership for windows sharing a style table. Every used index
  /// must map to a nonnegative parent index. Cannot be combined with an offset;
  /// unused indices are irrelevant and the composition retains no mutable map.
  final Map<int, int>? runIndexMap;
}

final class HtmlProjectedSourcePosition {
  const HtmlProjectedSourcePosition({
    required this.sourceRune,
    required this.displayUtf16,
    required this.isExact,
  });
  final int sourceRune;
  final int displayUtf16;

  /// False inside a display grapheme or at a discontinuous source boundary.
  /// This is a projection result, never evidence for an App semantic anchor.
  final bool isExact;
}

final class HtmlDisplayTextLimitException implements Exception {
  const HtmlDisplayTextLimitException();
}

/// Paragraph-local whitespace projection; no HTML slicing or semantic anchors.
/// NBSP and ideographic spaces remain literal. Only collapsible edge whitespace
/// is discarded, and preformatted whitespace is never trimmed.
final class HtmlDisplayTextProjection {
  static const revision = 8;

  /// Whitespace accepted by the explicit single-line projection policy. This
  /// predicate does not classify forum content or change normal HTML spacing.
  static bool isSingleLineWhitespace(int rune) =>
      const {
        0x09,
        0x0a,
        0x0b,
        0x0c,
        0x0d,
        0x20,
        0x85,
        0xa0,
        0x1680,
        0x2028,
        0x2029,
        0x202f,
        0x205f,
        0x3000,
        0xfeff,
      }.contains(rune) ||
      rune >= 0x2000 && rune <= 0x200a;
  HtmlDisplayTextProjection._(
    this.text,
    this.parts,
    this._runes,
    this._utf16Starts,
    this._graphemeBoundaries,
    this._emptySource, {
    int? leadingBeforeSource,
    int? trailingAfterSource,
    bool sourceIsOrdered = true,
    List<int> collapsibleSegmentBreakOffsets = const [],
  }) : _leadingBeforeSource = leadingBeforeSource,
       _trailingAfterSource = trailingAfterSource,
       _sourceIsOrdered = sourceIsOrdered,
       _collapsibleSegmentBreakOffsets = collapsibleSegmentBreakOffsets;

  /// [suppressLineBreaks] joins forced breaks as collapsible U+0020, while
  /// keeping each run's other whitespace rules. Consecutive breaks share one
  /// actual source range; CRLF remains one break even across styled runs.
  factory HtmlDisplayTextProjection.build(
    List<HtmlDisplayTextRun> runs, {
    int maxOutputCodeUnits = 16384,
    bool preserveCollapsibleEdges = false,
    bool suppressLineBreaks = false,
  }) {
    if (maxOutputCodeUnits < 0) throw ArgumentError.value(maxOutputCodeUnits);
    final builder = _ProjectionBuilder(
      maxOutputCodeUnits,
      preserveCollapsibleEdges,
      suppressLineBreaks,
    );
    var previousEnd = 0;
    for (var i = 0; i < runs.length; i++) {
      final run = runs[i];
      if (run.sourceRuneStart < previousEnd ||
          (run.hardBreak && run.text != '\n')) {
        throw ArgumentError('Invalid display text source order');
      }
      var source = run.sourceRuneStart;
      for (final rune in run.text.runes) {
        builder.add(rune, source++, i, run.whiteSpace, run.hardBreak);
      }
      previousEnd = source;
    }
    return builder.finish(runs.isEmpty ? 0 : runs.first.sourceRuneStart);
  }

  /// Concatenates already projected, independent formatting contexts without
  /// normalizing whitespace or joining graphemes across their boundaries.
  /// Run offsets address the caller's combined style table, not DOM positions.
  /// [sourceOrder], when present, is a complete permutation of segment indices
  /// in original source order. Every child must itself remain source-ordered;
  /// all actual source ranges and empty fences are checked for overlap/reversal.
  /// Output always follows the supplied display order, with original sources.
  factory HtmlDisplayTextProjection.concatenate(
    List<HtmlDisplayTextSegment> segments, {
    List<int>? sourceOrder,
    int maxOutputCodeUnits = 16384,
    int maxSegments = 512,
  }) {
    if (maxOutputCodeUnits < 0 || maxSegments < 0) {
      throw ArgumentError('Invalid projection budget');
    }
    if (segments.length > maxSegments) {
      throw const HtmlDisplayTextLimitException();
    }
    var totalLength = 0;
    for (final segment in segments) {
      totalLength += segment.projection.text.length;
      if (totalLength > maxOutputCodeUnits) {
        throw const HtmlDisplayTextLimitException();
      }
    }
    _validateSourceOrder(segments, sourceOrder);
    final text = StringBuffer();
    final parts = <HtmlDisplayTextPart>[];
    final runes = <_ProjectedRune>[];
    final utf16Starts = <int>[0];
    final boundaries = <int>[0];
    var length = 0;
    var sourceIsOrdered = true;
    List<int>? segmentBreakOffsets;
    int? previousRuneEnd;
    for (final segment in segments) {
      final projection = segment.projection;
      if (segment.runIndexOffset < 0 ||
          (segment.runIndexMap != null && segment.runIndexOffset != 0)) {
        throw ArgumentError.value(segment.runIndexOffset);
      }
      int runIndex(int index) {
        final map = segment.runIndexMap;
        if (map == null) return index + segment.runIndexOffset;
        final mapped = map[index];
        if (mapped == null || mapped < 0) {
          throw ArgumentError('Missing or invalid projected run ownership');
        }
        return mapped;
      }

      text.write(projection.text);
      for (final part in projection.parts) {
        parts.add(
          HtmlDisplayTextPart(
            runIndex(part.runIndex),
            part.text,
            part.utf16Start + length,
          ),
        );
      }
      for (final rune in projection._runes) {
        if (previousRuneEnd != null && rune.start < previousRuneEnd) {
          sourceIsOrdered = false;
        }
        previousRuneEnd = rune.end;
        runes.add(
          _ProjectedRune(
            rune.rune,
            rune.start,
            rune.end,
            runIndex(rune.runIndex),
          ),
        );
      }
      utf16Starts.addAll(
        projection._utf16Starts.skip(1).map((offset) => offset + length),
      );
      if (projection._collapsibleSegmentBreakOffsets.isNotEmpty) {
        (segmentBreakOffsets ??= []).addAll(
          projection._collapsibleSegmentBreakOffsets.map(
            (offset) => offset + length,
          ),
        );
      }
      boundaries.addAll(
        projection._graphemeBoundaries.skip(1).map((offset) => offset + length),
      );
      length += projection.text.length;
    }
    return HtmlDisplayTextProjection._(
      text.toString(),
      List.unmodifiable(parts),
      List.unmodifiable(runes),
      List.unmodifiable(utf16Starts),
      List.unmodifiable(boundaries),
      segments.isEmpty ? 0 : segments.first.projection._emptySource,
      leadingBeforeSource: segments.isEmpty
          ? 0
          : segments.first.projection._leadingBefore,
      trailingAfterSource: segments.isEmpty
          ? 0
          : segments.last.projection._trailingAfter,
      sourceIsOrdered: sourceIsOrdered,
      collapsibleSegmentBreakOffsets: segmentBreakOffsets == null
          ? const []
          : List.unmodifiable(segmentBreakOffsets),
    );
  }

  final String text;
  final List<HtmlDisplayTextPart> parts;
  final List<_ProjectedRune> _runes;
  final List<int> _utf16Starts;
  final List<int> _graphemeBoundaries;
  final int _emptySource;
  final int? _leadingBeforeSource;
  final int? _trailingAfterSource;
  final bool _sourceIsOrdered;
  final List<int> _collapsibleSegmentBreakOffsets;

  /// Actual collapse origins, not an inference from the resulting space text.
  /// Preserved spaces, tabs, NBSP and hard line feeds never enter this list.
  bool get hasCollapsibleSegmentBreaks =>
      _collapsibleSegmentBreakOffsets.isNotEmpty;

  /// UTF-16 locations of displayed spaces originating in a source line break.
  List<int> get collapsibleSegmentBreakOffsets =>
      _collapsibleSegmentBreakOffsets;

  String? get firstGrapheme =>
      text.isEmpty ? null : text.substring(0, _graphemeBoundaries[1]);
  String? get lastGrapheme => text.isEmpty
      ? null
      : text.substring(_graphemeBoundaries[_graphemeBoundaries.length - 2]);

  /// Resolve a whitespace-only context with explicit formatting-context edges.
  /// The caller supplies its text/language policy; this port owns complete
  /// graphemes, original run indices and source affinity, never semantic offsets.
  /// A collapsed space joined to a mark cannot be removed in part.
  HtmlDisplayTextProjection resolveWhitespaceSegmentBreaks({
    required bool Function(String? before, String? after) shouldRemove,
    String? precedingGrapheme,
    String? followingGrapheme,
  }) {
    for (final edge in [precedingGrapheme, followingGrapheme]) {
      if (edge != null && edge.characters.length != 1) {
        throw ArgumentError('Segment-break context must be one whole grapheme');
      }
    }
    if (_runes.any((rune) => !isSingleLineWhitespace(rune.rune))) {
      throw ArgumentError('Segment-break gap must contain only whitespace');
    }
    List<int>? removed;
    for (final offset in _collapsibleSegmentBreakOffsets) {
      final index = _lowerBound(_graphemeBoundaries, offset);
      if (_graphemeBoundaries[index] != offset ||
          _graphemeBoundaries[index + 1] != offset + 1) {
        continue;
      }
      final before = index == 0
          ? precedingGrapheme
          : text.substring(_graphemeBoundaries[index - 1], offset);
      final after = index + 2 == _graphemeBoundaries.length
          ? followingGrapheme
          : text.substring(offset + 1, _graphemeBoundaries[index + 2]);
      if (shouldRemove(before, after)) (removed ??= []).add(offset);
    }
    if (removed == null) return this;
    final builder = _ProjectionBuilder(text.length, true, false);
    var removal = 0;
    var origin = 0;
    for (var i = 0; i < _runes.length; i++) {
      final offset = _utf16Starts[i];
      final isBreak =
          origin < _collapsibleSegmentBreakOffsets.length &&
          _collapsibleSegmentBreakOffsets[origin] == offset;
      if (isBreak) origin++;
      if (removal < removed.length && removed[removal] == offset) {
        removal++;
      } else {
        builder._emit(_runes[i], segmentBreak: isBreak);
      }
    }
    return builder.finish(
      _emptySource,
      leadingBeforeSource: _leadingBefore,
      trailingAfterSource: _trailingAfter,
      sourceIsOrdered: _sourceIsOrdered,
    );
  }

  int get _leadingBefore =>
      _leadingBeforeSource ??
      (_runes.isEmpty ? _emptySource : _runes.first.start);
  int get _trailingAfter =>
      _trailingAfterSource ??
      (_runes.isEmpty ? _leadingBefore : _runes.last.end);

  /// Display text and its actual independent grapheme contexts, without source
  /// or style ownership. Glyph reuse still needs complete font/layout inputs.
  late final int displaySegmentationHash = Object.hash(
    text,
    Object.hashAll(_graphemeBoundaries),
  );
  bool hasSameDisplaySegmentation(HtmlDisplayTextProjection other) {
    if (identical(this, other)) return true;
    if (displaySegmentationHash != other.displaySegmentationHash ||
        text != other.text ||
        _graphemeBoundaries.length != other._graphemeBoundaries.length) {
      return false;
    }
    for (var index = 0; index < _graphemeBoundaries.length; index++) {
      if (_graphemeBoundaries[index] != other._graphemeBoundaries[index]) {
        return false;
      }
    }
    return true;
  }

  /// A display-coordinate window, never an HTML slice. Both endpoints must be
  /// existing grapheme boundaries. Boundary affinity/source gaps and original
  /// style-run indices survive, including an empty window at a source gap.
  HtmlDisplayTextProjection slice({
    required int startUtf16,
    required int endUtf16,
  }) {
    RangeError.checkValidRange(startUtf16, endUtf16, text.length);
    final firstBoundary = _lowerBound(_graphemeBoundaries, startUtf16);
    final lastBoundary = _lowerBound(_graphemeBoundaries, endUtf16);
    if (_graphemeBoundaries[firstBoundary] != startUtf16 ||
        _graphemeBoundaries[lastBoundary] != endUtf16) {
      throw ArgumentError(
        'Display slice endpoints must be grapheme boundaries',
      );
    }
    final firstRune = _lowerBound(_utf16Starts, startUtf16);
    final lastRune = _lowerBound(_utf16Starts, endUtf16);
    final parts = <HtmlDisplayTextPart>[];
    for (final part in this.parts) {
      final start = (startUtf16 - part.utf16Start).clamp(0, part.text.length);
      final end = (endUtf16 - part.utf16Start).clamp(start, part.text.length);
      if (start < end) {
        parts.add(
          HtmlDisplayTextPart(
            part.runIndex,
            part.text.substring(start, end),
            part.utf16Start + start - startUtf16,
          ),
        );
      }
    }
    return HtmlDisplayTextProjection._(
      text.substring(startUtf16, endUtf16),
      List.unmodifiable(parts),
      List.unmodifiable(_runes.sublist(firstRune, lastRune)),
      List.unmodifiable(
        _utf16Starts
            .sublist(firstRune, lastRune + 1)
            .map((value) => value - startUtf16),
      ),
      List.unmodifiable(
        _graphemeBoundaries
            .sublist(firstBoundary, lastBoundary + 1)
            .map((value) => value - startUtf16),
      ),
      sourceAtUtf16(startUtf16).sourceRune,
      leadingBeforeSource: sourceAtUtf16(
        startUtf16,
        affinity: HtmlProjectionAffinity.upstream,
      ).sourceRune,
      trailingAfterSource: sourceAtUtf16(endUtf16).sourceRune,
      sourceIsOrdered: _sourceIsOrdered,
      collapsibleSegmentBreakOffsets: _sliceSegmentBreakOffsets(
        startUtf16,
        endUtf16,
      ),
    );
  }

  List<int> _sliceSegmentBreakOffsets(int start, int end) {
    final first = _lowerBound(_collapsibleSegmentBreakOffsets, start);
    final last = _lowerBound(_collapsibleSegmentBreakOffsets, end);
    return first == last
        ? const []
        : List.unmodifiable([
            for (var i = first; i < last; i++)
              _collapsibleSegmentBreakOffsets[i] - start,
          ]);
  }

  /// Envelope of actual source ranges in a complete display window. Interior
  /// gaps and reordered contexts may lie inside; this is only a search hint,
  /// never proof of visible text, source adjacency or a semantic anchor.
  ({int runeStart, int runeEnd})? sourceEnvelope({
    required int startUtf16,
    required int endUtf16,
  }) {
    RangeError.checkValidRange(startUtf16, endUtf16, text.length);
    if (startUtf16 == endUtf16) return null;
    if (sourceAtUtf16(startUtf16).displayUtf16 != startUtf16 ||
        sourceAtUtf16(endUtf16).displayUtf16 != endUtf16) {
      throw ArgumentError(
        'Source envelope requires complete display graphemes',
      );
    }
    final first = _lowerBound(_utf16Starts, startUtf16);
    final last = _lowerBound(_utf16Starts, endUtf16);
    var start = _runes[first].start;
    var end = _runes[last - 1].end;
    if (!_sourceIsOrdered) {
      for (var i = first; i < last; i++) {
        final rune = _runes[i];
        if (rune.start < start) start = rune.start;
        if (rune.end > end) end = rune.end;
      }
    }
    return (runeStart: start, runeEnd: end);
  }

  /// Process-local hash for caches retaining this source projection. Never a
  /// persisted identity: callers must also use [hasSameSourceMapping] to handle
  /// hash collisions. Style/run ownership is deliberately independent.
  late final int sourceMappingHash = Object.hash(
    displaySegmentationHash,
    _leadingBefore,
    _trailingAfter,
    Object.hashAll(_runes.map((rune) => Object.hash(rune.start, rune.end))),
  );

  /// Equal visible text can originate at different source coordinates or gaps.
  /// A match guarantees equal sourceAtUtf16 results, even if the input runs
  /// partition styling differently. This is not evidence for a semantic anchor
  /// or equality of the original HTML.
  bool hasSameSourceMapping(HtmlDisplayTextProjection other) {
    if (identical(this, other)) return true;
    if (sourceMappingHash != other.sourceMappingHash ||
        !hasSameDisplaySegmentation(other) ||
        _leadingBefore != other._leadingBefore ||
        _trailingAfter != other._trailingAfter ||
        _runes.length != other._runes.length) {
      return false;
    }
    for (var index = 0; index < _runes.length; index++) {
      final first = _runes[index];
      final second = other._runes[index];
      if (first.start != second.start || first.end != second.end) return false;
    }
    return true;
  }

  /// Enumerates only complete display graphemes in a verified line window.
  /// Invalid/non-grapheme endpoints are rejected rather than rounded. Source
  /// gaps still require explicit sourceAtUtf16 affinity; these ranges do not
  /// prove application semantic coverage or the visibility of any glyph.
  Iterable<({int startUtf16, int endUtf16})> graphemeRanges({
    required int startUtf16,
    required int endUtf16,
  }) sync* {
    RangeError.checkValidRange(startUtf16, endUtf16, text.length);
    final start = _lowerBound(_graphemeBoundaries, startUtf16);
    final end = _lowerBound(_graphemeBoundaries, endUtf16);
    if (_graphemeBoundaries[start] != startUtf16 ||
        _graphemeBoundaries[end] != endUtf16) {
      throw ArgumentError(
        'Display range endpoints must be grapheme boundaries',
      );
    }
    for (var index = start; index < end; index++) {
      yield (
        startUtf16: _graphemeBoundaries[index],
        endUtf16: _graphemeBoundaries[index + 1],
      );
    }
  }

  /// Contiguous display spans made of whole graphemes contained in the
  /// half-open source interval. Offsets in a collapsed space or grapheme
  /// never select part of it. Reordered contexts retain their display order.
  Iterable<({int startUtf16, int endUtf16})> displayRangesInSource({
    required int sourceStart,
    required int sourceEnd,
    required int startUtf16,
    required int endUtf16,
  }) sync* {
    if (sourceStart < 0 || sourceEnd < sourceStart) {
      throw ArgumentError('Invalid source range');
    }
    RangeError.checkValidRange(startUtf16, endUtf16, text.length);
    final first = _lowerBound(_graphemeBoundaries, startUtf16);
    final last = _lowerBound(_graphemeBoundaries, endUtf16);
    if (_graphemeBoundaries[first] != startUtf16 ||
        _graphemeBoundaries[last] != endUtf16) {
      throw ArgumentError(
        'Display range endpoints must be grapheme boundaries',
      );
    }
    if (sourceStart == sourceEnd || first == last) return;

    if (_sourceIsOrdered) {
      final from =
          _utf16Starts[_findRuneBoundary((rune) => rune.start < sourceStart)];
      final to =
          _utf16Starts[_findRuneBoundary((rune) => rune.end <= sourceEnd)];
      if (to <= startUtf16 || from >= endUtf16 || to <= from) return;
      final start = from <= startUtf16
          ? startUtf16
          : _graphemeBoundaries[_lowerBound(_graphemeBoundaries, from)];
      final end = to >= endUtf16
          ? endUtf16
          : sourceAtUtf16(
              to,
              affinity: HtmlProjectionAffinity.upstream,
            ).displayUtf16;
      if (start < end) yield (startUtf16: start, endUtf16: end);
      return;
    }

    int? start;
    for (var index = first; index < last; index++) {
      final from = _graphemeBoundaries[index];
      final bounds = sourceEnvelope(
        startUtf16: from,
        endUtf16: _graphemeBoundaries[index + 1],
      )!;
      if (sourceStart <= bounds.runeStart && bounds.runeEnd <= sourceEnd) {
        start ??= from;
      } else if (start != null) {
        yield (startUtf16: start, endUtf16: from);
        start = null;
      }
    }
    if (start != null) yield (startUtf16: start, endUtf16: endUtf16);
  }

  int _findRuneBoundary(bool Function(_ProjectedRune) before) {
    var low = 0, high = _runes.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (before(_runes[middle])) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  HtmlProjectedSourcePosition sourceAtUtf16(
    int offset, {
    HtmlProjectionAffinity affinity = HtmlProjectionAffinity.downstream,
  }) {
    RangeError.checkValueInInterval(offset, 0, text.length, 'offset');
    final downstream = affinity == HtmlProjectionAffinity.downstream;
    final graphemeIndex = _lowerBound(_graphemeBoundaries, offset);
    final isBoundary = _graphemeBoundaries[graphemeIndex] == offset;
    final display = isBoundary || downstream
        ? _graphemeBoundaries[graphemeIndex]
        : _graphemeBoundaries[graphemeIndex - 1];
    final runeIndex = _lowerBound(_utf16Starts, display);
    final before = runeIndex > 0 ? _runes[runeIndex - 1].end : _leadingBefore;
    final after = runeIndex < _runes.length
        ? _runes[runeIndex].start
        : _trailingAfter;
    return HtmlProjectedSourcePosition(
      sourceRune: downstream ? after : before,
      displayUtf16: display,
      isExact: isBoundary && before == after,
    );
  }
}

// The explicit permutation describes SOURCE order; output remains in the
// supplied display order. Validate every actual range, including each child's
// interior, so a reordered child cannot hide an overlap behind its endpoints.
void _validateSourceOrder(
  List<HtmlDisplayTextSegment> segments,
  List<int>? sourceOrder,
) {
  if (sourceOrder != null && sourceOrder.length != segments.length) {
    throw ArgumentError('Source order must include every display segment');
  }
  final seen = List<bool>.filled(segments.length, false);
  int? previousEnd;
  for (var i = 0; i < segments.length; i++) {
    final index = sourceOrder?[i] ?? i;
    RangeError.checkValidIndex(index, segments, 'sourceOrder');
    if (seen[index]) throw ArgumentError('Source order repeats a segment');
    seen[index] = true;
    final projection = segments[index].projection;
    if (projection._runes.isEmpty) {
      if ((previousEnd != null && projection._leadingBefore < previousEnd) ||
          projection._trailingAfter < projection._leadingBefore) {
        throw ArgumentError('Empty segment reverses source order');
      }
      previousEnd = projection._trailingAfter;
    }
    for (final rune in projection._runes) {
      if ((previousEnd != null && rune.start < previousEnd) ||
          rune.end <= rune.start) {
        throw ArgumentError('Projected ranges overlap or reverse source order');
      }
      previousEnd = rune.end;
    }
  }
}

int _lowerBound(List<int> sorted, int target) {
  var low = 0;
  var high = sorted.length;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    if (sorted[middle] < target) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

final class _ProjectedRune {
  _ProjectedRune(this.rune, this.start, this.end, this.runIndex);
  final int rune;
  final int start;
  int end;
  final int runIndex;
}

final class _ProjectionBuilder {
  _ProjectionBuilder(
    this.limit,
    this.preserveCollapsibleEdges,
    this.suppressLineBreaks,
  );
  final int limit;
  final bool preserveCollapsibleEdges;
  final bool suppressLineBreaks;
  final output = <_ProjectedRune>[];
  final utf16Starts = <int>[0];
  _ProjectedRune? pendingSpace;
  _ProjectedRune? previousCarriageReturn;
  bool pendingSpaceHasSegmentBreak = false;
  List<int>? _segmentBreakOffsets;

  void add(
    int rune,
    int source,
    int runIndex,
    HtmlDisplayWhiteSpace mode,
    bool hardBreak,
  ) {
    // HTML normally normalizes CRLF while parsing; keep this pure port usable
    // with already-decoded text too, including pairs split by styled runs.
    if (!hardBreak && rune == 10 && previousCarriageReturn != null) {
      previousCarriageReturn!.end = source + 1;
      previousCarriageReturn = null;
      return;
    }
    previousCarriageReturn = null;
    final value = _ProjectedRune(
      rune == 13 ? 10 : rune,
      source,
      source + 1,
      runIndex,
    );
    final collapse =
        mode == HtmlDisplayWhiteSpace.normal ||
        mode == HtmlDisplayWhiteSpace.preLine ||
        mode == HtmlDisplayWhiteSpace.singleLine;
    final singleLine = mode == HtmlDisplayWhiteSpace.singleLine;
    // Format-level suppression affects only forced breaks. In particular it
    // must not collapse preformatted tabs/spaces, NBSP or ideographic spaces.
    final suppressedBreak =
        suppressLineBreaks &&
        (hardBreak || const {10, 0x85, 0x2028, 0x2029}.contains(value.rune));
    if (!singleLine &&
        !suppressedBreak &&
        (hardBreak ||
            (mode != HtmlDisplayWhiteSpace.normal && value.rune == 10))) {
      pendingSpace = null;
      pendingSpaceHasSegmentBreak = false;
      _emit(value);
    } else if (suppressedBreak ||
        (collapse &&
            (singleLine
                ? HtmlDisplayTextProjection.isSingleLineWhitespace(value.rune)
                : const {9, 10, 12, 32}.contains(value.rune)))) {
      if (pendingSpace == null) {
        pendingSpace = _ProjectedRune(32, source, source + 1, runIndex);
        pendingSpaceHasSegmentBreak = false;
      } else {
        pendingSpace!.end = source + 1;
      }
      pendingSpaceHasSegmentBreak |= suppressedBreak || value.rune == 10;
      if (rune == 13) previousCarriageReturn = pendingSpace;
      return;
    } else {
      final space = pendingSpace;
      if (space != null &&
          (output.isEmpty
              ? preserveCollapsibleEdges
              : output.last.rune != 10)) {
        _emit(space, segmentBreak: pendingSpaceHasSegmentBreak);
      }
      pendingSpace = null;
      pendingSpaceHasSegmentBreak = false;
      _emit(value);
    }
    if (rune == 13) previousCarriageReturn = value;
  }

  void _emit(_ProjectedRune rune, {bool segmentBreak = false}) {
    final next = utf16Starts.last + (rune.rune > 0xffff ? 2 : 1);
    if (next > limit) throw const HtmlDisplayTextLimitException();
    if (segmentBreak) (_segmentBreakOffsets ??= []).add(utf16Starts.last);
    output.add(rune);
    utf16Starts.add(next);
  }

  HtmlDisplayTextProjection finish(
    int emptySource, {
    int? leadingBeforeSource,
    int? trailingAfterSource,
    bool sourceIsOrdered = true,
  }) {
    // An inline fragment does not own the surrounding formatting context.
    // Preserve one collapsed edge space for its parent to place or trim, while
    // actual hard-line edges retain the ordinary whitespace rules.
    final space = pendingSpace;
    if (preserveCollapsibleEdges &&
        space != null &&
        (output.isEmpty || output.last.rune != 10)) {
      _emit(space, segmentBreak: pendingSpaceHasSegmentBreak);
    }
    final parts = <HtmlDisplayTextPart>[];
    final text = StringBuffer();
    var i = 0;
    while (i < output.length) {
      final start = i;
      final run = output[i].runIndex;
      final part = StringBuffer();
      while (i < output.length && output[i].runIndex == run) {
        part.writeCharCode(output[i++].rune);
      }
      final value = part.toString();
      text.write(value);
      parts.add(HtmlDisplayTextPart(run, value, utf16Starts[start]));
    }
    final value = text.toString();
    final boundaries = <int>[0];
    for (final grapheme in value.characters) {
      boundaries.add(boundaries.last + grapheme.length);
    }
    return HtmlDisplayTextProjection._(
      value,
      List.unmodifiable(parts),
      List.unmodifiable(output),
      List.unmodifiable(utf16Starts),
      List.unmodifiable(boundaries),
      emptySource,
      leadingBeforeSource: leadingBeforeSource,
      trailingAfterSource: trailingAfterSource,
      sourceIsOrdered: sourceIsOrdered,
      collapsibleSegmentBreakOffsets: _segmentBreakOffsets == null
          ? const []
          : List.unmodifiable(_segmentBreakOffsets!),
    );
  }
}

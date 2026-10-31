import 'package:characters/characters.dart';

enum HtmlDisplayWhiteSpace { normal, pre, preWrap, preLine }

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
  HtmlDisplayTextProjection._(
    this.text,
    this.parts,
    this._runes,
    this._utf16Starts,
    this._graphemeBoundaries,
    this._emptySource,
  );

  factory HtmlDisplayTextProjection.build(
    List<HtmlDisplayTextRun> runs, {
    int maxOutputCodeUnits = 16384,
  }) {
    if (maxOutputCodeUnits < 0) throw ArgumentError.value(maxOutputCodeUnits);
    final builder = _ProjectionBuilder(maxOutputCodeUnits);
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

  final String text;
  final List<HtmlDisplayTextPart> parts;
  final List<_ProjectedRune> _runes;
  final List<int> _utf16Starts;
  final List<int> _graphemeBoundaries;
  final int _emptySource;

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
    final before = runeIndex > 0
        ? _runes[runeIndex - 1].end
        : (_runes.isEmpty ? _emptySource : _runes.first.start);
    final after = runeIndex < _runes.length ? _runes[runeIndex].start : before;
    return HtmlProjectedSourcePosition(
      sourceRune: downstream ? after : before,
      displayUtf16: display,
      isExact: isBoundary && before == after,
    );
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
  _ProjectionBuilder(this.limit);
  final int limit;
  final output = <_ProjectedRune>[];
  final utf16Starts = <int>[0];
  _ProjectedRune? pendingSpace;
  _ProjectedRune? previousCarriageReturn;

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
        mode == HtmlDisplayWhiteSpace.preLine;
    if (hardBreak ||
        (mode != HtmlDisplayWhiteSpace.normal && value.rune == 10)) {
      pendingSpace = null;
      _emit(value);
    } else if (collapse && const {9, 10, 12, 32}.contains(value.rune)) {
      if (pendingSpace == null) {
        pendingSpace = _ProjectedRune(32, source, source + 1, runIndex);
      } else {
        pendingSpace!.end = source + 1;
      }
      if (rune == 13) previousCarriageReturn = pendingSpace;
      return;
    } else {
      final space = pendingSpace;
      if (space != null && output.isNotEmpty && output.last.rune != 10) {
        _emit(space);
      }
      pendingSpace = null;
      _emit(value);
    }
    if (rune == 13) previousCarriageReturn = value;
  }

  void _emit(_ProjectedRune rune) {
    final next = utf16Starts.last + (rune.rune > 0xffff ? 2 : 1);
    if (next > limit) throw const HtmlDisplayTextLimitException();
    output.add(rune);
    utf16Starts.add(next);
  }

  HtmlDisplayTextProjection finish(int emptySource) {
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
    );
  }
}

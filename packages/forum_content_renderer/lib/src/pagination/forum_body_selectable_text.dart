import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_prepared_text_fragment.dart';

/// Copy uses visible text units of the existing projection. Merge style seams
/// before snapping, so hidden or excluded runs cannot expose half a grapheme.
List<TextRange>? forumBodyVisibleTextRanges(
  HtmlDisplayTextProjection projection,
  List<ForumBodyParagraphRun> runs,
  int start,
  int end, {
  int? maxParts,
  bool includeAnnotations = true,
}) {
  final parts = projection.parts;
  var low = 0, high = parts.length;
  while (low < high) {
    final mid = (low + high) ~/ 2;
    if (parts[mid].utf16Start + parts[mid].text.length <= start) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  final merged = <TextRange>[];
  for (var i = low; i < parts.length && parts[i].utf16Start < end; i++) {
    if (maxParts != null && i - low >= maxParts) return null;
    final part = parts[i];
    final style = runs[part.runIndex].style;
    if (style.visibilityHidden ||
        (!includeAnnotations && style.role == ForumBodyTextRole.ruby)) {
      continue;
    }
    var from = math.max(start, part.utf16Start);
    final to = math.min(end, part.utf16Start + part.text.length);
    if (from >= to) continue;
    if (merged.lastOrNull?.end == from) from = merged.removeLast().start;
    merged.add(TextRange(start: from, end: to));
  }
  final ranges = <TextRange>[];
  for (final range in merged) {
    final from = projection.sourceAtUtf16(range.start).displayUtf16;
    final to = projection
        .sourceAtUtf16(range.end, affinity: HtmlProjectionAffinity.upstream)
        .displayUtf16;
    if (from < to) ranges.add(TextRange(start: from, end: to));
  }
  return ranges;
}

/// Display coordinates for geometry and compact UTF-16 coordinates for the
/// Flutter registrar. Neither coordinate is a persisted reading position.
final class ForumBodySelectableText {
  ForumBodySelectableText(this.projection, this.ranges);

  final HtmlDisplayTextProjection projection;
  final List<TextRange> ranges;

  int get start => ranges.first.start;
  int get end => ranges.last.end;
  int get length => offsetAt(end);

  int offsetAt(int display) {
    var offset = 0;
    for (final range in ranges) {
      if (display <= range.start) break;
      offset += math.min(range.end, display) - range.start;
    }
    return offset;
  }

  Iterable<TextRange> intersection(int start, int end) sync* {
    for (final range in ranges) {
      if (range.end <= start) continue;
      if (range.start >= end) break;
      yield TextRange(
        start: math.max(start, range.start),
        end: math.min(end, range.end),
      );
    }
  }

  String copy(int start, int end) {
    final result = StringBuffer();
    for (final range in intersection(start, end)) {
      result.write(range.textInside(projection.text));
    }
    return result.toString();
  }

  int snap(int display, {required bool forward}) {
    for (final range in ranges) {
      if (display > range.end) continue;
      if (display >= range.start) return display;
      if (forward || identical(range, ranges.first)) return range.start;
      break;
    }
    for (final range in ranges.reversed) {
      if (range.end <= display) return range.end;
    }
    return start;
  }

  int? adjacentGlyph(int display, {required bool forward}) {
    if (forward) {
      for (final range in ranges) {
        if (display < range.end) return math.max(display, range.start);
      }
    } else {
      for (final range in ranges.reversed) {
        if (display <= range.start) continue;
        return projection
            .sourceAtUtf16(
              math.min(range.end, display) - 1,
              affinity: HtmlProjectionAffinity.upstream,
            )
            .displayUtf16;
      }
    }
    return null;
  }

  int step(int display, {required bool forward, bool word = false}) {
    final glyph = adjacentGlyph(display, forward: forward);
    if (glyph == null) return forward ? end : start;
    if (word) {
      final boundary = wordAt(glyph);
      return forward ? boundary.end : boundary.start;
    }
    return forward ? _afterGlyph(glyph) : glyph;
  }

  int _afterGlyph(int glyph) =>
      projection.sourceAtUtf16(glyph + 1).displayUtf16;

  static final _word = RegExp(r'^[\p{L}\p{N}\p{M}_]+$', unicode: true);
  static final _cjk = RegExp(
    r'^[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}]',
    unicode: true,
  );

  /// A Unicode word within one uninterrupted visible span. CJK, symbols and
  /// emoji start with a single grapheme and can be extended by the user.
  TextRange wordAt(int glyph) {
    final span = ranges.firstWhere(
      (range) => range.start <= glyph && glyph < range.end,
    );
    var start = glyph;
    var end = _afterGlyph(glyph);
    bool word(int from, int to) {
      final cluster = projection.text.substring(from, to);
      return _word.hasMatch(cluster) && !_cjk.hasMatch(cluster);
    }

    if (word(start, end)) {
      while (start > span.start) {
        final previous = projection
            .sourceAtUtf16(start - 1, affinity: HtmlProjectionAffinity.upstream)
            .displayUtf16;
        if (!word(previous, start)) break;
        start = previous;
      }
      while (end < span.end) {
        final next = _afterGlyph(end);
        if (!word(end, next)) break;
        end = next;
      }
    }
    return TextRange(start: start, end: end);
  }

  static int? caretAt(ForumBodyPreparedTextFragment body, Offset point) =>
      switch (body) {
        ForumBodyPreparedParagraphFragment() =>
          body.view?.sourceAt(point).displayUtf16,
        ForumBodyPreparedInlineFragment() =>
          body.view.sourceAt(point).displayUtf16,
        ForumBodyPreparedEmphasisFragment() =>
          body.view.sourceAt(point).displayUtf16,
        ForumBodyPreparedFittedEmphasisFragment() =>
          body.view.sourceAt(point).displayUtf16,
        ForumBodyPreparedImageFragment() ||
        ForumBodyPreparedListItemFragment() => null,
      };
}

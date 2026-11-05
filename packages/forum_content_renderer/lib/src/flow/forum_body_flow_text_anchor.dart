import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../document/forum_body_document.dart';
import '../pagination/forum_body_prepared_text_fragment.dart';
import '../pagination/forum_body_text_page_binding.dart';
import '../pagination/forum_body_text_page_composer.dart';
import '../table/forum_body_table_viewport.dart';
import 'forum_body_flow_sliver.dart';

/// One grapheme in a single prepared document. Display offsets only narrow
/// the search. The destination must also prove both source boundaries.
final class ForumBodyFlowTextAnchor {
  const ForumBodyFlowTextAnchor._(
    this.identity,
    this.path,
    this.start,
    this.end,
    this.sourceStart,
    this.sourceEnd,
    this.text,
  );

  final ForumBodyIdentity identity;
  final String path;
  final int start, end, sourceStart, sourceEnd;
  final String text;

  bool matchesHint(ForumBodyTextPageFragment fragment) {
    final hint = fragment.sourceHint;
    return fragment.path == path &&
        hint != null &&
        hint.runeStart <= sourceStart &&
        hint.runeEnd >= sourceEnd &&
        fragment.coverageStartUtf16 <= start &&
        fragment.coverageEndUtf16 >= end;
  }

  /// Actual glyph bounds in page coordinates, after verifying the source.
  Rect? locate({
    required ForumBodyTextPageSnapshot snapshot,
    required int page,
    required List<ForumBodyPreparedTextFragment> fragments,
  }) {
    if (snapshot.identity != identity) return null;
    final layout = validateForumBodyPreparedTextPageBinding(
      snapshot: snapshot,
      pageIndex: page,
      layoutId: snapshot.layoutId,
      fragments: fragments,
    );
    final clip = Rect.fromLTWH(0, 0, snapshot.width, layout.usedHeight);
    for (final (index, fragment) in layout.fragments.indexed) {
      if (!matchesHint(fragment)) continue;
      final delivery = fragments[index];
      if (!delivery.isActive) continue;
      final projection = delivery.projection;
      if (end > projection.text.length ||
          projection.text.substring(start, end) != text) {
        continue;
      }
      final from = projection.sourceAtUtf16(start);
      final to = projection.sourceAtUtf16(end);
      if (!from.isExact ||
          !to.isExact ||
          from.sourceRune != sourceStart ||
          to.sourceRune != sourceEnd) {
        continue;
      }
      final bounds = _paintedGrapheme(delivery, fragment, start, end, clip);
      if (bounds != null) return bounds;
    }
    return null;
  }

  /// Takes a small, synchronous sample from actual mounted glyphs. No view,
  /// cache or native lease is retained in the returned position.
  static ({ForumBodyFlowTextAnchor anchor, Rect bounds})? firstVisible(
    ForumBodyFlowTextWindow window,
  ) {
    if (!window.isCurrent) return null;
    final point = _firstVisible(
      window.bounds,
      window.slices.map(
        (slice) => (
          snapshot: window.snapshot,
          page: slice.index,
          origin: Offset(0, slice.top),
          fragments: slice.fragments,
          areaPath: null,
        ),
      ),
    );
    return point == null ? null : (anchor: point.anchor, bounds: point.bounds);
  }

  /// A glyph from a settled cell, in the table's content coordinates.
  static ({ForumBodyFlowTextAnchor anchor, Rect bounds, String areaPath})?
  firstVisibleInTable(ForumBodyTableVisibleWindow window) {
    if (!window.isCurrent) return null;
    final point = _firstVisible(
      window.bounds,
      window.slices.map(
        (slice) => (
          snapshot: slice.area.snapshot,
          page: slice.page,
          origin: slice.bounds.topLeft,
          fragments: slice.fragments,
          areaPath: slice.area.element.path,
        ),
      ),
    );
    return point == null
        ? null
        : (
            anchor: point.anchor,
            bounds: point.bounds,
            areaPath: point.areaPath!,
          );
  }

  static ({ForumBodyFlowTextAnchor anchor, Rect bounds, String? areaPath})?
  _firstVisible(
    Rect visible,
    Iterable<
      ({
        ForumBodyTextPageSnapshot snapshot,
        int page,
        Offset origin,
        List<ForumBodyPreparedTextFragment> fragments,
        String? areaPath,
      })
    >
    pages,
  ) {
    final clock = Stopwatch()..start();
    var attempts = 0;
    for (final slice in pages) {
      final snapshot = slice.snapshot;
      final clip = visible.shift(-slice.origin);
      for (final (index, fragment) in snapshot[slice.page].fragments.indexed) {
        final path = fragment.path;
        final delivery = slice.fragments[index];
        if (path == null ||
            !delivery.isActive ||
            fragment.top >= clip.bottom ||
            fragment.top + fragment.height <= clip.top) {
          continue;
        }
        final projection = delivery.projection;
        for (final line in delivery.lines) {
          // A partially clipped row can have many glyphs outside the clip.
          // Start with a complete measured row to keep the probe bounded.
          if (line.top + fragment.top < clip.top - .001 ||
              line.bottom + fragment.top > clip.bottom + .001) {
            continue;
          }
          final start = math.max(
            line.coverageStartUtf16,
            fragment.coverageStartUtf16,
          );
          final end = math.min(
            line.coverageEndUtf16,
            fragment.coverageEndUtf16,
          );
          if (start >= end) continue;
          for (final range in projection.graphemeRanges(
            startUtf16: start,
            endUtf16: end,
          )) {
            if (++attempts > 128 ||
                (attempts % 8 == 0 && clock.elapsedMicroseconds >= 2500)) {
              return null;
            }
            final a = range.startUtf16, b = range.endUtf16;
            final from = projection.sourceAtUtf16(a);
            final to = projection.sourceAtUtf16(b);
            if (!from.isExact ||
                !to.isExact ||
                from.sourceRune >= to.sourceRune) {
              continue;
            }
            final text = projection.text.substring(a, b);
            if (text.trim().isEmpty) continue;
            final bounds = _paintedGrapheme(delivery, fragment, a, b, clip);
            if (bounds != null) {
              return (
                anchor: ForumBodyFlowTextAnchor._(
                  snapshot.identity,
                  path,
                  a,
                  b,
                  from.sourceRune,
                  to.sourceRune,
                  text,
                ),
                bounds: bounds.shift(slice.origin),
                areaPath: slice.areaPath,
              );
            }
          }
        }
      }
    }
    return null;
  }
}

Rect? _paintedGrapheme(
  ForumBodyPreparedTextFragment delivery,
  ForumBodyTextPageFragment fragment,
  int start,
  int end,
  Rect clip,
) {
  for (final part in delivery.projection.parts) {
    if (part.utf16Start >= end) break;
    if (part.utf16Start + part.text.length <= start) continue;
    if (delivery.runs[part.runIndex].style.visibilityHidden) return null;
  }
  final origin = Offset(fragment.left, fragment.top);
  final frame = clip.intersect(origin & Size(fragment.width, fragment.height));
  Rect? bounds;
  for (final glyph in delivery.glyphBoxes(start, end)) {
    final rect = glyph.toRect().shift(origin);
    if (rect.isEmpty ||
        rect.left < frame.left - .001 ||
        rect.right > frame.right + .001 ||
        rect.top < frame.top - .001 ||
        rect.bottom > frame.bottom + .001) {
      return null;
    }
    bounds = bounds?.expandToInclude(rect) ?? rect;
  }
  return bounds;
}

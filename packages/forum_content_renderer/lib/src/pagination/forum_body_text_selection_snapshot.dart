import 'dart:math' as math;
import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:html_pagination_core/html_pagination_core.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_prepared_text_fragment.dart';
import 'forum_body_text_page_composer.dart';

/// One visible local text context captured from a real prepared glyph hit.
/// Pure values only: no native handle, cache, DOM or reading authority.
final class ForumBodyTextSelectionSnapshot {
  const ForumBodyTextSelectionSnapshot._(
    this.text,
    this.position,
    this.isAnnotation,
    this.isCode,
  );
  final String text;
  final HtmlProjectedSourcePosition position;
  final bool isAnnotation;
  final bool isCode;
}

ForumBodyTextSelectionSnapshot? forumBodyTextSelectionAt({
  required ForumBodyPreparedTextFragment binding,
  required ForumBodyTextPageFragment fragment,
  required Size pageSize,
  required Offset point,
  int maxCodeUnits = 65536,
  int maxParts = 8192,
}) {
  if (maxCodeUnits <= 0 || maxParts <= 0) {
    throw ArgumentError('Invalid selection limits');
  }
  if (!binding.isActive ||
      !point.dx.isFinite ||
      !point.dy.isFinite ||
      !Rect.fromLTWH(0, 0, fragment.width, fragment.height).contains(point) ||
      !(Offset.zero & pageSize).contains(
        point + Offset(fragment.left, fragment.top),
      )) {
    return null;
  }
  final body = binding is ForumBodyPreparedListItemFragment
      ? binding.body
      : binding;
  HtmlProjectedSourcePosition? hit;
  var start = fragment.coverageStartUtf16;
  var end = fragment.coverageEndUtf16;
  ForumBodyTextRole role;
  switch (body) {
    case ForumBodyPreparedImageFragment():
      return null;
    case ForumBodyPreparedListItemFragment():
      return null;
    case ForumBodyPreparedParagraphFragment():
      hit = body.view?.sourceAt(point);
      role = body.lease.content.style.role;
    case ForumBodyPreparedInlineFragment():
      final actual = body.view.sourceHitAt(point);
      final window = actual.window;
      if (window == null) return null;
      hit = actual.position;
      start = math.max(start, window.startUtf16);
      end = math.min(end, window.endUtf16);
      role = window.content.style.role;
    case ForumBodyPreparedEmphasisFragment():
      hit = body.view.sourceAt(point);
      role = body.view.input.paragraph.content.style.role;
    case ForumBodyPreparedFittedEmphasisFragment():
      hit = body.view.sourceAt(point);
      role = body.plan.content.style.role;
  }
  if (hit == null || !hit.isExact || start >= end) return null;
  final projection = body.projection;
  final ranges = _visibleRanges(projection, body.runs, start, end, maxParts);
  if (ranges == null || ranges.isEmpty) return null;
  final caret = hit.displayUtf16;
  if (caret < start || caret > end) return null;
  final candidates = <({int start, int end})>[
    if (caret < end)
      (start: caret, end: projection.sourceAtUtf16(caret + 1).displayUtf16),
    if (caret > start)
      (
        start: projection
            .sourceAtUtf16(caret - 1, affinity: HtmlProjectionAffinity.upstream)
            .displayUtf16,
        end: caret,
      ),
  ];
  var glyphHit = false;
  for (final candidate in candidates) {
    if (!ranges.any(
      (r) => r.start <= candidate.start && r.end >= candidate.end,
    )) {
      continue;
    }
    for (final box in body.glyphBoxes(candidate.start, candidate.end)) {
      final rect = Rect.fromLTRB(box.left, box.top, box.right, box.bottom);
      final clip = Rect.fromLTWH(0, 0, fragment.width, fragment.height)
          .intersect(
            Rect.fromLTWH(
              -fragment.left,
              -fragment.top,
              pageSize.width,
              pageSize.height,
            ),
          );
      if (rect.contains(point) &&
          rect.left >= clip.left - precisionErrorTolerance &&
          rect.right <= clip.right + precisionErrorTolerance &&
          rect.top >= clip.top - precisionErrorTolerance &&
          rect.bottom <= clip.bottom + precisionErrorTolerance) {
        glyphHit = true;
        break;
      }
    }
    if (glyphHit) break;
  }
  if (!glyphHit) return null;
  var length = 0;
  for (final r in ranges) {
    length += r.end - r.start;
    if (length > maxCodeUnits) return null;
  }
  final text = StringBuffer();
  for (final r in ranges) {
    text.write(projection.text.substring(r.start, r.end));
  }
  return ForumBodyTextSelectionSnapshot._(
    text.toString(),
    hit,
    role == ForumBodyTextRole.ruby,
    role == ForumBodyTextRole.code,
  );
}

/// Merge visible style seams before snapping to complete display graphemes.
/// A hidden interior cannot leave a copied half-emoji or combining sequence.
List<({int start, int end})>? _visibleRanges(
  HtmlDisplayTextProjection projection,
  List<ForumBodyParagraphRun> runs,
  int start,
  int end,
  int maxParts,
) {
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
  final raw = <({int start, int end})>[];
  var checked = 0;
  for (var i = low; i < parts.length && parts[i].utf16Start < end; i++) {
    if (++checked > maxParts) return null;
    final part = parts[i];
    if (runs[part.runIndex].style.visibilityHidden) continue;
    final from = math.max(start, part.utf16Start);
    final to = math.min(end, part.utf16Start + part.text.length);
    if (from >= to) continue;
    if (raw.isNotEmpty && raw.last.end == from) {
      raw[raw.length - 1] = (start: raw.last.start, end: to);
    } else {
      raw.add((start: from, end: to));
    }
  }
  return [
    for (final r in raw)
      if (projection.sourceAtUtf16(r.start).displayUtf16 <
          projection
              .sourceAtUtf16(r.end, affinity: HtmlProjectionAffinity.upstream)
              .displayUtf16)
        (
          start: projection.sourceAtUtf16(r.start).displayUtf16,
          end: projection
              .sourceAtUtf16(r.end, affinity: HtmlProjectionAffinity.upstream)
              .displayUtf16,
        ),
  ];
}

import 'dart:math' as math;
import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_prepared_text_fragment.dart';
import 'forum_body_text_glyph_hit.dart';
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
  final hit = ForumBodyTextGlyphHit.at(
    binding: binding,
    fragment: fragment,
    pageSize: pageSize,
    point: point,
  );
  if (hit == null) return null;
  final projection = hit.body.projection;
  final ranges = _visibleRanges(
    projection,
    hit.body.runs,
    hit.start,
    hit.end,
    maxParts,
  );
  if (ranges == null || ranges.isEmpty) return null;
  if (!hit.paintedRanges.any(
    (glyph) => ranges.any((r) => r.start <= glyph.start && r.end >= glyph.end),
  )) {
    return null;
  }
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
    hit.position,
    hit.role == ForumBodyTextRole.ruby,
    hit.role == ForumBodyTextRole.code,
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

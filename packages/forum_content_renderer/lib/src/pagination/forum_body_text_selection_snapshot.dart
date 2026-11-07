import 'package:flutter/painting.dart';
import 'package:forum_content_renderer/forum_text.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_prepared_text_fragment.dart';
import 'forum_body_selectable_text.dart';
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
    requireExactSource: false,
  );
  // A ruby window can own the painted glyph even when its caret borders
  // nonadjacent raw source runs. Copy uses that window and the glyph proof
  // below while keeping the original source precision in the snapshot.
  if (hit == null ||
      (!hit.position.isExact && hit.role != ForumBodyTextRole.ruby)) {
    return null;
  }
  final projection = hit.body.projection;
  final ranges = forumBodyVisibleTextRanges(
    projection,
    hit.body.runs,
    hit.start,
    hit.end,
    maxParts: maxParts,
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

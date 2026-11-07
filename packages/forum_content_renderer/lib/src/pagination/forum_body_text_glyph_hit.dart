import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/painting.dart';
import 'package:forum_content_renderer/forum_text.dart';

import '../style/forum_body_style_options.dart';
import 'forum_body_prepared_text_fragment.dart';
import 'forum_body_text_page_composer.dart';

/// A caret in the actual painted context. The two adjacent display graphemes
/// may belong to different runs, so the caret alone cannot identify a link.
final class ForumBodyTextGlyphHit {
  const ForumBodyTextGlyphHit._(
    this.body,
    this.position,
    this.start,
    this.end,
    this.role,
    this._point,
    this._clip,
  );

  final ForumBodyPreparedTextFragment body;
  final HtmlProjectedSourcePosition position;
  final int start;
  final int end;
  final ForumBodyTextRole role;
  final Offset _point;
  final Rect _clip;

  static ForumBodyTextGlyphHit? at({
    required ForumBodyPreparedTextFragment binding,
    required ForumBodyTextPageFragment fragment,
    required Size pageSize,
    required Offset point,
    bool requireExactSource = true,
  }) {
    final clip = Rect.fromLTWH(0, 0, fragment.width, fragment.height).intersect(
      Rect.fromLTWH(
        -fragment.left,
        -fragment.top,
        pageSize.width,
        pageSize.height,
      ),
    );
    if (!binding.isActive || !point.isFinite || !clip.contains(point)) {
      return null;
    }
    final body = binding is ForumBodyPreparedListItemFragment
        ? binding.body
        : binding;
    HtmlProjectedSourcePosition? position;
    var start = fragment.coverageStartUtf16;
    var end = fragment.coverageEndUtf16;
    ForumBodyTextRole role;
    switch (body) {
      case ForumBodyPreparedHiddenImageFragment():
      case ForumBodyPreparedImageFragment():
      case ForumBodyPreparedListItemFragment():
        return null;
      case ForumBodyPreparedParagraphFragment():
        position = body.view?.sourceAt(point);
        role = body.lease.content.style.role;
      case ForumBodyPreparedInlineFragment():
        final actual = body.view.sourceHitAt(point);
        final window = actual.window;
        if (window == null) return null;
        position = actual.position;
        start = math.max(start, window.startUtf16);
        end = math.min(end, window.endUtf16);
        role = window.content.style.role;
      case ForumBodyPreparedEmphasisFragment():
        position = body.view.sourceAt(point);
        role = body.view.input.paragraph.content.style.role;
    }
    if (position == null ||
        (requireExactSource && !position.isExact) ||
        start >= end ||
        position.displayUtf16 < start ||
        position.displayUtf16 > end) {
      return null;
    }
    return ForumBodyTextGlyphHit._(
      body,
      position,
      start,
      end,
      role,
      point,
      clip,
    );
  }

  Iterable<({int start, int end})> get paintedRanges sync* {
    final caret = position.displayUtf16;
    final projection = body.projection;
    final candidates = [
      if (caret < end)
        (start: caret, end: projection.sourceAtUtf16(caret + 1).displayUtf16),
      if (caret > start)
        (
          start: projection
              .sourceAtUtf16(
                caret - 1,
                affinity: HtmlProjectionAffinity.upstream,
              )
              .displayUtf16,
          end: caret,
        ),
    ];
    for (final range in candidates) {
      if (range.start < start || range.end > end || range.start >= range.end) {
        continue;
      }
      for (final box in body.glyphBoxes(range.start, range.end)) {
        final rect = box.toRect();
        if (rect.contains(_point) &&
            rect.left >= _clip.left - precisionErrorTolerance &&
            rect.right <= _clip.right + precisionErrorTolerance &&
            rect.top >= _clip.top - precisionErrorTolerance &&
            rect.bottom <= _clip.bottom + precisionErrorTolerance) {
          yield range;
          break;
        }
      }
    }
  }

  String? get linkTarget {
    final parts = body.projection.parts;
    String? link;
    for (final range in paintedRanges) {
      var low = 0, high = parts.length;
      while (low < high) {
        final mid = (low + high) ~/ 2;
        if (parts[mid].utf16Start + parts[mid].text.length <= range.start) {
          low = mid + 1;
        } else {
          high = mid;
        }
      }
      String? target;
      for (
        var i = low;
        i < parts.length && parts[i].utf16Start < range.end;
        i++
      ) {
        final style = body.runs[parts[i].runIndex].style;
        final next = style.linkTarget;
        if (style.visibilityHidden ||
            next == null ||
            next.trim().isEmpty ||
            (target != null && target != next)) {
          return null;
        }
        target = next;
      }
      if (link != null && link != target) return null;
      link = target;
    }
    return link;
  }
}

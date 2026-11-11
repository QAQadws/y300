import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show WidgetSpan;

/// Local UTF-16 paint ranges, never HTML coordinates or reading anchors.
class ForumHtmlInlineBackgroundRange {
  const ForumHtmlInlineBackgroundRange(this.start, this.end, this.color);

  final int start;
  final int end;
  final Color color;
}

class ForumHtmlInlineBackgroundPlan {
  ForumHtmlInlineBackgroundPlan._(this.text, this.ranges);

  final InlineSpan text;
  final List<ForumHtmlInlineBackgroundRange> ranges;

  static ForumHtmlInlineBackgroundPlan? prepare(InlineSpan text) {
    final builder = _BackgroundPlanBuilder();
    final rewritten = builder.rewrite(text, null, null);
    if (builder.unsupported || builder.ranges.isEmpty) return null;
    return ForumHtmlInlineBackgroundPlan._(
      rewritten,
      List.unmodifiable(builder.ranges),
    );
  }
}

class _BackgroundPlanBuilder {
  final ranges = <ForumHtmlInlineBackgroundRange>[];
  var offset = 0;
  var unsupported = false;

  InlineSpan rewrite(
    InlineSpan span,
    Color? inherited,
    Color? inheritedForeground,
  ) {
    // Inline widgets keep their identity and occupy one paragraph placeholder.
    // Their own text is painted by their own renderer, not the outer paragraph.
    if (span is WidgetSpan) {
      offset++;
      return span;
    }
    if (span.runtimeType != TextSpan) {
      unsupported = true;
      return span;
    }
    final text = span as TextSpan;
    final style = text.style;
    final background = style?.background;
    // fwfh emits solid fills. Preserve unfamiliar paint effects as-is rather
    // than silently replacing a shader, filter or blend with a flat color.
    if (background != null &&
        (background.shader != null ||
            background.colorFilter != null ||
            background.maskFilter != null ||
            background.imageFilter != null ||
            background.blendMode != BlendMode.srcOver ||
            background.style != PaintingStyle.fill)) {
      unsupported = true;
      return span;
    }
    final ownColor = background?.color ?? style?.backgroundColor;
    final effective = ownColor ?? (style?.inherit == false ? null : inherited);
    final foreground =
        style?.foreground?.color ??
        style?.color ??
        (style?.inherit == false ? null : inheritedForeground);
    final length = text.text?.length ?? 0;
    if (length > 0 &&
        effective != null &&
        foreground?.toARGB32() == effective.toARGB32()) {
      // Author-concealed text must stay concealed. Rounding just its background
      // can expose the glyphs at the cut-out corners, so keep this paragraph native.
      unsupported = true;
      return span;
    }
    if (length > 0 && effective != null && effective.a > 0) {
      final end = offset + length;
      if (ranges.isNotEmpty &&
          ranges.last.end == offset &&
          ranges.last.color.toARGB32() == effective.toARGB32()) {
        final previous = ranges.removeLast();
        ranges.add(
          ForumHtmlInlineBackgroundRange(previous.start, end, effective),
        );
      } else {
        ranges.add(ForumHtmlInlineBackgroundRange(offset, end, effective));
      }
    }
    offset += length;
    final children = text.children;
    final rewrittenChildren = children
        ?.map((child) => rewrite(child, effective, foreground))
        .toList(growable: false);
    final changedChildren =
        children != null &&
        children.indexed.any(
          (entry) => !identical(entry.$2, rewrittenChildren![entry.$1]),
        );
    if (ownColor == null && !changedChildren) return text;

    return TextSpan(
      text: text.text,
      // copyWith(null) cannot clear Paint. A transparent override suppresses
      // the native rectangles while retaining every metric-affecting field.
      style: ownColor == null
          ? style
          : style!.copyWith(
              background: Paint()..color = const Color(0x00000000),
            ),
      children: rewrittenChildren,
      recognizer: text.recognizer,
      mouseCursor: text.mouseCursor,
      onEnter: text.onEnter,
      onExit: text.onExit,
      semanticsLabel: text.semanticsLabel,
      semanticsIdentifier: text.semanticsIdentifier,
      locale: text.locale,
      spellOut: text.spellOut,
    );
  }
}

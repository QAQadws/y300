import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show OrdinalSortKey;
import 'package:flutter/services.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../style/forum_body_style_options.dart';
import 'forum_body_prepared_text_fragment.dart';
import 'forum_body_text_page_composer.dart';

/// Gives links their own native semantics and focus using the mounted text's
/// geometry. The original Surface still owns painting and pointer gestures.
final class ForumBodyTextPageSemantics extends StatefulWidget {
  const ForumBodyTextPageSemantics({
    required this.binding,
    required this.fragment,
    required this.pageSize,
    required this.identity,
    required this.onLinkTap,
    required this.buildSurface,
    super.key,
  });

  final ForumBodyPreparedTextFragment binding;
  final ForumBodyTextPageFragment fragment;
  final Size pageSize;
  final Object identity;
  final ValueChanged<String>? onLinkTap;
  final Widget Function(bool excludeTextSemantics) buildSurface;

  static bool hasLink(
    ForumBodyPreparedTextFragment binding,
    ForumBodyTextPageFragment fragment,
  ) {
    if (!binding.isActive) return false;
    final parts = binding.projection.parts;
    final end = fragment.coverageEndUtf16;
    for (
      var i = _partAt(parts, fragment.coverageStartUtf16);
      i < parts.length && parts[i].utf16Start < end;
      i++
    ) {
      final style = binding.runs[parts[i].runIndex].style;
      if (!style.visibilityHidden && _linkTarget(style) != null) return true;
    }
    return false;
  }

  @override
  State<ForumBodyTextPageSemantics> createState() => _TextPageSemanticsState();
}

final class _TextPageSemanticsState extends State<ForumBodyTextPageSemantics> {
  late List<_TextSpan> _spans;
  late Object _generation;

  void _prepare() {
    _generation = Object();
    _spans = widget.onLinkTap == null
        ? const []
        : _linkSpans(widget.binding, widget.fragment, widget.pageSize);
  }

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(ForumBodyTextPageSemantics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity ||
        oldWidget.pageSize != widget.pageSize ||
        (oldWidget.onLinkTap == null) != (widget.onLinkTap == null)) {
      _prepare();
    }
  }

  @override
  Widget build(BuildContext context) {
    final generation = _generation;
    void activate(String target) {
      if (mounted &&
          identical(generation, _generation) &&
          widget.binding.isActive) {
        widget.onLinkTap?.call(target);
      }
    }

    // Keep the painted subtree in the same slot when interactivity changes.
    // A remount would dispose the prepared text lease still used by this view.
    return Semantics(
      container: _spans.isNotEmpty,
      explicitChildNodes: _spans.isNotEmpty,
      child: FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: widget.buildSurface(_spans.isNotEmpty)),
            for (final span in _spans)
              Positioned.fromRect(
                key: ValueKey((generation, span.start)),
                rect: span.bounds,
                child: Semantics(
                  container: true,
                  label: span.label,
                  textDirection: span.style.direction,
                  header: span.style.heading,
                  link: span.style.target != null,
                  sortKey: OrdinalSortKey(span.start.toDouble()),
                  onTap: span.style.target == null
                      ? null
                      : () => activate(span.style.target!),
                  child: span.style.target == null
                      ? const SizedBox.expand()
                      : _LinkFocus(
                          onActivate: () => activate(span.style.target!),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

final class _LinkFocus extends StatelessWidget {
  const _LinkFocus({required this.onActivate});

  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter ||
              event.logicalKey == LogicalKeyboardKey.space)) {
        onActivate();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Builder(
      builder: (context) => IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Focus.of(context).hasFocus
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  )
                : null,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

typedef _SpanStyle = ({
  String? target,
  String? anchor,
  TextDirection direction,
  bool heading,
});

typedef _TextSpan = ({int start, _SpanStyle style, Rect bounds, String label});

List<_TextSpan> _linkSpans(
  ForumBodyPreparedTextFragment binding,
  ForumBodyTextPageFragment fragment,
  Size pageSize,
) {
  if (!binding.isActive) return const [];
  final projection = binding.projection;
  final parts = projection.parts;
  final start = fragment.coverageStartUtf16;
  final end = fragment.coverageEndUtf16;
  final ranges = <({int start, int end, _SpanStyle style})>[];
  for (
    var i = _partAt(parts, start);
    i < parts.length && parts[i].utf16Start < end;
    i++
  ) {
    final part = parts[i];
    final run = binding.runs[part.runIndex];
    if (run.style.visibilityHidden) continue;
    final target = _linkTarget(run.style);
    final style = (
      target: target,
      anchor: target == null ? null : run.style.linkPath ?? run.path,
      direction: run.style.textDirection,
      heading: run.style.role == ForumBodyTextRole.heading,
    );
    var from = math.max(start, part.utf16Start);
    final to = math.min(end, part.utf16Start + part.text.length);
    final previous = ranges.lastOrNull;
    if (previous?.end == from && previous?.style == style) {
      from = ranges.removeLast().start;
    }
    ranges.add((start: from, end: to, style: style));
  }

  final clip = Rect.fromLTWH(0, 0, fragment.width, fragment.height).intersect(
    Rect.fromLTWH(
      -fragment.left,
      -fragment.top,
      pageSize.width,
      pageSize.height,
    ),
  );
  final spans = <_TextSpan>[];
  for (final range in ranges) {
    final label = projection.text.substring(range.start, range.end);
    if (label.trim().isEmpty) continue;
    Rect? bounds;
    for (final box in binding.glyphBoxes(range.start, range.end)) {
      final visible = box.toRect().intersect(clip);
      if (visible.isEmpty) continue;
      bounds = bounds?.expandToInclude(visible) ?? visible;
    }
    if (bounds != null) {
      spans.add((
        start: range.start,
        style: range.style,
        bounds: bounds,
        label: label,
      ));
    }
  }
  return spans;
}

String? _linkTarget(ForumBodyResolvedStyle style) {
  final href = style.linkTarget;
  return href != null && href.trim().isNotEmpty ? href : null;
}

int _partAt(List<HtmlDisplayTextPart> parts, int offset) {
  var low = 0, high = parts.length;
  while (low < high) {
    final mid = (low + high) ~/ 2;
    if (parts[mid].utf16Start + parts[mid].text.length <= offset) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}

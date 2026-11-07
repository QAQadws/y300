import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show OrdinalSortKey;
import 'package:flutter/services.dart';
import 'package:forum_content_renderer/forum_text.dart';

import '../style/forum_body_style_options.dart';
import 'forum_body_prepared_text_fragment.dart';
import 'forum_body_text_page_composer.dart';

/// Orders visible text and resources by display position and exposes link
/// actions. The original Surface owns painting and pointer gestures.
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
  final Widget Function(bool excludeTextSemantics, Map<int, double> imageOrder)
  buildSurface;

  static bool needsStructuredSemantics(
    ForumBodyPreparedTextFragment binding,
    ForumBodyTextPageFragment fragment,
  ) {
    if (!binding.isActive) return false;
    if (binding.imageCount > 0) return true;
    final parts = binding.projection.parts;
    final end = fragment.coverageEndUtf16;
    // A run-table read checks the whole inline view. Borrow it once for this
    // synchronous scan of the prepared styles.
    final runs = binding.runs;
    for (
      var i = _partAt(parts, fragment.coverageStartUtf16);
      i < parts.length && parts[i].utf16Start < end;
      i++
    ) {
      final style = runs[parts[i].runIndex].style;
      if (!style.visibilityHidden && _linkTarget(style) != null) return true;
    }
    return false;
  }

  @override
  State<ForumBodyTextPageSemantics> createState() => _TextPageSemanticsState();
}

final class _TextPageSemanticsState extends State<ForumBodyTextPageSemantics> {
  late List<_TextSpan> _spans;
  late Map<int, double> _imageOrder;
  late Object _generation;

  void _prepare() {
    _generation = Object();
    final body = widget.binding;
    final text = body is ForumBodyPreparedListItemFragment ? body.body : body;
    final fences = <int>{};
    _imageOrder = {};
    if (text case ForumBodyPreparedInlineFragment(
      :final view,
    ) when text.isActive) {
      final images = view.images.keys.toList()..sort();
      for (final (index, atom) in images.indexed) {
        final offset = view.content.projection.atoms[atom].displayStartUtf16;
        fences.add(offset);
        // Text beginning at the same fence follows all its image slots.
        _imageOrder[atom] = offset + (index + 1) / (2 * (images.length + 1));
      }
    }
    _spans = widget.onLinkTap == null && fences.isEmpty
        ? const []
        : _textSpans(
            body,
            widget.fragment,
            widget.pageSize,
            fences.toList(),
            linksEnabled: widget.onLinkTap != null,
          );
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
    final structured = _spans.isNotEmpty || _imageOrder.isNotEmpty;
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
      container: structured,
      explicitChildNodes: structured,
      child: FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: widget.buildSurface(structured, _imageOrder),
            ),
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
                  sortKey: OrdinalSortKey(span.start + .5),
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

List<_TextSpan> _textSpans(
  ForumBodyPreparedTextFragment binding,
  ForumBodyTextPageFragment fragment,
  Size pageSize,
  List<int> fences, {
  required bool linksEnabled,
}) {
  if (!binding.isActive) return const [];
  final projection = binding.projection;
  final parts = projection.parts;
  final runs = binding.runs;
  final start = fragment.coverageStartUtf16;
  final end = fragment.coverageEndUtf16;
  final ranges = <({int start, int end, _SpanStyle style})>[];
  for (
    var i = _partAt(parts, start);
    i < parts.length && parts[i].utf16Start < end;
    i++
  ) {
    final part = parts[i];
    final run = runs[part.runIndex];
    if (run.style.visibilityHidden) continue;
    final target = linksEnabled ? _linkTarget(run.style) : null;
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
  void addVisibleSpan(int start, int end, _SpanStyle style) {
    final label = projection.text.substring(start, end);
    if (label.trim().isEmpty) return;
    Rect? bounds;
    for (final box in binding.glyphBoxes(start, end)) {
      final visible = box.toRect().intersect(clip);
      if (visible.isEmpty) continue;
      bounds = bounds?.expandToInclude(visible) ?? visible;
    }
    if (bounds != null) {
      spans.add((start: start, style: style, bounds: bounds, label: label));
    }
  }

  void addSpan(int start, int endOffset, _SpanStyle style) {
    final from = projection.sourceAtUtf16(start).displayUtf16;
    final to = projection
        .sourceAtUtf16(endOffset, affinity: HtmlProjectionAffinity.upstream)
        .displayUtf16;
    if (from < to) addVisibleSpan(from, to, style);
    if (to < from || to == endOffset) return;
    final boundary = projection.sourceAtUtf16(endOffset).displayUtf16;
    if (boundary > end) return;
    // A style seam can bisect an extended grapheme. Announce it once as
    // plain text, provided no part of that grapheme is hidden.
    for (
      var i = _partAt(parts, to);
      i < parts.length && parts[i].utf16Start < boundary;
      i++
    ) {
      if (binding.runs[parts[i].runIndex].style.visibilityHidden) return;
    }
    addVisibleSpan(to, boundary, (
      target: null,
      anchor: null,
      direction: style.direction,
      heading: style.heading,
    ));
  }

  var fence = 0;
  for (final range in ranges) {
    var from = range.start;
    while (fence < fences.length && fences[fence] <= from) {
      fence++;
    }
    while (fence < fences.length && fences[fence] < range.end) {
      final at = fences[fence++];
      addSpan(from, at, range.style);
      from = at;
    }
    addSpan(from, range.end, range.style);
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

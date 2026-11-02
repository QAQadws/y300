import 'dart:collection';

import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_paragraph_layout.dart'
    show ForumBodyParagraphLayoutException, ForumBodyParagraphLayoutFailure;
import '../paragraph/forum_body_text_request_preparation.dart';
import '../paragraph/forum_body_native_request.dart';
import '../pagination/forum_body_inline_page_preparation.dart';
import 'forum_body_inline_paragraph_view.dart';
import 'forum_body_inline_span_content.dart';
import 'forum_body_ruby_container_background.dart';
import 'forum_body_ruby_group_contract.dart';
import 'forum_body_ruby_group_metrics.dart';
import 'forum_body_ruby_group_preparation.dart';
import 'forum_body_ruby_hit_band.dart';
import 'forum_body_ruby_tree_input.dart';
import 'forum_body_ruby_segment_hit_route.dart';
import 'forum_body_ruby_tree_metrics_preparation.dart';

part 'forum_body_ruby_tree_preparation.dart';

final class ForumBodyRubyTreeMember {
  const ForumBodyRubyTreeMember._(
    this.nodeIndex,
    this.content,
    this.lease,
    this.offset,
  ) : inlineView = null,
      inlineWindow = null;
  const ForumBodyRubyTreeMember._inline(
    this.nodeIndex,
    this.content,
    this.inlineView,
    this.inlineWindow,
    this.offset,
  ) : lease = null;
  final int nodeIndex;
  final ForumBodyParagraphContent content;
  final ForumBodyTextLease? lease;
  final Offset offset;
  final ForumBodyInlineParagraphView? inlineView;
  final ForumBodyInlineContext? inlineWindow;
}

typedef ForumBodyRubyTreeHit = ({
  int nodeIndex,
  ForumBodyParagraphContent content,
  HtmlProjectedSourcePosition position,
});

/// A current same-owner native binding of a complete measured tree. It owns
/// only real leaf leases; auxiliary container fonts remain numeric snapshots.
/// Parent windows/page coverage must still bind each original member explicitly.
final class ForumBodyRubyTreeLayout {
  ForumBodyRubyTreeLayout._({
    required this.input,
    required this.metrics,
    required List<ForumBodyRubyTreeMember> members,
    required Map<int, ForumBodyRubyTreeMember> byNode,
    required Map<int, bool> hasText,
    required Map<int, ForumBodyInlineParagraphView> inlineViews,
    required Map<int, Map<ForumBodyParagraphContent, int>> inlineIds,
    required List<({int id, Offset offset})> paintNodes,
    required List<({Rect rect, ForumBodyRubyContainerFontBox font})>
    backgrounds,
  }) : _members = UnmodifiableListView(members),
       _byNode = UnmodifiableMapView(byNode),
       _hasText = UnmodifiableMapView(hasText),
       _inlineViews = UnmodifiableMapView(inlineViews),
       _inlineIds = UnmodifiableMapView(inlineIds),
       _paintNodes = UnmodifiableListView(paintNodes),
       backgrounds = UnmodifiableListView(backgrounds);
  final ForumBodyRubyTreeInput input;
  final ForumBodyRubyTreeMetrics metrics;
  List<ForumBodyRubyTreeMember> _members;
  Map<int, ForumBodyRubyTreeMember> _byNode;
  final Map<int, bool> _hasText;
  Map<int, ForumBodyInlineParagraphView> _inlineViews;
  final Map<int, Map<ForumBodyParagraphContent, int>> _inlineIds;
  List<({int id, Offset offset})> _paintNodes;
  final List<({Rect rect, ForumBodyRubyContainerFontBox font})> backgrounds;
  bool _closed = false;
  List<ForumBodyRubyTreeMember> get members => _members;
  Size get size => metrics.box.bounds.size;
  double get baseline => metrics.box.alphabeticBaseline;
  bool get isActive =>
      !_closed &&
      _inlineViews.values.every((view) => view.isActive) &&
      _members.every(
        (member) =>
            member.lease == null ||
            (member.lease!.isActive && member.lease!.layout.isPaintPrepared),
      );
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    for (final member in _members) ?member.lease,
    for (final view in _inlineViews.values) ...view.nativeLeases,
  ];
  bool isOwnedBy(ForumBodyParagraphCache cache) =>
      isActive && nativeLeases.every(cache.ownsLease);

  /// Glyph plane only. The page draws ALL container backgrounds before ANY
  /// glyph; interleaving nested backgrounds with text would cover earlier ink.
  void paint(Canvas canvas, Offset offset) {
    _ensureActive();
    for (final item in _paintNodes) {
      final view = _inlineViews[item.id];
      if (view != null) {
        view.paint(canvas, offset + item.offset, paintBackgrounds: false);
      } else {
        _byNode[item.id]!.lease?.layout.paint(canvas, offset + item.offset);
      }
    }
  }

  /// Standalone component helper; page integration consumes the same prepared
  /// regions. Clipping is explicit and belongs to the actual destination page.
  void paintBackgrounds(Canvas canvas, Offset offset, {required Rect clip}) {
    _ensureActive();
    canvas.save();
    try {
      canvas.clipRect(clip);
      for (final background in backgrounds) {
        canvas.drawRect(
          background.rect.shift(offset),
          Paint()..color = background.font.background.color,
        );
      }
    } finally {
      canvas.restore();
    }
  }

  ForumBodyRubyTreeHit sourceAt(Offset offset) {
    _ensureActive();
    if (!offset.dx.isFinite || !offset.dy.isFinite) {
      throw ArgumentError.value(offset);
    }
    var id = input.root;
    var point = offset;
    var approximate = !(Offset.zero & size).contains(point);
    while (true) {
      final node = input.nodes[id];
      final numeric = metrics.nodes[id];
      switch (node) {
        case ForumBodyRubyTreeSegment():
          final box = numeric as ForumBodyRubyTreeContainerMetrics;
          final segment = box.segment!;
          point -= Offset(0, box.frame.childTop);
          if (!(Offset.zero & segment.size).contains(point)) approximate = true;
          final route = resolveForumBodyRubySegmentHitRoute(
            metrics: segment,
            point: point,
            spanRanks: node.spanRanks,
            annotationGapRanks: node.annotationGapRanks,
            baseHasText: (column) => _hasText[node.bases[column]]!,
          );
          if (route.forced) approximate = true;
          if (route.annotationGapIndex case final gap?) {
            id = node.annotationGaps[gap].child;
            point -= segment.annotationGaps[gap].offset;
          } else if (route.spanIndex case final span?) {
            id = node.spans[span].child;
            point -= segment.spans[span].offset;
          } else if (route.gapIndex case final gap?) {
            id = node.gaps[gap].child;
            point -=
                segment.gaps[gap].offset + segment.gaps[gap].font.baseOffset;
          } else {
            final column = route.columnIndex;
            id = node.bases[column];
            point -=
                segment.columnOffsets[column] +
                segment.columns[column].baseOffset;
          }
        case ForumBodyRubyTreeInline():
          final box = numeric as ForumBodyRubyTreeContainerMetrics;
          point -= Offset(0, box.frame.childTop);
          final view = _inlineViews[id]!;
          final bound = view.sourceHitAt(point);
          final hit = bound.position;
          if (bound.window case final window?) {
            final local = hit.displayUtf16 - window.startUtf16;
            final projected = window.content.projection.sourceAtUtf16(local);
            return (
              nodeIndex: _inlineIds[id]![window.content]!,
              content: window.content,
              position: HtmlProjectedSourcePosition(
                sourceRune: hit.sourceRune,
                displayUtf16: local,
                isExact:
                    !approximate &&
                    hit.isExact &&
                    projected.isExact &&
                    hit.sourceRune == projected.sourceRune,
              ),
            );
          }
          final windows = view.content.contexts;
          var low = 0, high = windows.length;
          while (low < high) {
            final mid = (low + high) ~/ 2;
            if (windows[mid].endUtf16 < hit.displayUtf16) {
              low = mid + 1;
            } else {
              high = mid;
            }
          }
          ForumBodyInlineContext? chosen;
          var exact = false;
          for (
            var i = low;
            i < windows.length && windows[i].startUtf16 <= hit.displayUtf16;
            i++
          ) {
            final window = windows[i];
            chosen ??= window;
            final local = hit.displayUtf16 - window.startUtf16;
            final projected = window.content.projection.sourceAtUtf16(local);
            if (window.startUtf16 < window.endUtf16 &&
                projected.sourceRune == hit.sourceRune) {
              chosen = window;
              exact = projected.isExact;
              break;
            }
          }
          if (chosen == null) {
            throw StateError('Inline hit has no actual source window');
          }
          return (
            nodeIndex: _inlineIds[id]![chosen.content]!,
            content: chosen.content,
            position: HtmlProjectedSourcePosition(
              sourceRune: hit.sourceRune,
              displayUtf16: hit.displayUtf16 - chosen.startUtf16,
              isExact: !approximate && hit.isExact && exact,
            ),
          );
        case ForumBodyRubyTreeText():
          final member = _byNode[id]!;
          final hit =
              member.lease?.layout.sourceAt(point) ??
              node.content.projection.sourceAtUtf16(0);
          if (member.lease == null || !_hasText[id]!) approximate = true;
          return (
            nodeIndex: id,
            content: node.content,
            position: approximate
                ? HtmlProjectedSourcePosition(
                    sourceRune: hit.sourceRune,
                    displayUtf16: hit.displayUtf16,
                    isExact: false,
                  )
                : hit,
          );
        case ForumBodyRubyTreeFrame():
          final box = numeric as ForumBodyRubyTreeContainerMetrics;
          point -= Offset(0, box.frame.childTop);
          if (!metrics.nodes[node.child].box!.bounds.contains(point)) {
            approximate = true;
          }
          id = node.child;
        case ForumBodyRubyTreeGroup():
          final box = numeric as ForumBodyRubyTreeContainerMetrics;
          final group = box.group!;
          point -= Offset(0, box.frame.childTop);
          if (!(Offset.zero & group.size).contains(point)) approximate = true;
          final band = resolveForumBodyRubyHitBand(
            metrics: group,
            y: point.dy,
            baseHasText: _hasText[node.base]!,
            annotationHasText: (rank) {
              final child = node.annotations[rank].child;
              return child != null && _hasText[child]!;
            },
          );
          if (band.forced) approximate = true;
          if (band.annotationIndex < 0) {
            id = node.base;
            point -= group.baseOffset;
          } else {
            id = node.annotations[band.annotationIndex].child!;
            point -= group.annotations[band.annotationIndex].offset;
          }
      }
    }
  }

  List<TextBox> selectionBoxes({
    required int nodeIndex,
    required int startUtf16,
    required int endUtf16,
    bool paintedOnly = false,
  }) {
    _ensureActive();
    final member = _byNode[nodeIndex];
    if (member == null) throw ArgumentError.value(nodeIndex, 'nodeIndex');
    RangeError.checkValidRange(
      startUtf16,
      endUtf16,
      member.content.projection.text.length,
    );
    final inline = member.inlineView;
    final boxes = inline == null
        ? member.lease?.layout.selectionBoxes(startUtf16, endUtf16) ??
              const <TextBox>[]
        : paintedOnly
        ? inline.glyphBoxes(
            member.inlineWindow!.startUtf16 + startUtf16,
            member.inlineWindow!.startUtf16 + endUtf16,
          )
        : inline.selectionBoxes(
            member.inlineWindow!.startUtf16 + startUtf16,
            member.inlineWindow!.startUtf16 + endUtf16,
            clipToView: false,
          );
    return [
      for (final box in boxes)
        TextBox.fromLTRBD(
          box.left + member.offset.dx,
          box.top + member.offset.dy,
          box.right + member.offset.dx,
          box.bottom + member.offset.dy,
          box.direction,
        ),
    ];
  }

  void _ensureActive() {
    if (!isActive) throw StateError('Ruby tree layout is retired');
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final member in _members) {
      member.lease?.release();
    }
    for (final view in _inlineViews.values) {
      view.close();
    }
    _inlineViews = const {};
    _paintNodes = const [];
    _members = const [];
    _byNode = const {};
  }
}

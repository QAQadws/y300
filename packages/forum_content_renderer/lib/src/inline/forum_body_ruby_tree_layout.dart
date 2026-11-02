import 'dart:collection';

import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_paragraph_layout.dart'
    show ForumBodyParagraphLayoutException, ForumBodyParagraphLayoutFailure;
import '../paragraph/forum_body_text_request_preparation.dart';
import 'forum_body_ruby_container_background.dart';
import 'forum_body_ruby_group_contract.dart';
import 'forum_body_ruby_group_metrics.dart';
import 'forum_body_ruby_group_preparation.dart';
import 'forum_body_ruby_hit_band.dart';
import 'forum_body_ruby_tree_input.dart';
import 'forum_body_ruby_tree_metrics_preparation.dart';

part 'forum_body_ruby_tree_preparation.dart';

final class ForumBodyRubyTreeMember {
  const ForumBodyRubyTreeMember._(
    this.nodeIndex,
    this.content,
    this.lease,
    this.offset,
  );
  final int nodeIndex;
  final ForumBodyParagraphContent content;
  final ForumBodyTextLease? lease;
  final Offset offset;
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
    required List<({Rect rect, ForumBodyRubyContainerFontBox font})>
    backgrounds,
  }) : _members = UnmodifiableListView(members),
       _byNode = UnmodifiableMapView(byNode),
       _hasText = UnmodifiableMapView(hasText),
       backgrounds = UnmodifiableListView(backgrounds);
  final ForumBodyRubyTreeInput input;
  final ForumBodyRubyTreeMetrics metrics;
  List<ForumBodyRubyTreeMember> _members;
  Map<int, ForumBodyRubyTreeMember> _byNode;
  final Map<int, bool> _hasText;
  final List<({Rect rect, ForumBodyRubyContainerFontBox font})> backgrounds;
  bool _closed = false;
  List<ForumBodyRubyTreeMember> get members => _members;
  Size get size => metrics.box.bounds.size;
  double get baseline => metrics.box.alphabeticBaseline;
  bool get isActive =>
      !_closed &&
      _members.every(
        (member) =>
            member.lease == null ||
            (member.lease!.isActive && member.lease!.layout.isPaintPrepared),
      );
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases => [
    for (final member in _members) ?member.lease,
  ];
  bool isOwnedBy(ForumBodyParagraphCache cache) =>
      isActive && nativeLeases.every(cache.ownsLease);

  /// Glyph plane only. The page draws ALL container backgrounds before ANY
  /// glyph; interleaving nested backgrounds with text would cover earlier ink.
  void paint(Canvas canvas, Offset offset) {
    _ensureActive();
    for (final member in _members) {
      member.lease?.layout.paint(canvas, offset + member.offset);
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
  }) {
    _ensureActive();
    final member = _byNode[nodeIndex];
    if (member == null) throw ArgumentError.value(nodeIndex, 'nodeIndex');
    RangeError.checkValidRange(
      startUtf16,
      endUtf16,
      member.content.projection.text.length,
    );
    return [
      for (final box
          in member.lease?.layout.selectionBoxes(startUtf16, endUtf16) ??
              const <TextBox>[])
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
    _members = const [];
    _byNode = const {};
  }
}

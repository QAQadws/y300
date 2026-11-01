import 'dart:collection';

import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_text_request.dart';
import '../paragraph/forum_body_text_request_preparation.dart';
import '../style/forum_body_style_options.dart' show ForumBodyRubySide;
import 'forum_body_ruby_group_contract.dart';
import 'forum_body_ruby_group_metrics.dart';
import 'forum_body_ruby_group_preparation.dart';
import 'forum_body_ruby_soft_space_contract.dart';
import 'forum_body_ruby_soft_space_request.dart';
import 'forum_body_text_band_layout.dart';

part 'forum_body_ruby_soft_space_preparation.dart';

final class ForumBodyRubySoftSpaceHit {
  const ForumBodyRubySoftSpaceHit(this.memberIndex, this.position);
  final int memberIndex;
  final HtmlProjectedSourcePosition position;
}

/// Exactly the real, prepared whitespace members of one visible gap. The
/// existing cache owns all glyphs; this object only transfers their leases.
final class ForumBodyRubySoftSpaceLayout {
  ForumBodyRubySoftSpaceLayout._(
    this._leases,
    List<ForumBodyParagraphContent> contents,
    this.metrics,
  ) : _contents = contents,
      contents = UnmodifiableListView(contents);
  List<ForumBodyTextLease> _leases;
  final List<ForumBodyParagraphContent> _contents;
  final List<ForumBodyParagraphContent> contents;
  final ForumBodyRubySoftSpaceMetrics metrics;
  bool _closed = false;
  Size get size => metrics.size;
  double get baseline => metrics.baseline;
  bool get isActive =>
      !_closed && _leases.every((l) => l.isActive && l.layout.isPaintPrepared);
  bool isOwnedBy(ForumBodyParagraphCache cache) =>
      isActive && _leases.every(cache.ownsLease);
  Iterable<ForumBodyNativeParagraphLease> get nativeLeases =>
      _leases.map((l) => l);
  ForumBodyTextLease memberAt(int index) {
    _ensureActive();
    return _leases[index];
  }

  void paint(Canvas canvas, Offset offset) {
    _ensureActive();
    for (final (index, lease) in _leases.indexed) {
      lease.layout.paint(canvas, offset + metrics.members[index].offset);
    }
  }

  ForumBodyRubySoftSpaceHit sourceAt(Offset point) {
    _ensureActive();
    if (!point.dx.isFinite || !point.dy.isFinite) {
      throw ArgumentError.value(point);
    }
    var selected = 0;
    var bestVertical = double.infinity;
    var bestHorizontal = double.infinity;
    double distance(double v, double start, double end) => v < start
        ? start - v
        : v > end
        ? v - end
        : 0;
    for (final (i, member) in metrics.members.indexed) {
      final bounds = member.input.font.bounds.shift(member.offset);
      final vertical = distance(point.dy, member.bandTop, member.bandBottom);
      final horizontal = distance(point.dx, bounds.left, bounds.right);
      if (vertical < bestVertical ||
          (vertical == bestVertical && horizontal < bestHorizontal)) {
        selected = i;
        bestVertical = vertical;
        bestHorizontal = horizontal;
      }
    }
    final member = metrics.members[selected];
    final bounds = member.input.font.bounds.shift(member.offset);
    final hit = _leases[selected].layout.sourceAt(point - member.offset);
    return ForumBodyRubySoftSpaceHit(
      selected,
      bounds.contains(point)
          ? hit
          : HtmlProjectedSourcePosition(
              sourceRune: hit.sourceRune,
              displayUtf16: hit.displayUtf16,
              isExact: false,
            ),
    );
  }

  List<TextBox> selectionBoxes({
    required int memberIndex,
    required int startUtf16,
    required int endUtf16,
  }) {
    _ensureActive();
    final offset = metrics.members[memberIndex].offset;
    return [
      for (final box in _leases[memberIndex].layout.selectionBoxes(
        startUtf16,
        endUtf16,
      ))
        TextBox.fromLTRBD(
          box.left + offset.dx,
          box.top + offset.dy,
          box.right + offset.dx,
          box.bottom + offset.dy,
          box.direction,
        ),
    ];
  }

  void _ensureActive() {
    if (!isActive) throw StateError('Ruby soft-space layout is retired');
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final lease in _leases) {
      lease.release();
    }
    _leases = const [];
    _contents.clear();
  }
}

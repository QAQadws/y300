import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_content.dart';
import '../paragraph/forum_body_text_layout.dart';

/// One text box shifted against its parent's alphabetic baseline. All inputs
/// are already scaled logical pixels; positive shift raises the child.
/// Numeric geometry alone grants no source or native ownership.
final class ForumBodyTextBaselineMetrics {
  ForumBodyTextBaselineMetrics({
    required this.childBounds,
    required this.childBaseline,
    required this.baselineShift,
  }) {
    if (!childBounds.left.isFinite ||
        !childBounds.top.isFinite ||
        !childBounds.right.isFinite ||
        !childBounds.bottom.isFinite ||
        childBounds.width < 0 ||
        childBounds.height < 0 ||
        !childBaseline.isFinite ||
        !baselineShift.isFinite ||
        baselineShift.abs() > 16384) {
      throw ArgumentError('Invalid text baseline geometry');
    }
    final reference = childBaseline + baselineShift;
    final top = math.min(childBounds.top, reference);
    final bottom = math.max(childBounds.bottom, reference);
    size = Size(childBounds.width, bottom - top);
    baseline = reference - top;
    childOffset = Offset(-childBounds.left, -top);
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        !baseline.isFinite ||
        !childOffset.dx.isFinite ||
        !childOffset.dy.isFinite) {
      throw ArgumentError('Text baseline geometry overflow');
    }
  }

  static const revision = 1;
  final Rect childBounds;
  final double childBaseline;
  final double baselineShift;
  late final Size size;
  late final double baseline;
  late final Offset childOffset;

  // Include the reference baseline even when all glyphs are above/below it.
  // Native placeholders then need no negative ascent or descent.
  PlaceholderDimensions get placeholderDimensions => PlaceholderDimensions(
    size: size,
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    baselineOffset: baseline,
  );
}

/// Owns exactly one existing text lease. Painting, hit testing and selection
/// use one translation over the same shaped text, with no extra font or cache.
/// The caller still prepares paint through its reading owner's normal port.
final class ForumBodyTextBaselineLayout implements ForumBodyTextLayout {
  ForumBodyTextBaselineLayout._(this._lease, this.metrics);

  /// Consumes this handle on success AND failure. Other aliases are untouched.
  factory ForumBodyTextBaselineLayout.adopt({
    required ForumBodyParagraphCache cache,
    required ForumBodyTextLease lease,
    required double baselineShift,
  }) {
    try {
      if (!cache.ownsLease(lease)) {
        throw StateError('Text baseline owner is retired or foreign');
      }
      final layout = lease.layout;
      final metrics = ForumBodyTextBaselineMetrics(
        childBounds: forumBodyTextLayoutBounds(layout),
        childBaseline: layout.alphabeticBaseline,
        baselineShift: baselineShift,
      );
      if (!cache.ownsLease(lease)) {
        throw StateError('Text baseline owner retired during measurement');
      }
      return ForumBodyTextBaselineLayout._(lease, metrics);
    } catch (_) {
      lease.release();
      rethrow;
    }
  }

  ForumBodyTextLease? _lease;
  final ForumBodyTextBaselineMetrics metrics;
  ForumBodyTextLease get lease {
    if (isDisposed) throw StateError('Text baseline layout is retired');
    return _lease!;
  }

  ForumBodyParagraphContent get content => lease.content;
  @override
  HtmlDisplayTextProjection get projection => content.projection;
  @override
  bool get isDisposed => _lease == null || !_lease!.isActive;
  @override
  bool get isPaintPrepared => !isDisposed && _lease!.layout.isPaintPrepared;
  @override
  double get width => metrics.size.width;
  @override
  double get height => metrics.size.height;
  @override
  double get alphabeticBaseline => metrics.baseline;

  @override
  void paint(Canvas canvas, Offset offset) {
    _checkPoint(offset);
    lease.layout.paint(canvas, offset + metrics.childOffset);
  }

  @override
  HtmlProjectedSourcePosition sourceAt(Offset offset) {
    _checkPoint(offset);
    final local = offset - metrics.childOffset;
    final position = lease.layout.sourceAt(local);
    if (metrics.childBounds.contains(local)) return position;
    // Space reserved only to reach the parent's baseline is not a glyph hit.
    return HtmlProjectedSourcePosition(
      sourceRune: position.sourceRune,
      displayUtf16: position.displayUtf16,
      isExact: false,
    );
  }

  @override
  List<TextBox> selectionBoxes(int startUtf16, int endUtf16) {
    final offset = metrics.childOffset;
    return List.unmodifiable([
      for (final box in lease.layout.selectionBoxes(startUtf16, endUtf16))
        TextBox.fromLTRBD(
          box.left + offset.dx,
          box.top + offset.dy,
          box.right + offset.dx,
          box.bottom + offset.dy,
          box.direction,
        ),
    ]);
  }

  void _checkPoint(Offset point) {
    if (!point.dx.isFinite || !point.dy.isFinite) {
      throw ArgumentError.value(point);
    }
  }

  void close() {
    final handle = _lease;
    _lease = null;
    handle?.release();
  }
}

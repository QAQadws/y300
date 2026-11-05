import 'dart:math' as math;

import '../block/forum_body_block_flow_cursor.dart';
import '../block/forum_body_block_box.dart';
import '../style/forum_body_box_style.dart';
import '../style/forum_body_length.dart';
import '../style/forum_body_style_options.dart';

typedef _Widths = ({double minimum, double preferred});

/// Reduces actual glyph and resource widths over the normal-flow block stack.
/// Used only by an intrinsic measurement session. A wide probe's unused
/// width and the free space placed by RTL/auto margins are not content.
final class ForumBodyFlowWidthMeasure {
  ForumBodyFlowWidthMeasure(this.availableWidth);
  final double availableWidth;
  final _frames = <_WidthFrame>[];
  _Widths _widths = (minimum: 0, preferred: 0);

  ({double minimum, double preferred}) get result {
    if (_frames.isNotEmpty) throw StateError('Unclosed intrinsic width frame');
    return _widths;
  }

  void add(double minimum, double preferred) {
    final frame = _frames.lastOrNull;
    if (frame == null) {
      _widths = (
        minimum: math.max(_widths.minimum, minimum),
        preferred: math.max(_widths.preferred, preferred),
      );
    } else {
      frame.minimum = math.max(frame.minimum, minimum);
      frame.preferred = math.max(frame.preferred, preferred);
    }
  }

  void open(ForumBodyBlockFlowBoundary boundary) {
    _frames.add(_WidthFrame(boundary));
  }

  void addListGutter(double extent) {
    _frames.last.gutter = extent;
  }

  void close(String path) {
    final frame = _frames.removeLast();
    if (frame.path != path) {
      throw StateError('Unbalanced intrinsic width frame');
    }
    final values = frame.finish();
    add(values.minimum, values.preferred);
  }
}

final class _WidthFrame {
  _WidthFrame(ForumBodyBlockFlowBoundary boundary)
    : path = boundary.boundary.event!.node.path,
      style = boundary.boundary.event!.style,
      box = boundary.box!;

  final String path;
  final ForumBodyResolvedStyle style;
  final ForumBodyBlockBox box;
  double minimum = 0, preferred = 0, gutter = 0;

  _Widths finish() {
    double pixels(ForumBodyLength value) =>
        value.unit == ForumBodyLengthUnit.px ? value.value : 0;
    double fraction(ForumBodyLength value) =>
        value.unit == ForumBodyLengthUnit.percent ? value.value / 100 : 0;
    final paddingFraction =
        fraction(style.padding.left) + fraction(style.padding.right);
    final padding =
        box.padding.horizontal -
        paddingFraction * box.containingWidth +
        box.leftBorder;
    final edges =
        padding + pixels(style.margin.left) + pixels(style.margin.right);
    final edgeFraction =
        paddingFraction +
        fraction(style.margin.left) +
        fraction(style.margin.right);
    final sizing = style.box;
    double contentLength(ForumBodyLength value) => math.max(
      0.0,
      value.value -
          (sizing.sizing == ForumBodyBoxSizing.borderBox ? padding : 0),
    );
    var min = minimum + gutter, pref = preferred + gutter;
    if (sizing.width case final width?) {
      if (width.unit == ForumBodyLengthUnit.px) {
        min = math.max(min, box.contentWidth);
        pref = box.contentWidth;
      } else if (width.unit == ForumBodyLengthUnit.percent && width.value > 0) {
        // The fixed pass resolves this width against the chosen track. Give
        // actual minimum content room even when its block takes a fraction.
        final relative = width.value / 100;
        final outer = sizing.sizing == ForumBodyBoxSizing.borderBox
            ? padding
            : 0.0;
        final needed = (min + outer) / relative - outer;
        min = math.max(min, needed);
      }
    }
    if (sizing.minWidth.unit == ForumBodyLengthUnit.px) {
      min = math.max(min, contentLength(sizing.minWidth));
    }
    if (sizing.maxWidth case final max?
        when max.unit == ForumBodyLengthUnit.px) {
      pref = math.min(pref, contentLength(max));
    }
    // For finite percentage edges solve the containing-width dependency.
    // An over-constrained block is still checked by the actual layout pass.
    final remaining = edgeFraction < 1 ? 1 - edgeFraction : 1.0;
    return (
      minimum: math.max(0.0, (min + edges) / remaining),
      preferred: math.max(0.0, (math.max(min, pref) + edges) / remaining),
    );
  }
}

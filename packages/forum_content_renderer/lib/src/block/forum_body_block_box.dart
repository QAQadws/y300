import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../style/forum_body_box_style.dart';
import '../style/forum_body_length.dart';
import '../style/forum_body_style_options.dart';

enum ForumBodyBlockBoxFailure { display, geometry }

final class ForumBodyBlockBoxException implements Exception {
  const ForumBodyBlockBoxException(this.failure);
  final ForumBodyBlockBoxFailure failure;
  @override
  String toString() => 'ForumBodyBlockBoxException(${failure.name})';
}

/// Horizontal normal-flow geometry for ordinary blocks and built-in quote
/// borders. Fixed CSS lengths
/// are logical pixels; em/rem were computed by the sole style resolver. Text
/// scaling remains owned by the native paragraph and is not applied here.
/// Vertical margins are values only: collapse/fragmentation belongs to flow.
/// Overflow is represented honestly, never shrunk into a different text width.
final class ForumBodyBlockBox {
  const ForumBodyBlockBox._({
    required this.containingWidth,
    required this.contentWidth,
    required this.margin,
    required this.padding,
    required this.leftBorder,
  });

  factory ForumBodyBlockBox.resolve({
    required ForumBodyResolvedStyle style,
    required double containingWidth,
    required TextDirection containingDirection,
    required double rootFontSize,
    bool blockifyInline = false,
  }) {
    if (style.display != ForumBodyDisplay.block &&
        style.display != ForumBodyDisplay.listItem &&
        !(blockifyInline && style.display == ForumBodyDisplay.inline)) {
      throw const ForumBodyBlockBoxException(ForumBodyBlockBoxFailure.display);
    }
    final fontSize = style.textStyle.fontSize;
    if (!containingWidth.isFinite ||
        containingWidth < 0 ||
        !rootFontSize.isFinite ||
        rootFontSize <= 0 ||
        fontSize == null ||
        !fontSize.isFinite ||
        fontSize <= 0) {
      throw const ForumBodyBlockBoxException(ForumBodyBlockBoxFailure.geometry);
    }
    double length(ForumBodyLength value) {
      if (value.unit == ForumBodyLengthUnit.auto || !value.value.isFinite) {
        throw const ForumBodyBlockBoxException(
          ForumBodyBlockBoxFailure.geometry,
        );
      }
      final pixels = value.resolve(
        fontSize: fontSize,
        rootFontSize: rootFontSize,
        reference: containingWidth,
      );
      if (!pixels.isFinite) {
        throw const ForumBodyBlockBoxException(
          ForumBodyBlockBoxFailure.geometry,
        );
      }
      return pixels;
    }

    double verticalMargin(ForumBodyLength value) =>
        value.unit == ForumBodyLengthUnit.auto ? 0 : length(value);
    final padding = EdgeInsets.fromLTRB(
      length(style.padding.left),
      length(style.padding.top),
      length(style.padding.right),
      length(style.padding.bottom),
    );
    if (!padding.isNonNegative ||
        !padding.horizontal.isFinite ||
        !padding.vertical.isFinite) {
      throw const ForumBodyBlockBoxException(ForumBodyBlockBoxFailure.geometry);
    }
    final leftAuto = style.margin.left.unit == ForumBodyLengthUnit.auto;
    final rightAuto = style.margin.right.unit == ForumBodyLengthUnit.auto;
    var left = leftAuto ? 0.0 : length(style.margin.left);
    var right = rightAuto ? 0.0 : length(style.margin.right);
    final box = style.box;
    final leftBorder = style.quoteDecoration == null
        ? 0.0
        : ForumBodyQuoteDecoration.borderWidth * 1.0;
    final horizontalEdges = padding.horizontal + leftBorder;
    double contentLength(ForumBodyLength value) {
      final resolved = length(value);
      if (resolved < 0) {
        throw const ForumBodyBlockBoxException(
          ForumBodyBlockBoxFailure.geometry,
        );
      }
      return box.sizing == ForumBodyBoxSizing.borderBox
          ? math.max(0.0, resolved - horizontalEdges)
          : resolved;
    }

    var width = box.width == null
        ? math.max(0.0, containingWidth - horizontalEdges - left - right)
        : contentLength(box.width!);
    if (box.maxWidth != null) {
      width = math.min(width, contentLength(box.maxWidth!));
    }
    width = math.max(width, contentLength(box.minWidth));
    final remaining = containingWidth - width - horizontalEdges - left - right;
    if (!width.isFinite || !remaining.isFinite) {
      throw const ForumBodyBlockBoxException(ForumBodyBlockBoxFailure.geometry);
    }
    // Re-solve margins after min/max constraints. Over-constrained blocks keep
    // their real width and discard the physical end margin of the containing
    // block's direction, independently of the child's own text direction.
    if (remaining >= 0 && (leftAuto || rightAuto)) {
      if (leftAuto && rightAuto) {
        left = right = remaining / 2;
      } else if (leftAuto) {
        left = remaining;
      } else {
        right = remaining;
      }
    } else if (containingDirection == TextDirection.ltr) {
      right += remaining;
    } else {
      left += remaining;
    }
    return ForumBodyBlockBox._(
      containingWidth: containingWidth,
      contentWidth: width,
      margin: EdgeInsets.fromLTRB(
        left,
        verticalMargin(style.margin.top),
        right,
        verticalMargin(style.margin.bottom),
      ),
      padding: padding,
      leftBorder: leftBorder,
    );
  }

  final double containingWidth;
  final double contentWidth;
  final EdgeInsets margin;
  final EdgeInsets padding;
  final double leftBorder;
  double get contentLeft => margin.left + leftBorder + padding.left;
  double get borderBoxWidth => contentWidth + padding.horizontal + leftBorder;
  bool get hasHorizontalOverflow =>
      margin.left < 0 || margin.left + borderBoxWidth > containingWidth;
}

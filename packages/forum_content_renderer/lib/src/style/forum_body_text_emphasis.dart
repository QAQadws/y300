import 'package:flutter/painting.dart' show Color;

enum ForumBodyEmphasisShape {
  none,
  dot,
  circle,
  doubleCircle,
  triangle,
  sesame,
  custom,
}

enum ForumBodyEmphasisFill { filled, open }

enum ForumBodyEmphasisSide { over, under }

enum ForumBodyEmphasisVerticalSide { right, left }

/// Computed values only. A mark has no DOM range, copy text, native
/// resource or semantic anchor. Layout must separately bind the decorated text.
final class ForumBodyTextEmphasis {
  const ForumBodyTextEmphasis({
    this.shape = ForumBodyEmphasisShape.none,
    this.fill = ForumBodyEmphasisFill.filled,
    this.customMark,
    this.color,
    this.side = ForumBodyEmphasisSide.over,
    this.verticalSide = ForumBodyEmphasisVerticalSide.right,
  }) : assert(
         shape == ForumBodyEmphasisShape.custom
             ? customMark != null
             : customMark == null,
       );
  final ForumBodyEmphasisShape shape;
  final ForumBodyEmphasisFill fill;
  final String? customMark;

  /// null preserves currentColor through inheritance; it is resolved against
  /// each element's effective foreground, including the reader's color policy.
  final Color? color;
  final ForumBodyEmphasisSide side;
  final ForumBodyEmphasisVerticalSide verticalSide;
  ForumBodyTextEmphasis withColor(Color? value) => value == color
      ? this
      : ForumBodyTextEmphasis(
          shape: shape,
          fill: fill,
          customMark: customMark,
          color: value,
          side: side,
          verticalSide: verticalSide,
        );
  bool get isEnabled =>
      shape != ForumBodyEmphasisShape.none &&
      (shape != ForumBodyEmphasisShape.custom || customMark != '');

  String? get mark => switch (shape) {
    ForumBodyEmphasisShape.none => null,
    ForumBodyEmphasisShape.custom => customMark,
    ForumBodyEmphasisShape.dot =>
      fill == ForumBodyEmphasisFill.filled ? '•' : '◦',
    ForumBodyEmphasisShape.circle =>
      fill == ForumBodyEmphasisFill.filled ? '●' : '○',
    ForumBodyEmphasisShape.doubleCircle =>
      fill == ForumBodyEmphasisFill.filled ? '◉' : '◎',
    ForumBodyEmphasisShape.triangle =>
      fill == ForumBodyEmphasisFill.filled ? '▲' : '△',
    ForumBodyEmphasisShape.sesame =>
      fill == ForumBodyEmphasisFill.filled ? '﹅' : '﹆',
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ForumBodyTextEmphasis &&
          shape == other.shape &&
          fill == other.fill &&
          customMark == other.customMark &&
          color == other.color &&
          side == other.side &&
          verticalSide == other.verticalSide;
  @override
  int get hashCode =>
      Object.hash(shape, fill, customMark, color, side, verticalSide);
}

import 'package:flutter/painting.dart';

import 'forum_body_style_options.dart';

/// Hidden text retains its layout and source ownership without visible paint.
TextStyle forumBodyPaintTextStyle(ForumBodyResolvedStyle style) =>
    style.visibilityHidden
    ? style.textStyle.copyWith(
        foreground: Paint()..color = const Color(0x00000000),
        background: Paint()..color = const Color(0x00000000),
        decoration: TextDecoration.none,
        shadows: const [],
      )
    : style.textStyle;

Color? forumBodySolidTextBackground(ForumBodyResolvedStyle style) {
  if (style.visibilityHidden) return null;
  final paint = style.textStyle.background;
  if (paint != null &&
      (paint.shader != null ||
          paint.colorFilter != null ||
          paint.imageFilter != null ||
          paint.maskFilter != null ||
          paint.blendMode != BlendMode.srcOver ||
          paint.style != PaintingStyle.fill)) {
    return null;
  }
  final color = paint?.color ?? style.textStyle.backgroundColor;
  return color != null && color.a > 0 ? color : null;
}

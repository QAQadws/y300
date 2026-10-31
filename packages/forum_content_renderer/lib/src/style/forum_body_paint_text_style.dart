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

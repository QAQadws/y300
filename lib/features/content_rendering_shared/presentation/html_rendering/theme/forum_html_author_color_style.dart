import 'dart:ui';

import 'package:flutter/foundation.dart';

enum ForumHtmlColorSource {
  inlineStyle,
  legacyFontAttribute,
  legacyBgColorAttribute,
  inherited,
}

enum ForumHtmlBackgroundRole { inlineHighlight, blockSurface }

@immutable
final class ForumHtmlAuthorColorStyle {
  const ForumHtmlAuthorColorStyle({
    this.foreground,
    this.background,
    this.foregroundSource,
    this.backgroundSource,
    required this.backgroundRole,
    this.unsupportedForeground = false,
    this.unsupportedBackground = false,
    this.transparentForeground = false,
    this.transparentBackground = false,
  });

  final Color? foreground;
  final Color? background;
  final ForumHtmlColorSource? foregroundSource;
  final ForumHtmlColorSource? backgroundSource;
  final ForumHtmlBackgroundRole backgroundRole;
  final bool unsupportedForeground;
  final bool unsupportedBackground;
  final bool transparentForeground;
  final bool transparentBackground;
}

import 'package:flutter/material.dart';

import '../html_rendering/theme/forum_html_theme_context.dart';
import '../models/forum_html_render_options.dart';

/// Resolves the starting text style before applying author or reader fonts.
TextStyle resolveForumHtmlBaseTextStyle(
  BuildContext context, {
  required ForumHtmlRenderOptions options,
  required ForumHtmlThemeContext theme,
}) {
  final fallback = Theme.of(context).textTheme.bodyMedium;
  final baseFontSize = fallback?.fontSize ?? 14;
  return (fallback ?? const TextStyle()).copyWith(
    color: theme.foreground,
    fontSize: baseFontSize * options.fontScale,
    height: options.lineHeightScale,
  );
}

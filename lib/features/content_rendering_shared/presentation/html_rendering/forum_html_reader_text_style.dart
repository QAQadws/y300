import 'package:flutter/material.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:y300/features/fonts/fonts.dart';

import '../../application/forum_html_render_preferences_projection.dart';
import '../../domain/models/forum_html_reader_preferences.dart';

TextStyle resolveForumHtmlReaderTextStyle(
  BuildContext context, {
  required ForumHtmlReaderPreferences preferences,
  required ForumHtmlThemeContext theme,
  required ResolvedFont font,
}) {
  // Recreate the scene baseline on fallback instead of copying an old reader
  // style: copyWith(null) on the latter would retain its custom family.
  final baseline = resolveForumHtmlBaseTextStyle(
    context,
    options: preferences.renderOptions,
    theme: theme,
  );
  return font.isSystem
      ? baseline
      : baseline.copyWith(fontFamily: font.fontFamily);
}

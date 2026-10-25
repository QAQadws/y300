import 'package:flutter/material.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:y300/features/fonts/fonts.dart';

import '../../domain/models/forum_html_reader_preferences.dart';
import 'forum_html_style_policy.dart';

TextStyle resolveForumHtmlReaderTextStyle(
  BuildContext context, {
  required ForumHtmlReaderPreferences preferences,
  required ForumHtmlThemeContext theme,
  required ResolvedFont font,
}) {
  // Recreate the scene baseline on fallback instead of copying an old reader
  // style: copyWith(null) on the latter would retain its custom family.
  final baseline = ForumHtmlStylePolicy(
    preferences,
    theme: theme,
  ).baseTextStyle(context);
  return font.isSystem
      ? baseline
      : baseline.copyWith(fontFamily: font.fontFamily);
}

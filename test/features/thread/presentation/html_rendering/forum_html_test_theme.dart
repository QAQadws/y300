import 'package:flutter/material.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_adapter.dart';

const forumHtmlTestAdaptationMode = ForumHtmlThemeAdaptationMode.disabled;

const forumHtmlTestTheme = ForumHtmlThemeContext(
  brightness: ForumHtmlBrightness.light,
  surface: Color(0xFFFFFFFF),
  foreground: Color(0xFF212121),
  link: Color(0xFF1565C0),
  quoteSurface: Color(0xFFF1F1F1),
  quoteForeground: Color(0xFF424242),
  codeSurface: Color(0xFFF5F5F5),
  codeForeground: Color(0xFF212121),
);

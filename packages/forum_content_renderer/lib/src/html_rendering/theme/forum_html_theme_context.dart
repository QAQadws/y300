import 'dart:ui';

import 'package:flutter/foundation.dart';

enum ForumHtmlBrightness { light, dark }

@immutable
final class ForumHtmlThemeContext {
  const ForumHtmlThemeContext({
    required this.brightness,
    required this.surface,
    required this.foreground,
    required this.link,
    required this.quoteSurface,
    required this.quoteForeground,
    required this.codeSurface,
    required this.codeForeground,
  });

  final ForumHtmlBrightness brightness;
  final Color surface;
  final Color foreground;
  final Color link;
  final Color quoteSurface;
  final Color quoteForeground;
  final Color codeSurface;
  final Color codeForeground;
  String get signature => _buildSignature(
    brightness: brightness,
    surface: surface,
    foreground: foreground,
    link: link,
    quoteSurface: quoteSurface,
    quoteForeground: quoteForeground,
    codeSurface: codeSurface,
    codeForeground: codeForeground,
  );

  static String _buildSignature({
    required ForumHtmlBrightness brightness,
    required Color surface,
    required Color foreground,
    required Color link,
    required Color quoteSurface,
    required Color quoteForeground,
    required Color codeSurface,
    required Color codeForeground,
  }) {
    String argb(Color color) =>
        color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
    return <String>[
      'forum-html-theme-v1',
      brightness.name,
      argb(surface),
      argb(foreground),
      argb(link),
      argb(quoteSurface),
      argb(quoteForeground),
      argb(codeSurface),
      argb(codeForeground),
    ].join(':');
  }
}

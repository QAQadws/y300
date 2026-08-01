import 'package:flutter/material.dart';

/// Theme-derived color palette for forum WebView CSS generation.
///
/// A-3.1 only exposes values. CSS generation and injection are intentionally
/// left to later A-3 stages so light mode keeps the original forum colors.
@immutable
final class ForumWebViewThemePalette {
  const ForumWebViewThemePalette({
    required this.brightness,
    required this.colorScheme,
    required this.pageBackground,
    required this.surface,
    required this.surfaceElevated,
    required this.sectionHeaderBackground,
    required this.text,
    required this.mutedText,
    required this.subtleText,
    required this.link,
    required this.border,
    required this.inputBackground,
    required this.inputText,
    required this.buttonBackground,
    required this.buttonText,
    required this.quoteBackground,
    required this.codeBackground,
    required this.activeBackground,
    required this.scrim,
  });

  static const String signatureVersion = 'v1';

  final Brightness brightness;
  final String colorScheme;
  final Color pageBackground;
  final Color surface;
  final Color surfaceElevated;
  final Color sectionHeaderBackground;
  final Color text;
  final Color mutedText;
  final Color subtleText;
  final Color link;
  final Color border;
  final Color inputBackground;
  final Color inputText;
  final Color buttonBackground;
  final Color buttonText;
  final Color quoteBackground;
  final Color codeBackground;
  final Color activeBackground;
  final Color scrim;

  String get signature {
    final brightnessLabel = brightness == Brightness.dark ? 'dark' : 'light';
    return '$brightnessLabel:'
        '${_toCssHex(pageBackground)}:'
        '${_toCssHex(surface)}:'
        '${_toCssHex(text)}:'
        '${_toCssHex(border)}:'
        '$signatureVersion';
  }

  static String _toCssHex(Color color) {
    final rgb = color.toARGB32() & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}

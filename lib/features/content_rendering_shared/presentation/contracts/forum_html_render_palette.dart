import 'dart:ui';
import 'package:flutter/foundation.dart';

/// Source-neutral native surface colors supplied by the application's Host.
@immutable
final class ForumHtmlRenderPalette {
  const ForumHtmlRenderPalette({
    required this.background,
    required this.card,
    required this.cardElevated,
    required this.panelBackground,
    required this.accent,
    required this.bodyText,
  });

  final Color background;
  final Color card;
  final Color cardElevated;
  final Color panelBackground;
  final Color accent;
  final Color bodyText;
}

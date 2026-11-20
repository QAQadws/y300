import 'package:flutter/material.dart';

/// Shared image loading style for forum chrome, avatars, and shelf covers.
abstract final class ForumMediaLoadingStyle {
  static const Duration fadeInDuration = Duration(milliseconds: 300);
  static const double placeholderDarkenAmount = 0.10;

  static Color placeholderColorFor(Color backgroundColor) {
    return Color.lerp(backgroundColor, Colors.black, placeholderDarkenAmount)!;
  }
}

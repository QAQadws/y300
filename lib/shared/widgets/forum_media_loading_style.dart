import 'package:flutter/material.dart';

/// Shared loading treatment for forum chrome and avatars.
abstract final class ForumMediaLoadingStyle {
  static const Duration fadeInDuration = Duration(milliseconds: 300);
  static const double placeholderDarkenAmount = 0.10;

  static Color placeholderColorFor(Color backgroundColor) {
    return Color.lerp(backgroundColor, Colors.black, placeholderDarkenAmount)!;
  }
}

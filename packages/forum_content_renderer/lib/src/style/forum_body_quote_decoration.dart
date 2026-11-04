import 'package:flutter/painting.dart';

/// Shared forum quote chrome; these are renderer defaults, not author borders.
final class ForumBodyQuoteDecoration {
  const ForumBodyQuoteDecoration(this.borderColor);
  static const borderWidth = 3;
  static const radius = 6;
  static const verticalPadding = 8;
  static const horizontalPadding = 10;
  final Color borderColor;
}

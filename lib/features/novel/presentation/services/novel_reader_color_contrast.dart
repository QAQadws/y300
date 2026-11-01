import 'dart:math' as math;

import 'package:flutter/painting.dart';

double novelReaderColorContrast(Color foreground, Color background) {
  final a = Color.alphaBlend(foreground, background).computeLuminance();
  final b = background.computeLuminance();
  return (math.max(a, b) + .05) / (math.min(a, b) + .05);
}

/// Adjust generated role colors only. Explicit body color is never rewritten.
/// Bounded RGB interpolation keeps the candidate unchanged when already legible.
Color readableNovelReaderRole(Color candidate, List<Color> backgrounds) {
  double contrast(Color value) => backgrounds
      .map((bg) => novelReaderColorContrast(value, bg))
      .reduce(math.min);
  if (contrast(candidate) >= 4.5) return candidate;
  const black = Color(0xff000000), white = Color(0xffffffff);
  final target = contrast(black) >= contrast(white) ? black : white;
  var low = 0.0, high = 1.0;
  for (var i = 0; i < 16; i++) {
    final middle = (low + high) / 2;
    if (contrast(Color.lerp(candidate, target, middle)!) >= 4.5) {
      high = middle;
    } else {
      low = middle;
    }
  }
  return Color.lerp(candidate, target, high)!;
}

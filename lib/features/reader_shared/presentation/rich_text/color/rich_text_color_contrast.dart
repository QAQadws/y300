import 'dart:ui';

abstract interface class RichTextColorContrast {
  Color composite(Color foreground, Color background);

  double contrastRatio(Color first, Color second);
}

/// Flutter-backed WCAG contrast operations for final display colors.
///
/// Callers must composite every translucent layer onto an opaque reading
/// surface before asking for a contrast ratio.
final class FlutterRichTextColorContrast implements RichTextColorContrast {
  const FlutterRichTextColorContrast();

  @override
  Color composite(Color foreground, Color background) {
    return Color.alphaBlend(foreground, background);
  }

  @override
  double contrastRatio(Color first, Color second) {
    _requireOpaque(first, 'first');
    _requireOpaque(second, 'second');
    final firstLuminance = first.computeLuminance();
    final secondLuminance = second.computeLuminance();
    final lighter = firstLuminance > secondLuminance
        ? firstLuminance
        : secondLuminance;
    final darker = firstLuminance > secondLuminance
        ? secondLuminance
        : firstLuminance;
    return (lighter + 0.05) / (darker + 0.05);
  }

  void _requireOpaque(Color color, String name) {
    if ((color.toARGB32() >>> 24) != 0xFF) {
      throw ArgumentError.value(
        color,
        name,
        'Contrast requires a color composited onto an opaque surface.',
      );
    }
  }
}

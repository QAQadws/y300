part of 'forum_body_emphasis_line_layout.dart';

/// Natural native marker font only. It carries no source coordinate, fitted
/// placement, current lease or scene/coverage qualification.
final class ForumBodyEmphasisMarkFontMetrics {
  const ForumBodyEmphasisMarkFontMetrics._({
    required this.request,
    required this.nativeInputIdentity,
    required this.scaledFontSize,
    required this.width,
    required this.height,
    required this.alphabeticBaseline,
    required this.fontBounds,
  });
  final ForumBodyEmphasisMarkRequest request;
  ForumBodyEmphasisMarkInput get input => request.input;
  final Object nativeInputIdentity;
  final double scaledFontSize, width, height, alphabeticBaseline;
  final Rect fontBounds;
}

/// Qualified glyph geometry and independently sampled half-font numerics.
/// Each font was measured temporarily with the caller's owned prefix; these
/// values are not the complete footprint of a final visible page or scene.
final class ForumBodyInlineEmphasisFontMetrics {
  ForumBodyInlineEmphasisFontMetrics._({
    required this.geometry,
    required this.parentRequest,
    required this.requestWidth,
    required this.textScaler,
    required List<ForumBodyEmphasisMarkFontMetrics> fonts,
    required List<int> unitFonts,
  }) : fonts = UnmodifiableListView(fonts),
       unitFonts = UnmodifiableListView(unitFonts);
  static const revision = 1;
  final ForumBodyInlineEmphasisTextGeometry geometry;
  final ForumBodyInlineParagraphRequest parentRequest;
  final double requestWidth;
  final TextScaler textScaler;
  Map<double, double> get effectiveScales => (textScaler as _LineScaler).values;
  final List<ForumBodyEmphasisMarkFontMetrics> fonts;
  final List<int> unitFonts;
  ForumBodyEmphasisMarkFontMetrics fontForUnit(int index) =>
      fonts[unitFonts[index]];
}

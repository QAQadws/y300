import '../style/forum_body_style_options.dart' show ForumBodyRubySide;

/// One numeric annotation-row transition shared by actual glyph composition
/// and source-free decoration clearance. Callers validate their measured inputs.
({double over, double under, double baseline, double top, double bottom})
forumBodyAdvanceRubyBandStack({
  required double over,
  required double under,
  required bool hasAnnotation,
  required ForumBodyRubySide side,
  required double ascent,
  required double descent,
  required double gap,
}) {
  if (!hasAnnotation) {
    return (over: over, under: under, baseline: 0, top: 0, bottom: 0);
  }
  if (side == ForumBodyRubySide.over) {
    final bottom = -over - gap;
    final next = over + (gap + ascent + descent);
    return (
      over: next,
      under: under,
      baseline: bottom - descent,
      top: -next,
      bottom: bottom,
    );
  }
  final top = under + gap;
  final next = under + (gap + ascent + descent);
  return (
    over: over,
    under: next,
    baseline: top + ascent,
    top: top,
    bottom: next,
  );
}

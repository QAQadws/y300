part of 'forum_body_inline_span_content.dart';

/// Exact whole-parent paint derivation. Real source/child windows, projections,
/// font styles and text seams are borrowed unchanged; only native paint phases
/// differ. These values cannot bind source contexts or become readable parents.
final class ForumBodyInlinePaintInput {
  ForumBodyInlinePaintInput(ForumBodyInlineSpanContent original)
    : original = original,
      background = _derive(original, ForumBodyParagraphPaintLayer.background),
      foreground = _derive(original, ForumBodyParagraphPaintLayer.foreground),
      decoration = _derive(original, ForumBodyParagraphPaintLayer.decoration);
  static const revision = 1;
  final ForumBodyInlineSpanContent original, background, foreground, decoration;
  static ForumBodyInlineSpanContent _derive(
    ForumBodyInlineSpanContent original,
    ForumBodyParagraphPaintLayer layer,
  ) {
    if (original.paintLayer != ForumBodyParagraphPaintLayer.all) {
      throw ArgumentError(
        'Inline paint phases require an original whole parent',
      );
    }
    return ForumBodyInlineSpanContent._paintLayer(original, layer);
  }
}

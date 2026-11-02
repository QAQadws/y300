part of 'forum_body_paragraph_content.dart';

/// Native per-row paint phases. Foreground includes shadows and decorations;
/// both layers must be composed in row order, never all backgrounds first.
enum ForumBodyParagraphPaintLayer { all, background, foreground }

/// Whole-context paint derivation; no text/style seam or font input is changed.
/// These inputs have distinct native identities and use the existing cache and
/// admission. They do not acquire resources or authorize current source hits.
final class ForumBodyParagraphPaintInput {
  ForumBodyParagraphPaintInput(ForumBodyParagraphContent original)
    : original = original,
      background = _derive(original, ForumBodyParagraphPaintLayer.background),
      foreground = _derive(original, ForumBodyParagraphPaintLayer.foreground);

  static const revision = 1;
  final ForumBodyParagraphContent original, background, foreground;

  static ForumBodyParagraphContent _derive(
    ForumBodyParagraphContent original,
    ForumBodyParagraphPaintLayer layer,
  ) {
    if (original.isSourceFree ||
        original.paintLayer != ForumBodyParagraphPaintLayer.all) {
      throw ArgumentError('Paint layers require an original text context');
    }
    return ForumBodyParagraphContent._paintLayer(original, layer);
  }
}

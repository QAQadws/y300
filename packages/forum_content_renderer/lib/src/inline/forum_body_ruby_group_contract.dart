import '../paragraph/forum_body_paragraph_content.dart';

enum ForumBodyRubyGroupFailure { scope, content, geometry, overflow }

final class ForumBodyRubyGroupException implements Exception {
  const ForumBodyRubyGroupException(this.failure);
  final ForumBodyRubyGroupFailure failure;
  @override
  String toString() => 'ForumBodyRubyGroupException(${failure.name})';
}

// Shared pure admission for glyph-only metrics and readable group adoption.
// It is intentionally not exported as a separate public construction bypass.
void validateForumBodyRubyGroupInputs({
  required ForumBodyParagraphContent base,
  required ForumBodyParagraphContent annotation,
  required double gap,
  required double maxWidth,
}) {
  if (base.identity != annotation.identity ||
      base.fontRevision != annotation.fontRevision ||
      base.styleRevision != annotation.styleRevision) {
    throw const ForumBodyRubyGroupException(ForumBodyRubyGroupFailure.scope);
  }
  if (base.layoutMode != ForumBodyParagraphLayoutMode.intrinsicSingleLine ||
      annotation.layoutMode !=
          ForumBodyParagraphLayoutMode.intrinsicSingleLine ||
      (base.projection.text.isEmpty && annotation.projection.text.isEmpty)) {
    throw const ForumBodyRubyGroupException(ForumBodyRubyGroupFailure.content);
  }
  // Child geometry is already scaled into logical pixels. The parent must not
  // apply another TextScaler to the completed placeholder dimensions.
  if (!gap.isFinite ||
      gap < 0 ||
      gap > 16384 ||
      !maxWidth.isFinite ||
      maxWidth <= 0 ||
      maxWidth > 16384) {
    throw const ForumBodyRubyGroupException(ForumBodyRubyGroupFailure.geometry);
  }
}

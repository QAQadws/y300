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
}) => validateForumBodyRubyColumnInputs(
  base: base,
  annotations: [(content: annotation, gap: gap)],
  maxWidth: maxWidth,
);

// Empty positions retain their rank. At least one position must contain text,
// including columns whose only annotation belongs to an outer level.
void validateForumBodyRubyColumnInputs({
  required ForumBodyParagraphContent base,
  required List<({ForumBodyParagraphContent content, double gap})> annotations,
  required double maxWidth,
  bool allowEmptyBase = false,
}) {
  if (annotations.isEmpty ||
      base.layoutMode != ForumBodyParagraphLayoutMode.intrinsicSingleLine) {
    throw const ForumBodyRubyGroupException(ForumBodyRubyGroupFailure.content);
  }
  var hasText = base.projection.text.isNotEmpty;
  for (final annotation in annotations) {
    final content = annotation.content;
    if (base.identity != content.identity ||
        base.fontRevision != content.fontRevision ||
        base.styleRevision != content.styleRevision) {
      throw const ForumBodyRubyGroupException(ForumBodyRubyGroupFailure.scope);
    }
    if (content.layoutMode !=
        ForumBodyParagraphLayoutMode.intrinsicSingleLine) {
      throw const ForumBodyRubyGroupException(
        ForumBodyRubyGroupFailure.content,
      );
    }
    hasText |= content.projection.text.isNotEmpty;
    if (!annotation.gap.isFinite ||
        annotation.gap < 0 ||
        annotation.gap > 16384) {
      throw const ForumBodyRubyGroupException(
        ForumBodyRubyGroupFailure.geometry,
      );
    }
  }
  if (!hasText && !allowEmptyBase) {
    throw const ForumBodyRubyGroupException(ForumBodyRubyGroupFailure.content);
  }
  // Child geometry is already scaled into logical pixels. The parent must not
  // apply another TextScaler to the completed placeholder dimensions.
  if (!maxWidth.isFinite || maxWidth <= 0 || maxWidth > 16384) {
    throw const ForumBodyRubyGroupException(ForumBodyRubyGroupFailure.geometry);
  }
}

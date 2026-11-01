import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_ruby_content.dart';

/// Resolve actual RT columns of one annotation level. Container identity stays
/// in the grammar; anonymous/spanning text, multiple levels and intra-level gaps
/// require their own layout, never transparent-container text concatenation.
({List<ForumBodyRubyTextAnnotationContent> columns, ForumBodyRubySide side})
resolveForumBodyRubyAnnotationInputs(ForumBodyRubyGroupContent group) {
  final entries = group.annotations;
  if (entries.every((entry) => entry is ForumBodyRubyTextAnnotationContent)) {
    return _result(
      entries.cast<ForumBodyRubyTextAnnotationContent>(),
      group.style.rubyPosition,
      group.rootPath,
    );
  }
  if (entries.length != 1 ||
      entries.single is! ForumBodyRubyAnnotationContainerContent) {
    _unsupported(group.rootPath);
  }
  final container = entries.single as ForumBodyRubyAnnotationContainerContent;
  final columns = <ForumBodyRubyTextAnnotationContent>[];
  String? pendingGap;
  for (final part in container.parts) {
    switch (part) {
      case ForumBodyRubyTextAnnotationContent():
        if (pendingGap != null) _unsupported(pendingGap);
        columns.add(part);
      case ForumBodyRubyTextContent():
        final text = part.content.projection.text;
        if (!text.runes.every(_space)) _unsupported(part.content.path);
        // RTC structural indentation is removed only at actual outer edges.
        // An interior gap remains unsupported rather than shifting pairing or
        // discarding a visible annotation-level space.
        if (columns.isNotEmpty && text.isNotEmpty) {
          pendingGap ??= part.content.path ?? container.path;
        }
      default:
        _unsupported(container.path);
    }
  }
  if (columns.isEmpty && container.parts.isNotEmpty) {
    // A sole anonymous annotation, even whitespace-only, may span all bases.
    // It is not the removable edge indentation around actual RT children.
    _unsupported(container.path);
  }
  return _result(columns, container.style.rubyPosition, container.path);
}

({List<ForumBodyRubyTextAnnotationContent> columns, ForumBodyRubySide side})
_result(
  Iterable<ForumBodyRubyTextAnnotationContent> columns,
  ForumBodyRubyPosition position,
  String path,
) {
  final side = position.sideAfter(null);
  if (side == null) _unsupported(path);
  return (columns: List.unmodifiable(columns), side: side);
}

bool _space(int rune) => const {9, 10, 12, 13, 32}.contains(rune);

Never _unsupported(String? path) => throw ForumBodyParagraphInputException(
  ForumBodyParagraphInputFailure.structure,
  path,
);

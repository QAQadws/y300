import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_ruby_content.dart';

typedef ForumBodyRubyAnnotationInput = ({
  List<ForumBodyRubyTextAnnotationContent> columns,
  ForumBodyRubySide side,
});

/// Consecutive direct RTs form one implicit level; every RTC owns another.
/// Keep original level order (including empty RTCs) for pairing and position.
/// Anonymous spans and interior gaps still require their own layout.
List<ForumBodyRubyAnnotationInput> resolveForumBodyRubyAnnotationInputs(
  ForumBodyRubyGroupContent group,
) {
  final levels = <ForumBodyRubyAnnotationInput>[];
  var implicit = <ForumBodyRubyTextAnnotationContent>[];
  void append(
    List<ForumBodyRubyTextAnnotationContent> columns,
    ForumBodyRubyPosition position,
    String path,
  ) {
    final side = position.sideAfter(levels.lastOrNull?.side);
    if (side == null) _unsupported(path);
    levels.add((columns: List.unmodifiable(columns), side: side));
  }

  void flush() {
    if (implicit.isEmpty) return;
    append(implicit, group.style.rubyPosition, group.rootPath);
    implicit = [];
  }

  for (final entry in group.annotations) {
    switch (entry) {
      case ForumBodyRubyTextAnnotationContent():
        implicit.add(entry);
      case ForumBodyRubyAnnotationContainerContent():
        flush();
        append(_columns(entry), entry.style.rubyPosition, entry.path);
    }
  }
  flush();
  if (levels.isEmpty) {
    // Preserve the existing base-only column contract without inventing RTs.
    append([], group.style.rubyPosition, group.rootPath);
  }
  return List.unmodifiable(levels);
}

List<ForumBodyRubyTextAnnotationContent> _columns(
  ForumBodyRubyAnnotationContainerContent container,
) {
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
  return columns;
}

bool _space(int rune) => const {9, 10, 12, 13, 32}.contains(rune);

Never _unsupported(String? path) => throw ForumBodyParagraphInputException(
  ForumBodyParagraphInputFailure.structure,
  path,
);

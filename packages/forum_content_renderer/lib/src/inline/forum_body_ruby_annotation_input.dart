import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_ruby_content.dart';

sealed class ForumBodyRubyAnnotationBoxInput {
  const ForumBodyRubyAnnotationBoxInput();
  String? get path;
}

final class ForumBodyRubyExplicitAnnotationInput
    extends ForumBodyRubyAnnotationBoxInput {
  const ForumBodyRubyExplicitAnnotationInput(this.annotation);
  final ForumBodyRubyTextAnnotationContent annotation;
  @override
  String get path => annotation.path;
}

/// The actual anonymous text sequence, including its existing runs/projection.
/// It is not a generated RT node or a copy of text for each associated base.
final class ForumBodyRubyAnonymousAnnotationInput
    extends ForumBodyRubyAnnotationBoxInput {
  const ForumBodyRubyAnonymousAnnotationInput(this.content);
  final ForumBodyParagraphContent content;
  @override
  String? get path => content.path;
}

typedef ForumBodyRubyAnnotationInput = ({
  List<ForumBodyRubyAnnotationBoxInput> boxes,
  ForumBodyRubySide side,
});

/// Consecutive direct RTs form one implicit level; every RTC owns another.
/// Keep original level order (including empty RTCs) for pairing and position.
/// Anonymous boxes retain their real type until explicit interval pairing.
/// Interior gaps and nested boxes still require their own layout.
List<ForumBodyRubyAnnotationInput> resolveForumBodyRubyAnnotationInputs(
  ForumBodyRubyGroupContent group,
) {
  final levels = <ForumBodyRubyAnnotationInput>[];
  var implicit = <ForumBodyRubyAnnotationBoxInput>[];
  void append(
    List<ForumBodyRubyAnnotationBoxInput> boxes,
    ForumBodyRubyPosition position,
    String path,
  ) {
    final side = position.sideAfter(levels.lastOrNull?.side);
    if (side == null) _unsupported(path);
    levels.add((boxes: List.unmodifiable(boxes), side: side));
  }

  void flush() {
    if (implicit.isEmpty) return;
    append(implicit, group.style.rubyPosition, group.rootPath);
    implicit = [];
  }

  for (final entry in group.annotations) {
    switch (entry) {
      case ForumBodyRubyTextAnnotationContent():
        implicit.add(ForumBodyRubyExplicitAnnotationInput(entry));
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

List<ForumBodyRubyAnnotationBoxInput> _columns(
  ForumBodyRubyAnnotationContainerContent container,
) {
  final boxes = <ForumBodyRubyAnnotationBoxInput>[];
  String? pendingGap;
  for (final (index, part) in container.parts.indexed) {
    switch (part) {
      case ForumBodyRubyTextAnnotationContent():
        if (pendingGap != null) _unsupported(pendingGap);
        boxes.add(ForumBodyRubyExplicitAnnotationInput(part));
      case ForumBodyRubyTextContent():
        final text = part.content.projection.text;
        if (!text.runes.every(_space)) {
          if (pendingGap != null) _unsupported(pendingGap);
          boxes.add(ForumBodyRubyAnonymousAnnotationInput(part.content));
          continue;
        }
        // RTC structural indentation is removed only at actual outer edges.
        // An interior gap remains unsupported rather than shifting pairing or
        // discarding a visible annotation-level space.
        if (container.parts.length == 1) {
          boxes.add(ForumBodyRubyAnonymousAnnotationInput(part.content));
        } else if (index != 0 &&
            index != container.parts.length - 1 &&
            text.isNotEmpty) {
          pendingGap ??= part.content.path ?? container.path;
        }
      default:
        _unsupported(container.path);
    }
  }
  return boxes;
}

bool _space(int rune) => const {9, 10, 12, 13, 32}.contains(rune);

Never _unsupported(String? path) => throw ForumBodyParagraphInputException(
  ForumBodyParagraphInputFailure.structure,
  path,
);

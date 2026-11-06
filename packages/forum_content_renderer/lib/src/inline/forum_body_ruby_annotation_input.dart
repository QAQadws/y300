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
  List<ForumBodyRubyAnnotationGapInput> gaps,
  ForumBodyRubySide side,
});

/// An original whitespace context between actual boxes, never another RT.
/// beforeBox is a unit index, not a source-code-point or display offset.
typedef ForumBodyRubyAnnotationGapInput = ({
  int beforeBox,
  ForumBodyParagraphContent content,
});

/// Consecutive direct RTs form one implicit level; every RTC owns another.
/// Keep original level order (including empty RTCs) for pairing and position.
/// Anonymous boxes retain their real type until explicit interval pairing.
/// Interior gaps retain their real context independently of RT unit pairing.
/// This pure value does not prove that a consumer supports their layout.
List<ForumBodyRubyAnnotationInput> resolveForumBodyRubyAnnotationInputs(
  ForumBodyRubyGroupContent group,
) {
  final levels = <ForumBodyRubyAnnotationInput>[];
  var implicit = <ForumBodyRubyAnnotationBoxInput>[];
  List<ForumBodyRubyAnnotationGapInput>? implicitGaps;
  void append(
    List<ForumBodyRubyAnnotationBoxInput> boxes,
    ForumBodyRubyPosition position,
    String path, [
    List<ForumBodyRubyAnnotationGapInput> gaps = const [],
  ]) {
    final side = position.sideAfter(levels.lastOrNull?.side);
    if (side == null) _unsupported(path);
    levels.add((
      boxes: List.unmodifiable(boxes),
      gaps: gaps.isEmpty ? const [] : List.unmodifiable(gaps),
      side: side,
    ));
  }

  void flush() {
    if (implicit.isEmpty) return;
    append(
      implicit,
      group.style.rubyPosition,
      group.rootPath,
      implicitGaps ?? const [],
    );
    implicit = [];
    implicitGaps = null;
  }

  var gapIndex = 0;
  for (final (index, entry) in group.annotations.indexed) {
    while (gapIndex < group.annotationGaps.length &&
        group.annotationGaps[gapIndex].beforeAnnotationIndex == index) {
      final gap = group.annotationGaps[gapIndex++];
      if (implicit.isEmpty || entry is! ForumBodyRubyTextAnnotationContent) {
        _unsupported(gap.content.path ?? group.rootPath);
      }
      (implicitGaps ??= []).add((
        beforeBox: implicit.length,
        content: gap.content,
      ));
    }
    switch (entry) {
      case ForumBodyRubyTextAnnotationContent():
        implicit.add(ForumBodyRubyExplicitAnnotationInput(entry));
      case ForumBodyRubyAnnotationContainerContent():
        flush();
        final contents = resolveForumBodyRubyAnnotationColumns(entry);
        append(
          contents.boxes,
          entry.style.rubyPosition,
          entry.path,
          contents.gaps,
        );
    }
  }
  if (gapIndex != group.annotationGaps.length) _unsupported(group.rootPath);
  flush();
  if (levels.isEmpty) {
    // Preserve the existing base-only column contract without inventing RTs.
    append([], group.style.rubyPosition, group.rootPath);
  }
  return List.unmodifiable(levels);
}

({
  List<ForumBodyRubyAnnotationBoxInput> boxes,
  List<ForumBodyRubyAnnotationGapInput> gaps,
})
resolveForumBodyRubyAnnotationColumns(
  ForumBodyRubyAnnotationContainerContent container,
) {
  final boxes = <ForumBodyRubyAnnotationBoxInput>[];
  final gaps = <ForumBodyRubyAnnotationGapInput>[];
  final pending = <ForumBodyParagraphContent>[];
  void append(ForumBodyRubyAnnotationBoxInput box) {
    // A gap is interior only after a following real box arrives. Consecutive
    // styled pieces keep separate identities; leading/trailing indentation
    // never invents an annotation unit or shifts its neighbours.
    for (final content in pending) {
      gaps.add((beforeBox: boxes.length, content: content));
    }
    pending.clear();
    boxes.add(box);
  }

  for (final part in container.parts) {
    switch (part) {
      case ForumBodyRubyTextAnnotationContent():
        append(ForumBodyRubyExplicitAnnotationInput(part));
      case ForumBodyRubyTextContent():
        final text = part.content.projection.text;
        if (!text.runes.every(_space)) {
          append(ForumBodyRubyAnonymousAnnotationInput(part.content));
          continue;
        }
        // A sole whitespace annotation is still an actual anonymous box.
        if (container.parts.length == 1) {
          boxes.add(ForumBodyRubyAnonymousAnnotationInput(part.content));
        } else if (boxes.isNotEmpty && text.isNotEmpty) {
          pending.add(part.content);
        }
      default:
        _unsupported(container.path);
    }
  }
  return (boxes: boxes, gaps: gaps);
}

bool _space(int rune) => const {9, 10, 12, 13, 32}.contains(rune);

Never _unsupported(String? path) => throw ForumBodyParagraphInputException(
  ForumBodyParagraphInputFailure.structure,
  path,
);

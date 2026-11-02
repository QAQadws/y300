import '../paragraph/forum_body_paragraph_content.dart';
import 'forum_body_ruby_content.dart';
import 'forum_body_ruby_child_input.dart';

enum ForumBodyRubyBaseInputKind { implicit, explicit, gap }

typedef ForumBodyRubyBaseInput = ({
  ForumBodyParagraphContent content,
  ForumBodyRubyBaseInputKind kind,
});

typedef ForumBodyRubyBaseChildInput = ({
  ForumBodyRubyChildInput child,
  ForumBodyRubyBaseInputKind kind,
});

/// Original base units before their native representation is chosen. Structured
/// RBs stay structured; indentation outside explicit RBs never consumes a column.
List<ForumBodyRubyBaseChildInput> resolveForumBodyRubyBaseChildInputs(
  ForumBodyRubyGroupContent group,
) {
  final explicit = group.base.any((part) => part is ForumBodyRubyBaseContent);
  if (!explicit) {
    return group.base.isEmpty
        ? const []
        : List.unmodifiable([
            (
              child: ForumBodyRubyChildInput.implicit(group, group.base),
              kind: ForumBodyRubyBaseInputKind.implicit,
            ),
          ]);
  }
  return List.unmodifiable([
    for (final part in group.base)
      switch (part) {
        ForumBodyRubyBaseContent() => (
          child: ForumBodyRubyChildInput.base(group, part),
          kind: ForumBodyRubyBaseInputKind.explicit,
        ),
        ForumBodyRubyTextContent() => (
          child: ForumBodyRubyChildInput.implicit(group, [part]),
          kind: part.content.projection.text.runes.every(_space)
              ? ForumBodyRubyBaseInputKind.gap
              : ForumBodyRubyBaseInputKind.implicit,
        ),
        ForumBodyRubyNestedContent() => (
          child: ForumBodyRubyChildInput.implicit(group, [part]),
          kind: ForumBodyRubyBaseInputKind.implicit,
        ),
        ForumBodyRubyAnnotationContent() => _unsupported(part.path),
      },
  ]);
}

/// Flat text units in original base-range order, before native pairing. A
/// whitespace-only RB is an explicit unit; whitespace outside RBs is a gap.
/// Nested content remains unsupported here, never silently flattened.
List<ForumBodyRubyBaseInput> resolveForumBodyRubyBaseInputs(
  ForumBodyRubyGroupContent group,
) {
  return List.unmodifiable([
    for (final unit in resolveForumBodyRubyBaseChildInputs(group))
      (content: unit.child.requireText(), kind: unit.kind),
  ]);
}

bool _space(int rune) => const {9, 10, 12, 13, 32}.contains(rune);

Never _unsupported(String? path) => throw ForumBodyParagraphInputException(
  ForumBodyParagraphInputFailure.structure,
  path,
);

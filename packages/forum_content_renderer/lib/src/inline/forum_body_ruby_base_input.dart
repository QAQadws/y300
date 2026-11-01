import '../paragraph/forum_body_paragraph_content.dart';
import 'forum_body_ruby_content.dart';

enum ForumBodyRubyBaseInputKind { implicit, explicit, gap }

typedef ForumBodyRubyBaseInput = ({
  ForumBodyParagraphContent content,
  ForumBodyRubyBaseInputKind kind,
});

/// Flat text units in original base-range order, before native pairing. A
/// whitespace-only RB is an explicit unit; whitespace outside RBs is a gap.
/// Nested content remains unsupported here, never silently flattened.
List<ForumBodyRubyBaseInput> resolveForumBodyRubyBaseInputs(
  ForumBodyRubyGroupContent group,
) {
  final hasExplicit = group.base.any(
    (part) => part is ForumBodyRubyBaseContent,
  );
  if (!hasExplicit && group.base.length > 1) _unsupported(group.rootPath);
  return List.unmodifiable([
    for (final part in group.base)
      switch (part) {
        ForumBodyRubyTextContent() => (
          content: part.content,
          kind: hasExplicit && part.content.projection.text.runes.every(_space)
              ? ForumBodyRubyBaseInputKind.gap
              : ForumBodyRubyBaseInputKind.implicit,
        ),
        ForumBodyRubyBaseContent() => (
          content: _explicitText(part),
          kind: ForumBodyRubyBaseInputKind.explicit,
        ),
        ForumBodyRubyNestedContent() => _unsupported(part.path),
      },
  ]);
}

ForumBodyParagraphContent _explicitText(ForumBodyRubyBaseContent base) {
  if (base.parts.length != 1 ||
      base.parts.single is! ForumBodyRubyTextContent) {
    _unsupported(base.path);
  }
  return (base.parts.single as ForumBodyRubyTextContent).content;
}

bool _space(int rune) => const {9, 10, 12, 13, 32}.contains(rune);

Never _unsupported(String? path) => throw ForumBodyParagraphInputException(
  ForumBodyParagraphInputFailure.structure,
  path,
);

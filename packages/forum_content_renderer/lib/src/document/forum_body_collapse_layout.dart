import 'forum_body_document.dart';

/// One Discuz fold with actual nodes from the same repaired document.
final class ForumBodyCollapseSection {
  const ForumBodyCollapseSection._(
    this.box,
    this.title,
    this.body,
    this.initiallyExpanded,
    this.expanded,
  );

  final ForumBodyElement box, title, body;
  final bool initiallyExpanded, expanded;
  String get id => box.path;
}

/// Immutable layout input for one chapter generation. IDs are actual box
/// paths, so duplicate titles or author IDs cannot share expansion state.
final class ForumBodyCollapseLayout {
  factory ForumBodyCollapseLayout(
    ForumBodyDocument document, {
    Map<String, bool> expansionOverrides = const {},
  }) {
    final sections = <String, ForumBodyCollapseSection>{};
    final elements = <ForumBodyElement, ForumBodyCollapseSection>{};
    for (final box in document.collapseElements) {
      if (!identical(document.nodeAtPath(box.path), box) ||
          box.kind != ForumBodyElementKind.collapse) {
        throw ArgumentError('Collapse box belongs to another document');
      }
      ForumBodyElement? title, body;
      var valid = true;
      for (final child in box.children) {
        if (child is! ForumBodyElement) continue;
        if (child.kind == ForumBodyElementKind.collapseTitle) {
          if (title != null || body != null) {
            valid = false;
            break;
          }
          title = child;
        } else if (child.kind == ForumBodyElementKind.collapseContent) {
          if (title == null || body != null) {
            valid = false;
            break;
          }
          body = child;
        }
      }
      if (!valid || title == null || body == null) continue;
      final initiallyExpanded =
          box.attributes['class']
              ?.split(_classSpace)
              .contains('showcollapse_active') ??
          false;
      final section = ForumBodyCollapseSection._(
        box,
        title,
        body,
        initiallyExpanded,
        expansionOverrides[box.path] ?? initiallyExpanded,
      );
      sections[box.path] = section;
      elements[box] = elements[title] = elements[body] = section;
    }
    if (expansionOverrides.keys.any((id) => !sections.containsKey(id))) {
      throw ArgumentError('Unknown collapse section');
    }
    return ForumBodyCollapseLayout._(
      document,
      Map.unmodifiable(sections),
      Map.unmodifiable(elements),
      Set.unmodifiable([
        for (final section in sections.values)
          if (!section.expanded) section.body.path,
      ]),
    );
  }

  const ForumBodyCollapseLayout._(
    this.document,
    this.sections,
    this._elements,
    this._closedBodies,
  );

  static final _classSpace = RegExp(r'\s+');
  final ForumBodyDocument document;
  final Map<String, ForumBodyCollapseSection> sections;
  final Map<ForumBodyElement, ForumBodyCollapseSection> _elements;
  final Set<String> _closedBodies;

  ForumBodyCollapseSection? sectionFor(ForumBodyElement element) =>
      _elements[element];

  bool omitsBody(ForumBodyElement element) {
    final section = _elements[element];
    return section != null &&
        identical(element, section.body) &&
        !section.expanded;
  }

  /// A path from this document is excluded when it falls inside a closed body.
  /// The check walks path segments, so adjacent sibling indices cannot match.
  bool hidesPath(String path) {
    if (_closedBodies.isEmpty) return false;
    var end = path.length;
    while (end > 0) {
      if (_closedBodies.contains(path.substring(0, end))) return true;
      end = path.lastIndexOf('/', end - 1);
    }
    return false;
  }
}

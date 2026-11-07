import '../document/forum_body_collapse_layout.dart';
import '../document/forum_body_document.dart';
import 'forum_body_style_builder.dart';
import 'forum_body_style_cursor.dart';
import 'forum_body_style_options.dart';

/// Resolves the immutable IR without reparsing HTML or constructing widgets.
final class ForumBodyStyleResolver {
  const ForumBodyStyleResolver();
  static const revision = forumBodyStyleRevision;

  ForumBodyStyleCursor open(
    ForumBodyDocument document,
    ForumBodyReaderStyle reader, {
    ForumBodyCollapseLayout? collapses,
    ForumBodyElement? contentRoot,
  }) => ForumBodyStyleCursor(
    document: document,
    reader: reader,
    collapses: collapses,
    contentRoot: contentRoot,
  );

  ForumBodyStyleResult resolve(
    ForumBodyDocument document,
    ForumBodyReaderStyle reader,
  ) {
    final cursor = open(document, reader);
    final styles = <String, ForumBodyResolvedStyle>{};
    final issues = <ForumBodyStyleIssue>[];
    try {
      while (cursor.moveNext()) {
        styles[cursor.currentNode!.path] = cursor.currentStyle!;
        issues.addAll(cursor.takePendingIssues());
      }
      return ForumBodyStyleResult(
        identity: cursor.identity,
        fontRevision: cursor.fontRevision,
        resolverRevision: revision,
        root: cursor.root,
        byPath: styles,
        issues: issues,
      );
    } finally {
      cursor.close();
    }
  }

  /// Uses the normal ancestor cascade before a resource is handed to a Host.
  /// No descendants, paragraphs or native layout resources are constructed.
  bool isVisibleAt(
    ForumBodyDocument document,
    ForumBodyReaderStyle reader,
    ForumBodyElement element, {
    ForumBodyCollapseLayout? collapses,
  }) {
    if (collapses != null && !identical(collapses.document, document)) {
      throw ArgumentError('Collapse layout belongs to another document');
    }
    if (collapses?.hidesPath(element.path) == true) return false;
    final cursor = open(
      document,
      reader,
      collapses: collapses,
      contentRoot: element,
    );
    try {
      return !cursor.root.hidden && !cursor.root.visibilityHidden;
    } finally {
      cursor.close();
    }
  }
}

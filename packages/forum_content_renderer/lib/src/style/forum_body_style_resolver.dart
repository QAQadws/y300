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
    ForumBodyReaderStyle reader,
  ) => ForumBodyStyleCursor(document: document, reader: reader);

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
}

import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_layout.dart';
import 'forum_body_text_page_composer.dart';
import 'forum_body_source_hint.dart';

enum ForumBodyTextPageSurfaceFailure { generation, leases, identity, geometry }

final class ForumBodyTextPageSurfaceException implements Exception {
  const ForumBodyTextPageSurfaceException(this.failure);
  final ForumBodyTextPageSurfaceFailure failure;
  @override
  String toString() => 'ForumBodyTextPageSurfaceException(${failure.name})';
}

/// Shared readiness gate for headless page preparation and the visible Surface.
/// This borrows inputs without taking ownership or touching a Widget/Context.
ForumBodyTextPage validateForumBodyTextPageBinding({
  required ForumBodyTextPageSnapshot snapshot,
  required int pageIndex,
  required String layoutId,
  required List<ForumBodyParagraphLease> leases,
}) {
  if (snapshot.layoutId != layoutId ||
      snapshot.backendRevision != ForumBodyParagraphLayout.backendRevision ||
      snapshot.composerRevision != ForumBodyTextPageComposer.revision) {
    _fail(ForumBodyTextPageSurfaceFailure.generation);
  }
  final page = snapshot[pageIndex];
  if (leases.length != page.fragments.length ||
      (Set<ForumBodyParagraphLease>.identity()..addAll(leases)).length !=
          leases.length ||
      leases.any((lease) => !lease.isActive)) {
    _fail(ForumBodyTextPageSurfaceFailure.leases);
  }
  for (final (index, fragment) in page.fragments.indexed) {
    final lease = leases[index];
    final content = lease.content;
    if (content.identity != snapshot.identity ||
        content.path != fragment.path ||
        content.fontRevision != fragment.fontRevision ||
        content.styleRevision != fragment.styleRevision) {
      _fail(ForumBodyTextPageSurfaceFailure.identity);
    }
    final layout = lease.layout;
    if (layout.isDisposed) _fail(ForumBodyTextPageSurfaceFailure.leases);
    ForumBodyParagraphFragment? view;
    if (layout.lines.isEmpty) {
      if (fragment.startLine != 0 || fragment.endLine != 0) {
        _fail(ForumBodyTextPageSurfaceFailure.geometry);
      }
    } else {
      try {
        view = layout.fragment(fragment.startLine, fragment.endLine);
      } on RangeError {
        _fail(ForumBodyTextPageSurfaceFailure.geometry);
      } on StateError {
        _fail(ForumBodyTextPageSurfaceFailure.geometry);
      } on ForumBodyParagraphLayoutException {
        _fail(ForumBodyTextPageSurfaceFailure.geometry);
      }
    }
    if (layout.width != fragment.width ||
        (view?.height ?? layout.height) != fragment.height ||
        (view?.coverageStartUtf16 ?? 0) != fragment.coverageStartUtf16 ||
        (view?.coverageEndUtf16 ?? 0) != fragment.coverageEndUtf16 ||
        fragment.sourceHint !=
            forumBodySourceHint(
              content.projection,
              view?.coverageStartUtf16 ?? 0,
              view?.coverageEndUtf16 ?? 0,
            )) {
      _fail(ForumBodyTextPageSurfaceFailure.geometry);
    }
  }
  return page;
}

Never _fail(ForumBodyTextPageSurfaceFailure failure) =>
    throw ForumBodyTextPageSurfaceException(failure);

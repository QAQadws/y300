import 'dart:ui' show Offset;
import 'package:flutter/foundation.dart' show listEquals;
import '../paragraph/forum_body_paragraph_cache.dart';
import '../paragraph/forum_body_paragraph_layout.dart';
import 'forum_body_text_page_composer.dart';
import 'forum_body_source_hint.dart';
import 'forum_body_prepared_text_fragment.dart';

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
    if (fragment.listMarker != null) {
      _fail(ForumBodyTextPageSurfaceFailure.leases);
    }
    _validateParagraph(fragment, leases[index], snapshot);
  }
  return page;
}

/// Full typed delivery gate. All visible child resources must already be
/// prepared and source-bound; numeric pages/parent placeholders alone cannot
/// establish readable coverage. This function borrows and never closes input.
ForumBodyTextPage validateForumBodyPreparedTextPageBinding({
  required ForumBodyTextPageSnapshot snapshot,
  required int pageIndex,
  required String layoutId,
  required List<ForumBodyPreparedTextFragment> fragments,
}) {
  if (snapshot.layoutId != layoutId ||
      snapshot.backendRevision != ForumBodyParagraphLayout.backendRevision ||
      snapshot.composerRevision != ForumBodyTextPageComposer.revision) {
    _fail(ForumBodyTextPageSurfaceFailure.generation);
  }
  final page = snapshot[pageIndex];
  if (fragments.length != page.fragments.length ||
      fragments.any((fragment) => !fragment.isActive)) {
    _fail(ForumBodyTextPageSurfaceFailure.leases);
  }
  final handles = Set<ForumBodyNativeParagraphLease>.identity();
  ForumBodyNativeParagraphLease? ownerWitness;
  for (final (index, delivery) in fragments.indexed) {
    for (final handle in delivery.nativeLeases) {
      if (!handle.isActive ||
          !handles.add(handle) ||
          (ownerWitness != null && !ownerWitness.hasSameActiveOwner(handle))) {
        _fail(ForumBodyTextPageSurfaceFailure.leases);
      }
      ownerWitness ??= handle;
    }
    final fragment = page.fragments[index];
    final binding = delivery is ForumBodyPreparedListItemFragment
        ? delivery.body
        : delivery;
    if (binding is! ForumBodyPreparedInlineFragment &&
        delivery.imageCount != fragment.imageCount) {
      _fail(ForumBodyTextPageSurfaceFailure.geometry);
    }
    if (delivery is ForumBodyPreparedListItemFragment) {
      final baseline = switch (binding) {
        ForumBodyPreparedImageFragment() ||
        ForumBodyPreparedHiddenImageFragment() =>
          delivery.plan.blockTopBaseline,
        ForumBodyPreparedParagraphFragment() when binding.lines.isEmpty =>
          binding.lease.layout.alphabeticBaseline,
        _ => binding.lines.first.baseline,
      };
      if (delivery.plan.identity != snapshot.identity ||
          !identical(delivery.placement, fragment.listMarker) ||
          delivery.picture.input != delivery.plan.picture ||
          delivery.placement.baseline != baseline ||
          delivery.placement.bounds !=
              delivery.plan.bounds.shift(Offset(0, baseline))) {
        _fail(ForumBodyTextPageSurfaceFailure.geometry);
      }
    } else if (fragment.listMarker != null) {
      _fail(ForumBodyTextPageSurfaceFailure.leases);
    }
    switch (binding) {
      case ForumBodyPreparedHiddenImageFragment():
        if (binding.content.identity != snapshot.identity) {
          _fail(ForumBodyTextPageSurfaceFailure.identity);
        }
        binding.content.nativeHandleCountFor(fragment);
      case ForumBodyPreparedImageFragment():
        if (binding.content.identity != snapshot.identity) {
          _fail(ForumBodyTextPageSurfaceFailure.identity);
        }
        binding.content.nativeHandleCountFor(fragment);
      case ForumBodyPreparedListItemFragment():
        _fail(ForumBodyTextPageSurfaceFailure.identity);
      case ForumBodyPreparedParagraphFragment():
        if (binding.startLine != fragment.startLine ||
            binding.endLine != fragment.endLine) {
          _fail(ForumBodyTextPageSurfaceFailure.geometry);
        }
        _validateParagraph(fragment, binding.lease, snapshot);
      case ForumBodyPreparedInlineFragment():
        if (fragment.kind != ForumBodyTextPageFragmentKind.inline) {
          _fail(ForumBodyTextPageSurfaceFailure.identity);
        }
        final view = binding.view;
        final (:content, :engineRange, :images) = view.readPageBinding();
        if (images.length != fragment.imageCount) {
          _fail(ForumBodyTextPageSurfaceFailure.geometry);
        }
        if (content.identity != snapshot.identity ||
            content.path != fragment.path ||
            content.fontRevision != fragment.fontRevision ||
            content.styleRevision != fragment.styleRevision) {
          _fail(ForumBodyTextPageSurfaceFailure.identity);
        }
        if (view.startLine != fragment.startLine ||
            view.endLine != fragment.endLine ||
            view.width != fragment.width ||
            view.height != fragment.height ||
            view.coverageStartUtf16 != fragment.coverageStartUtf16 ||
            view.coverageEndUtf16 != fragment.coverageEndUtf16 ||
            engineRange != fragment.engineRange ||
            (images.isEmpty
                ? fragment.imagePaths.isNotEmpty
                : !listEquals(
                    images.values
                        .map((image) => image.input.element.path)
                        .toList(growable: false),
                    fragment.imagePaths,
                  )) ||
            fragment.sourceHint !=
                forumBodySourceHint(
                  content.projection.display,
                  view.coverageStartUtf16,
                  view.coverageEndUtf16,
                )) {
          _fail(ForumBodyTextPageSurfaceFailure.geometry);
        }
      case ForumBodyPreparedEmphasisFragment():
        if (fragment.kind != ForumBodyTextPageFragmentKind.emphasis) {
          _fail(ForumBodyTextPageSurfaceFailure.identity);
        }
        final view = binding.view, content = view.input.paragraph.content;
        view.ensureActive();
        if (content.identity != snapshot.identity ||
            content.path != fragment.path ||
            content.fontRevision != fragment.fontRevision ||
            content.styleRevision != fragment.styleRevision) {
          _fail(ForumBodyTextPageSurfaceFailure.identity);
        }
        if (view.input.startLine != fragment.startLine ||
            view.input.endLine != fragment.endLine ||
            view.width != fragment.width ||
            view.height != fragment.height ||
            view.coverageStartUtf16 != fragment.coverageStartUtf16 ||
            view.coverageEndUtf16 != fragment.coverageEndUtf16 ||
            fragment.sourceHint !=
                forumBodySourceHint(
                  content.projection,
                  view.coverageStartUtf16,
                  view.coverageEndUtf16,
                )) {
          _fail(ForumBodyTextPageSurfaceFailure.geometry);
        }
    }
  }
  return page;
}

void _validateParagraph(
  ForumBodyTextPageFragment fragment,
  ForumBodyParagraphLease lease,
  ForumBodyTextPageSnapshot snapshot,
) {
  if (fragment.kind != ForumBodyTextPageFragmentKind.paragraph) {
    _fail(ForumBodyTextPageSurfaceFailure.identity);
  }
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

Never _fail(ForumBodyTextPageSurfaceFailure failure) =>
    throw ForumBodyTextPageSurfaceException(failure);

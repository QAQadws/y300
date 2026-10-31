import 'dart:async';

import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../services/novel_reader_pagination_cancellation.dart';
import 'novel_reader_native_page_coverage.dart';

enum NovelReaderNativePageViewState { owned, transferred, closed }

/// Owns an unmounted, fully checked view. takeFragments transfers ownership to
/// the caller/Surface exactly once; a later close never releases mounted views.
final class NovelReaderNativePageView {
  factory NovelReaderNativePageView.own({
    required ForumBodyTextPageSession session,
    required int pageIndex,
    required List<ForumBodyParagraphLease> leases,
    required NovelReaderNativePageCoverage coverage,
    required NovelReaderPaginationCancellationToken parent,
  }) {
    parent.throwIfCancelled();
    if (session.isClosed || session.isLayoutOwnerRetired) {
      throw const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.ownerRetired,
      );
    }
    validateForumBodyTextPageBinding(
      snapshot: session.snapshot,
      pageIndex: pageIndex,
      layoutId: session.snapshot.layoutId,
      leases: leases,
    );
    return NovelReaderNativePageView.ownPrepared(
      session: session,
      pageIndex: pageIndex,
      coverage: coverage,
      parent: parent,
      fragments: [
        for (final (index, lease) in leases.indexed)
          ForumBodyPreparedTextFragment.paragraph(
            lease: lease,
            startLine: session.snapshot[pageIndex].fragments[index].startLine,
            endLine: session.snapshot[pageIndex].fragments[index].endLine,
          ),
      ],
    );
  }

  factory NovelReaderNativePageView.ownPrepared({
    required ForumBodyTextPageSession session,
    required int pageIndex,
    required List<ForumBodyPreparedTextFragment> fragments,
    required NovelReaderNativePageCoverage coverage,
    required NovelReaderPaginationCancellationToken parent,
  }) {
    parent.throwIfCancelled();
    if (session.isClosed || session.isLayoutOwnerRetired) {
      throw const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.ownerRetired,
      );
    }
    final snapshot = session.snapshot;
    if (coverage.identity != snapshot.identity ||
        coverage.layoutId != snapshot.layoutId ||
        coverage.pageIndex != pageIndex) {
      throw StateError('Native view coverage identity changed');
    }
    validateForumBodyPreparedTextPageBinding(
      snapshot: snapshot,
      pageIndex: pageIndex,
      layoutId: snapshot.layoutId,
      fragments: fragments,
    );
    final view = NovelReaderNativePageView._(
      snapshot,
      pageIndex,
      List.unmodifiable(fragments),
      coverage,
    );
    view._bind(session, parent);
    return view;
  }

  NovelReaderNativePageView._(
    this.snapshot,
    this.pageIndex,
    this._fragments,
    this.coverage,
  );
  final ForumBodyTextPageSnapshot snapshot;
  final int pageIndex;
  final NovelReaderNativePageCoverage coverage;
  List<ForumBodyPreparedTextFragment> _fragments;
  NovelReaderNativePageViewState _state = NovelReaderNativePageViewState.owned;
  void Function()? _removeParent;
  StreamSubscription<void>? _retirement;
  StreamSubscription<int>? _owner;

  NovelReaderNativePageViewState get state => _state;
  bool get isReady =>
      _state == NovelReaderNativePageViewState.owned &&
      _fragments.every((fragment) => fragment.isActive);

  void _bind(
    ForumBodyTextPageSession session,
    NovelReaderPaginationCancellationToken parent,
  ) {
    final remove = parent.onCancel(close);
    if (_state != NovelReaderNativePageViewState.owned) {
      remove();
      return;
    }
    _removeParent = remove;
    _retirement = session.retirement.listen((_) => close(), onDone: close);
    _owner = session.layoutBudgetChanges.listen((_) {
      if (session.isClosed || session.isLayoutOwnerRetired) {
        close();
      }
    }, onDone: close);
    if (parent.isCancelled ||
        session.isClosed ||
        session.isLayoutOwnerRetired) {
      close();
    }
  }

  List<ForumBodyParagraphLease> takeLeases() {
    if (_fragments.any(
      (fragment) => fragment is! ForumBodyPreparedParagraphFragment,
    )) {
      throw StateError('Native view contains mixed fragments');
    }
    return [
      for (final fragment in takeFragments())
        (fragment as ForumBodyPreparedParagraphFragment).lease,
    ];
  }

  List<ForumBodyPreparedTextFragment> takeFragments() {
    if (_state != NovelReaderNativePageViewState.owned) {
      throw StateError('Native view leases already transferred or retired');
    }
    try {
      validateForumBodyPreparedTextPageBinding(
        snapshot: snapshot,
        pageIndex: pageIndex,
        layoutId: snapshot.layoutId,
        fragments: _fragments,
      );
      final fragments = _fragments;
      _fragments = const [];
      _state = NovelReaderNativePageViewState.transferred;
      _unbind();
      return fragments;
    } catch (_) {
      close();
      rethrow;
    }
  }

  void _unbind() {
    _removeParent?.call();
    _removeParent = null;
    final retirement = _retirement;
    final owner = _owner;
    _retirement = null;
    _owner = null;
    if (retirement != null) unawaited(retirement.cancel());
    if (owner != null) unawaited(owner.cancel());
  }

  void close() {
    if (_state == NovelReaderNativePageViewState.closed) return;
    _state = NovelReaderNativePageViewState.closed;
    _unbind();
    for (final fragment in _fragments) {
      fragment.close();
    }
    _fragments = const [];
  }
}

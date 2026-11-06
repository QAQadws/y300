import 'dart:async';

import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../services/novel_reader_pagination_cancellation.dart';
import 'novel_reader_native_page_coverage.dart';
import 'novel_reader_native_page_work.dart';

enum NovelReaderNativePageViewState { owned, transferred, closed }

/// Owns an unmounted, fully checked view. takeMount transfers ownership to
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
    NovelReaderNativePageWork? work,
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
      work,
      session.acquireTablePage(pageIndex),
    );
    view._bind(session, parent);
    return view;
  }

  NovelReaderNativePageView._(
    this.snapshot,
    this.pageIndex,
    this._fragments,
    this.coverage,
    this.work,
    this._table,
  );
  final ForumBodyTextPageSnapshot snapshot;
  final int pageIndex;
  final NovelReaderNativePageCoverage coverage;
  final NovelReaderNativePageWork? work;
  List<ForumBodyPreparedTextFragment> _fragments;
  WeakReference<List<ForumBodyPreparedTextFragment>>? _mountedText;
  ForumBodyTablePageLease? _table;
  NovelReaderNativePageViewState _state = NovelReaderNativePageViewState.owned;
  void Function()? _removeParent;
  StreamSubscription<void>? _retirement;
  StreamSubscription<int>? _owner;

  NovelReaderNativePageViewState get state => _state;
  bool get isReady =>
      _state == NovelReaderNativePageViewState.owned &&
      (_table?.isActive ?? true) &&
      _fragments.every((fragment) => fragment.isActive);

  /// The Surface still owns the exact text fragments transferred by this view.
  bool get hasLiveTextMount {
    final fragments = _mountedText?.target;
    return _state == NovelReaderNativePageViewState.transferred &&
        fragments != null &&
        fragments.every((fragment) => fragment.isActive);
  }

  bool matchesTextMount(List<ForumBodyPreparedTextFragment> fragments) =>
      _state == NovelReaderNativePageViewState.transferred &&
      identical(_mountedText?.target, fragments);

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
    if (_table != null) throw StateError('Native table requires a table mount');
    return takeMount().fragments;
  }

  ({
    List<ForumBodyPreparedTextFragment> fragments,
    ForumBodyTablePageLease? table,
  })
  takeMount() {
    if (_state != NovelReaderNativePageViewState.owned ||
        (_table?.isActive == false)) {
      throw StateError('Native view leases already transferred or retired');
    }
    try {
      validateForumBodyPreparedTextPageBinding(
        snapshot: snapshot,
        pageIndex: pageIndex,
        layoutId: snapshot.layoutId,
        fragments: _fragments,
      );
      final mount = (fragments: _fragments, table: _table);
      if (_table == null && !coverage.hasImages && coverage.hasLocations) {
        _mountedText = WeakReference(_fragments);
      }
      _fragments = const [];
      _table = null;
      _state = NovelReaderNativePageViewState.transferred;
      _unbind();
      return mount;
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
    _mountedText = null;
    _unbind();
    _table?.close();
    _table = null;
    for (final fragment in _fragments) {
      fragment.close();
    }
    _fragments = const [];
  }
}

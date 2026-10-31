import 'dart:async';

import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../services/novel_reader_pagination_cancellation.dart';
import 'novel_reader_native_page_coverage.dart';

enum NovelReaderNativePageViewState { owned, transferred, closed }

/// Owns an unmounted, fully checked view. takeLeases transfers ownership to
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
    final snapshot = session.snapshot;
    if (coverage.identity != snapshot.identity ||
        coverage.layoutId != snapshot.layoutId ||
        coverage.pageIndex != pageIndex) {
      throw StateError('Native view coverage identity changed');
    }
    validateForumBodyTextPageBinding(
      snapshot: snapshot,
      pageIndex: pageIndex,
      layoutId: snapshot.layoutId,
      leases: leases,
    );
    final view = NovelReaderNativePageView._(
      snapshot,
      pageIndex,
      List.unmodifiable(leases),
      coverage,
    );
    view._bind(session, parent);
    return view;
  }

  NovelReaderNativePageView._(
    this.snapshot,
    this.pageIndex,
    this._leases,
    this.coverage,
  );
  final ForumBodyTextPageSnapshot snapshot;
  final int pageIndex;
  final NovelReaderNativePageCoverage coverage;
  List<ForumBodyParagraphLease> _leases;
  NovelReaderNativePageViewState _state = NovelReaderNativePageViewState.owned;
  void Function()? _removeParent;
  StreamSubscription<void>? _retirement;
  StreamSubscription<int>? _owner;

  NovelReaderNativePageViewState get state => _state;
  bool get isReady =>
      _state == NovelReaderNativePageViewState.owned &&
      _leases.every((lease) => lease.isActive);

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
    if (_state != NovelReaderNativePageViewState.owned) {
      throw StateError('Native view leases already transferred or retired');
    }
    try {
      validateForumBodyTextPageBinding(
        snapshot: snapshot,
        pageIndex: pageIndex,
        layoutId: snapshot.layoutId,
        leases: _leases,
      );
      final leases = _leases;
      _leases = const [];
      _state = NovelReaderNativePageViewState.transferred;
      _unbind();
      return leases;
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
    for (final lease in _leases) {
      lease.release();
    }
    _leases = const [];
  }
}

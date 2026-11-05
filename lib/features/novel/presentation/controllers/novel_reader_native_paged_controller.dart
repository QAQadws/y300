import 'dart:async';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;

import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';

import '../models/novel_reader_chapter_turn.dart';
import '../models/novel_reader_native_anchor_map.dart';
import '../models/novel_reader_native_page_delivery.dart';
import '../models/novel_reader_native_page_view.dart';
import '../models/novel_reader_pagination_exception.dart';
import '../models/novel_reader_pagination_position.dart';
import '../services/novel_reader_native_page_hint_search.dart';
import '../services/novel_reader_native_page_view_job.dart';
import '../services/novel_reader_native_pagination_watchdog.dart';
import '../services/novel_reader_native_prefix_verifier.dart';
import '../services/novel_reader_native_restore_cursor.dart';
import '../services/novel_reader_native_source_run.dart';
import '../services/novel_reader_native_table_anchor_probe.dart';
import '../services/novel_reader_native_table_window_proof.dart';
import '../services/novel_reader_native_view_window.dart';
import '../services/novel_reader_native_work_scheduler.dart';
import '../services/novel_reader_pagination_cancellation.dart';
import '../services/novel_reader_pagination_demand.dart';
import '../services/novel_reader_pagination_performance_policy.dart';

enum NovelReaderNativePagedPhase {
  created,
  loading,
  ready,
  paused,
  empty,
  closed,
}

/// One native layout request. Owns scheduling/views/restore/deadlines, borrows
/// source/cache. Host keeps old mounted content and its box alive through reflow,
/// then retires its old session after replacement. Retry uses a NEW session and
/// controller, passing the old accepted prefix and stable key for verification.
/// No provider, protocol, mode preference, persistence or Widget is owned here.
final class NovelReaderNativePagedController {
  factory NovelReaderNativePagedController({
    required ForumBodyTextPageSession session,
    required NovelReaderNativeAnchorMap anchors,
    required NovelReaderProgressSnapshot position,
    required String paginationKey,
    required NovelReaderPaginationCancellationToken parent,
    NovelReaderTextAnchor? conversionAnchor,
    NovelReaderChapterEdge? entryEdge,
    ForumBodyTextPageSnapshot? previousPrefix,
    String? previousPaginationKey,
    NovelReaderNativeWorkScheduler scheduler =
        const NovelReaderNativeWorkScheduler(),
    NovelReaderPaginationPerformancePolicy performance =
        const NovelReaderPaginationPerformancePolicy(),
    NovelReaderNativeViewWindowLimits windowLimits =
        const NovelReaderNativeViewWindowLimits(),
    NovelReaderPaginationIdleScheduler? idleScheduler,
  }) {
    parent.throwIfCancelled();
    if (session.isClosed ||
        session.isLayoutOwnerRetired ||
        session.snapshot.identity != anchors.identity ||
        paginationKey.isEmpty ||
        (previousPrefix != null && previousPaginationKey == null)) {
      throw StateError('Native paged controller scope changed');
    }
    final controller = NovelReaderNativePagedController._(
      session,
      anchors,
      paginationKey,
      scheduler,
      entryEdge,
      NovelReaderPaginationDemand(idleScheduler: idleScheduler),
      NovelReaderNativeRestoreCursor(
        identity: anchors.identity,
        layoutId: session.snapshot.layoutId,
        episodeId: anchors.episodeId,
        paginationKey: paginationKey,
        position: position,
        conversionAnchor: conversionAnchor,
      ),
      position,
      conversionAnchor,
    );
    try {
      controller._window = NovelReaderNativeViewWindow(
        session: session,
        anchors: anchors,
        parent: controller._lifetime,
        centerPageIndex: 0,
        scheduler: scheduler,
        limits: windowLimits,
      );
      if (previousPrefix != null) {
        controller._verifier = NovelReaderNativePrefixVerifier(
          previous: previousPrefix,
          previousPaginationKey: previousPaginationKey!,
          incoming: session.snapshot,
          incomingPaginationKey: paginationKey,
        );
      }
      controller._watch = NovelReaderNativePaginationWatchdog(
        parent: controller._lifetime,
        policy: performance,
        onExpired: (error, _) => controller._pause(error),
      );
      controller._bind(session, parent);
      return controller;
    } catch (_) {
      controller.close();
      rethrow;
    }
  }

  NovelReaderNativePagedController._(
    this._session,
    this._anchors,
    this.paginationKey,
    this._scheduler,
    this._entryEdge,
    this._demand,
    this._restore,
    this._bootstrapPosition,
    this._bootstrapConversionAnchor,
  ) : episodeId = _anchors!.episodeId,
      _bootstrapEntry = _entryEdge,
      _snapshot = _session!.snapshot;
  ForumBodyTextPageSession? _session;
  NovelReaderNativeAnchorMap? _anchors;
  NovelReaderNativeWorkScheduler? _scheduler;
  NovelReaderPaginationDemand? _demand;
  NovelReaderNativeRestoreCursor? _restore;
  NovelReaderNativeViewWindow? _window;
  NovelReaderNativePaginationWatchdog? _watch;
  NovelReaderNativePrefixVerifier? _verifier;
  NovelReaderNativeSourceRun? _source;
  NovelReaderNativePageViewJob? _probe;
  NovelReaderPaginationCancellationToken? _anchorWork;
  ForumBodyTextPageSnapshot? _snapshot;
  final String paginationKey;
  final String episodeId;
  final _lifetime = NovelReaderPaginationCancellationToken();
  NovelReaderChapterEdge? _entryEdge;
  NovelReaderChapterEdge? _resolvedEntryEdge;
  NovelReaderNativeTargetWait? _ticket;
  NovelReaderNativePageDelivery? _target;
  NovelReaderNativePageDelivery? _visible;
  NovelReaderPaginationPosition? _lastPosition;
  NovelReaderProgressSnapshot? _bootstrapPosition;
  NovelReaderTextAnchor? _bootstrapConversionAnchor;
  NovelReaderChapterEdge? _bootstrapEntry;
  NovelReaderTextAnchor? _restoredAnchor;
  ({int request, int page, Rect bounds})? _tableFocus;
  int? _requestedPage;
  int _requestId = 0;
  int? _unavailableAnchorRevision;
  int _producerEpoch = 0;
  int _scannedPages = 0;
  bool _userNavigation = false;
  bool _readOnly = true;
  bool _prefixNavigation = false;
  bool _suspended = false;
  Object? _error;
  NovelReaderNativePagedPhase _phase = NovelReaderNativePagedPhase.created;
  StreamController<void>? _changes;
  StreamSubscription<void>? _windowChanges;
  StreamSubscription<void>? _retirement;
  StreamSubscription<int>? _owner;
  void Function()? _removeParent;

  NovelReaderNativePagedPhase get phase => _phase;
  bool get isClosed => _phase == NovelReaderNativePagedPhase.closed;
  bool get isSuspended => _suspended;
  Object? get error => _error;
  ForumBodyTextPageSnapshot? get snapshot => _snapshot;
  int? get requestedPageIndex => _requestedPage;

  /// Intent identity only; actual mounted coverage still owns confirmation.
  int get navigationRevision => _requestId;
  bool get hasPendingNavigation => _ticket != null;
  int? get unavailableAnchorRevision => _unavailableAnchorRevision;
  int? get visiblePageIndex => _visible?.pageIndex;
  NovelReaderNativePageView? get visibleView => _visible?.view;
  NovelReaderNativePageDelivery? get readyTarget => _target;
  Stream<void> get changes => isClosed
      ? const Stream<void>.empty()
      : (_changes ??= StreamController<void>.broadcast()).stream;
  NovelReaderNativePageView? viewForPage(int page) =>
      _window?.viewForPage(page);

  void start() {
    if (_phase != NovelReaderNativePagedPhase.created) {
      throw StateError('Native reader already started');
    }
    _phase = NovelReaderNativePagedPhase.loading;
    _requestId++;
    _ticket = _watch!.startTarget();
    _resolveStartEntry();
    _syncDemand();
    _restartProducer();
  }

  /// Replaces the single pending seek/turn. No position changes until UI ack.
  bool requestPage(int page) {
    if (isClosed ||
        _suspended ||
        _phase == NovelReaderNativePagedPhase.created ||
        page < 0 ||
        (_error != null && page >= _snapshot!.length) ||
        (_snapshot!.isComplete && page >= _snapshot!.length)) {
      return false;
    }
    _cancelAnchorWork();
    _unavailableAnchorRevision = null;
    _requestId++;
    _probe?.close();
    _probe = null;
    _restore?.close();
    _restore = null;
    _entryEdge = null;
    _resolvedEntryEdge = null;
    _restoredAnchor = null;
    _requestedPage = page;
    _target = null;
    _userNavigation = true;
    _readOnly = false;
    if (_error != null) {
      _startPublishedNavigation(page);
      _notify();
      return true;
    }
    _ticket = _watch!.startTarget();
    _window!.setCenter(page);
    _offerTarget();
    _syncDemand();
    _restartProducer();
    _notify();
    return true;
  }

  /// Explicit bookmark/search navigation uses observed coverage, never saved
  /// percentages or page guesses. Source and immutable prefix remain shared.
  bool requestAnchor(NovelReaderTextAnchor anchor) {
    if (isClosed ||
        _suspended ||
        _phase == NovelReaderNativePagedPhase.created ||
        _phase == NovelReaderNativePagedPhase.empty) {
      return false;
    }
    if (anchor.episodeId != episodeId ||
        (_anchors!
                .sourceCandidates(anchor, allowNodeCompatibility: true)
                .isEmpty &&
            _anchors!
                .imageCandidatePaths(anchor, allowNodeCompatibility: true)
                .isEmpty)) {
      cancelPendingNavigation();
      return false;
    }
    _cancelAnchorWork();
    _unavailableAnchorRevision = null;
    _requestId++;
    _probe?.close();
    _probe = null;
    _restore?.close();
    _restore = NovelReaderNativeRestoreCursor.forNavigation(
      identity: _anchors!.identity,
      layoutId: _snapshot!.layoutId,
      paginationKey: paginationKey,
      anchor: anchor,
    );
    _entryEdge = null;
    _resolvedEntryEdge = null;
    _restoredAnchor = anchor;
    _requestedPage = null;
    _scannedPages = 0;
    _target = null;
    _userNavigation = true;
    _readOnly = false;
    if (_error != null) {
      _startPublishedNavigation(_visible?.pageIndex ?? 0, resolveAnchor: true);
    } else {
      _ticket = _watch!.startTarget();
      _syncDemand();
      _restartProducer();
    }
    _notify();
    return true;
  }

  /// Opposite gesture/drag cancels automatic arrival without confirming a new
  /// position. Keep the last actual visible page and retire the old ticket.
  bool cancelPendingNavigation() {
    if (isClosed ||
        _suspended ||
        _ticket == null ||
        (_visible == null && _restore?.isExplicitNavigation != true) ||
        (_error != null && !_prefixNavigation)) {
      return false;
    }
    _cancelAnchorWork();
    _unavailableAnchorRevision = null;
    _requestId++;
    _target = null;
    _probe?.close();
    _probe = null;
    _restore?.close();
    _restore = null;
    _resolvedEntryEdge = null;
    if (_visible == null && _error == null) {
      _resetBootstrapRestore();
      _ticket = _watch!.startTarget();
      _resolveStartEntry();
      _syncDemand();
      _restartProducer();
      _notify();
      return true;
    }
    _requestedPage = _lastPosition?.pageIndex;
    _userNavigation = false;
    _readOnly = _lastPosition?.isReadOnlyCompatibilityRestore ?? true;
    _restoredAnchor = _lastPosition?.anchor;
    _entryEdge = null;
    _ticket = null;
    if (_error != null) {
      _prefixNavigation = false;
      _watch!.close();
      _window!.close();
      _notify();
      return true;
    }
    _watch!.markReadable(_watch!.startTarget());
    _window!.setCenter(_requestedPage!);
    _syncDemand();
    _restartProducer();
    _notify();
    return true;
  }

  /// Caller invokes after a real mounted/settled frame. Recheck original live
  /// leases, not just a successful preparation Future or a transferred marker.
  NovelReaderPaginationPosition? confirmVisible(
    NovelReaderNativePageDelivery delivery,
    List<ForumBodyParagraphLease> leases,
  ) {
    final fragments = _legacyFragments(delivery.view, leases);
    return fragments == null
        ? null
        : confirmPreparedVisible(delivery, fragments);
  }

  NovelReaderPaginationPosition? confirmPreparedVisible(
    NovelReaderNativePageDelivery delivery,
    List<ForumBodyPreparedTextFragment> fragments, {
    ForumBodyTablePageLease? table,
    NovelReaderNativeTableWindowProof? tableProof,
  }) {
    if (isClosed ||
        _suspended ||
        (_error != null && !_prefixNavigation) ||
        !identical(_target, delivery) ||
        delivery.requestId != _requestId ||
        delivery.view.state != NovelReaderNativePageViewState.transferred ||
        _session!.isClosed ||
        _session!.isLayoutOwnerRetired) {
      return null;
    }
    final tablePage = delivery.view.snapshot[delivery.pageIndex].table;
    if ((tablePage == null) != (table == null) ||
        (table != null &&
            !_acceptsTableProof(delivery.view, table, tableProof))) {
      return null;
    }
    try {
      validateForumBodyPreparedTextPageBinding(
        snapshot: delivery.view.snapshot,
        pageIndex: delivery.pageIndex,
        layoutId: _snapshot!.layoutId,
        fragments: fragments,
      );
    } on ForumBodyTextPageSurfaceException {
      return null;
    }
    final coverage = delivery.view.coverage;
    final anchor = delivery.restoredAnchor == null
        ? null
        : coverage.locate(delivery.restoredAnchor!);
    final actual =
        tableProof?.anchor ??
        anchor?.anchor ??
        (coverage.hasLocations ? coverage.locations.first.anchor : null);
    final wholePage =
        table == null &&
        actual != null &&
        _wholePageVisible(delivery, fragments);
    final unmatchedTableRestore =
        tableProof != null &&
        delivery.restoredAnchor?.hasCanonicalTextOffset == true &&
        !tableProof.matchesPreferred;
    _visible = delivery;
    _target = null;
    _phase = _error == null
        ? NovelReaderNativePagedPhase.ready
        : NovelReaderNativePagedPhase.paused;
    _prefixNavigation = false;
    if (_ticket != null) _watch!.markReadable(_ticket!);
    _ticket = null;
    _syncDemand();
    _notify();
    final entry = delivery.chapterEntryEdge;
    final entryArrived =
        delivery.hasUserNavigated &&
        ((entry == NovelReaderChapterEdge.start && delivery.pageIndex == 0) ||
            (entry == NovelReaderChapterEdge.end &&
                _snapshot!.isComplete &&
                delivery.pageIndex == _snapshot!.length - 1));
    final position = NovelReaderPaginationPosition(
      episodeId: episodeId,
      paginationKey: paginationKey,
      pageIndex: delivery.pageIndex,
      pageCount: _snapshot!.length,
      isPageCountFinal: _snapshot!.isComplete,
      anchor: (actual ?? NovelReaderTextAnchor(episodeId: episodeId)).copyWith(
        pageIndex: delivery.pageIndex,
      ),
      isReadOnlyCompatibilityRestore:
          delivery.isReadOnlyCompatibilityRestore ||
          unmatchedTableRestore ||
          actual == null,
      hasUserNavigated:
          delivery.hasUserNavigated &&
          !(delivery.tableFocus != null && unmatchedTableRestore),
      isBodyEndVisible: wholePage,
      isWholeBodyVisible: wholePage,
      appliedChapterEntry: entryArrived ? entry : null,
    );
    _entryEdge = null;
    _resolvedEntryEdge = null;
    _tableFocus = null;
    _lastPosition = position;
    _bootstrapPosition = null;
    _bootstrapConversionAnchor = null;
    _bootstrapEntry = null;
    return position;
  }

  Future<NovelReaderNativeTableWindowProof?> prepareTableWindow(
    ForumBodyTablePageLease table,
    ForumBodyTableVisibleWindow window,
    NovelReaderPaginationCancellationToken token, {
    NovelReaderTextAnchor? preferred,
  }) {
    if (isClosed ||
        _suspended ||
        !window.isCurrent ||
        !identical(window.layout, table.layout) ||
        !_session!.ownsTablePageLease(table.pageIndex, table)) {
      return Future.value(null);
    }
    return NovelReaderNativeTableWindowProof.prepare(
      window: window,
      anchors: _anchors!,
      scheduler: _scheduler!,
      token: token,
      preferred: preferred,
    );
  }

  NovelReaderPaginationPosition? refreshTableVisible(
    NovelReaderNativePageView view,
    ForumBodyTablePageLease table,
    NovelReaderNativeTableWindowProof proof,
  ) {
    final previous = _lastPosition;
    final anchor = proof.anchor;
    if (isClosed ||
        _suspended ||
        _ticket != null ||
        _target != null ||
        !identical(_visible?.view, view) ||
        previous == null ||
        anchor == null ||
        !proof.window.hasUserScrolled ||
        !_acceptsTableProof(view, table, proof)) {
      return null;
    }
    if (!previous.isReadOnlyCompatibilityRestore &&
        anchor.nodeId == previous.anchor.nodeId &&
        anchor.textOffset == previous.anchor.textOffset &&
        anchor.formatVersion == previous.anchor.formatVersion &&
        anchor.textIdentity == previous.anchor.textIdentity) {
      return null;
    }
    return _lastPosition = NovelReaderPaginationPosition(
      episodeId: episodeId,
      paginationKey: paginationKey,
      pageIndex: view.pageIndex,
      pageCount: _snapshot!.length,
      isPageCountFinal: _snapshot!.isComplete,
      anchor: anchor.copyWith(pageIndex: view.pageIndex),
      hasUserNavigated: true,
      isWholeBodyVisible: false,
      isBodyEndVisible: false,
    );
  }

  bool _acceptsTableProof(
    NovelReaderNativePageView view,
    ForumBodyTablePageLease table,
    NovelReaderNativeTableWindowProof? proof,
  ) =>
      proof != null &&
      proof.isCurrent &&
      identical(table.layout, proof.window.layout) &&
      _session!.ownsTablePageLease(view.pageIndex, table);

  void reportTablePresentationFailure(
    NovelReaderNativePageView view,
    ForumBodyTablePageLease table,
    Object error,
  ) {
    if (isClosed ||
        _suspended ||
        !(identical(view, _target?.view) || identical(view, _visible?.view)) ||
        !_session!.ownsTablePageLease(view.pageIndex, table)) {
      return;
    }
    _pause(error);
  }

  /// A later accepted image frame changes visibility, never reading authority,
  /// the saved anchor, or a consumed chapter-entry intent.
  NovelReaderPaginationPosition? refreshPreparedVisible(
    NovelReaderNativePageView view,
    List<ForumBodyPreparedTextFragment> fragments,
  ) {
    final visible = _visible, previous = _lastPosition;
    if (isClosed ||
        !view.coverage.hasImages ||
        _suspended ||
        _ticket != null ||
        _target != null ||
        visible == null ||
        previous == null ||
        !identical(visible.view, view) ||
        _session!.isClosed ||
        _session!.isLayoutOwnerRetired) {
      return null;
    }
    // A failed source keeps this exact visible view through suspend/resume,
    // even as navigation requests retire. Refresh pixels, never its authority.
    try {
      validateForumBodyPreparedTextPageBinding(
        snapshot: view.snapshot,
        pageIndex: view.pageIndex,
        layoutId: _snapshot!.layoutId,
        fragments: fragments,
      );
    } on ForumBodyTextPageSurfaceException {
      return null;
    }
    final whole =
        view.coverage.hasLocations && _wholePageVisible(visible, fragments);
    if (whole == previous.isWholeBodyVisible &&
        whole == previous.isBodyEndVisible &&
        previous.pageCount == _snapshot!.length &&
        previous.isPageCountFinal == _snapshot!.isComplete) {
      return null;
    }
    return _lastPosition = NovelReaderPaginationPosition(
      episodeId: previous.episodeId,
      paginationKey: previous.paginationKey,
      pageIndex: previous.pageIndex,
      pageCount: _snapshot!.length,
      isPageCountFinal: _snapshot!.isComplete,
      anchor: previous.anchor,
      isReadOnlyCompatibilityRestore: previous.isReadOnlyCompatibilityRestore,
      hasUserNavigated: previous.hasUserNavigated,
      isWholeBodyVisible: whole,
      isBodyEndVisible: whole,
    );
  }

  /// Retire work and pending navigation without closing source/native leases.
  /// A hidden surface cannot acknowledge a position or consume deadline time.
  bool suspend() {
    if (isClosed ||
        _suspended ||
        _phase == NovelReaderNativePagedPhase.created) {
      return false;
    }
    _suspended = true;
    _resolvedEntryEdge = null;
    _cancelAnchorWork();
    _requestId++;
    _producerEpoch++;
    _source?.close();
    _source = null;
    _probe?.close();
    _probe = null;
    _window!.close();
    if (_watch?.isClosed == false) _watch!.setSuspended(true);
    _ticket = null;
    _target = null;
    _prefixNavigation = false;
    _userNavigation = false;
    _restore?.close();
    _restore = null;
    final position = _lastPosition;
    if (position != null) {
      _requestedPage = position.pageIndex;
      _readOnly = position.isReadOnlyCompatibilityRestore;
      _restoredAnchor = position.anchor;
      _entryEdge = null;
    } else {
      // A seek issued before first paint must not revive when the route returns.
      _resetBootstrapRestore();
    }
    _notify();
    return true;
  }

  /// Continue the same immutable prefix/cursor after Host validates the scope.
  /// Source failure remains paused; only explicit retry can replace that source.
  bool resume() {
    if (isClosed || !_suspended) return false;
    _suspended = false;
    if (_error != null || _phase == NovelReaderNativePagedPhase.empty) {
      _notify();
      return true;
    }
    final old = _window!;
    final subscription = _windowChanges;
    if (subscription != null) unawaited(subscription.cancel());
    _window = NovelReaderNativeViewWindow(
      session: _session!,
      anchors: _anchors!,
      parent: _lifetime,
      centerPageIndex: _requestedPage ?? 0,
      scheduler: _scheduler!,
      limits: old.limits,
      jobLimits: old.jobLimits,
    );
    _windowChanges = _window!.changes.listen((_) => _offerTarget());
    _watch!.setSuspended(false);
    _ticket = _watch!.startTarget();
    _phase = NovelReaderNativePagedPhase.loading;
    _resolveStartEntry();
    _syncDemand();
    _restartProducer();
    _notify();
    return true;
  }

  void forgetPage(int page, NovelReaderNativePageView view) {
    final retryNeighbors = _window?.forgetPage(page, view) ?? false;
    if (identical(_visible?.view, view)) _visible = null;
    if (identical(_target?.view, view)) {
      _target = null;
      if (!isClosed && !_suspended) {
        if (_error == null) {
          _restartProducer();
        } else if (_prefixNavigation) {
          unawaited(
            _preparePublishedTarget(_window!, _requestId, afterFrame: true),
          );
        }
      }
    } else if (retryNeighbors && !isClosed && !_suspended && _error == null) {
      // At EOF there may be no more source publications to revisit optional
      // pressure. Only an actual UI unmount triggers this retry, not our own
      // preparation rollbacks. The source's first yield lets Surface release.
      _restartProducer();
    }
  }

  /// Only the mounted viewport calls this after an accepted forward chapter
  /// command. EOF metadata alone cannot grant navigation/completion authority.
  NovelReaderPaginationPosition? confirmChapterEndNavigation(
    NovelReaderNativePageView view,
    List<ForumBodyParagraphLease> leases,
  ) {
    final fragments = _legacyFragments(view, leases);
    return fragments == null
        ? null
        : confirmPreparedChapterEndNavigation(view, fragments);
  }

  NovelReaderPaginationPosition? confirmPreparedChapterEndNavigation(
    NovelReaderNativePageView view,
    List<ForumBodyPreparedTextFragment> fragments,
  ) {
    if (isClosed ||
        _suspended ||
        _ticket != null ||
        !identical(_visible?.view, view) ||
        _snapshot?.isComplete != true ||
        view.pageIndex != _snapshot!.length - 1 ||
        !view.coverage.hasLocations) {
      return null;
    }
    try {
      validateForumBodyPreparedTextPageBinding(
        snapshot: view.snapshot,
        pageIndex: view.pageIndex,
        layoutId: _snapshot!.layoutId,
        fragments: fragments,
      );
    } on ForumBodyTextPageSurfaceException {
      return null;
    }
    final delivery = NovelReaderNativePageDelivery(
      requestId: _requestId + 1,
      view: view,
      isReadOnlyCompatibilityRestore: false,
      hasUserNavigated: true,
      restoredAnchor: _lastPosition?.anchor,
    );
    if (!_wholePageVisible(delivery, fragments)) return null;
    _requestId++;
    _target = delivery;
    _prefixNavigation = _error != null;
    return confirmPreparedVisible(delivery, fragments);
  }

  void _startPublishedNavigation(int page, {bool resolveAnchor = false}) {
    final old = _window!;
    final limits = old.limits;
    final policy = _watch!.policy;
    old.close();
    final subscription = _windowChanges;
    if (subscription != null) unawaited(subscription.cancel());
    _windowChanges = null;
    _watch!.close();
    _prefixNavigation = true;
    try {
      _watch = NovelReaderNativePaginationWatchdog(
        parent: _lifetime,
        policy: policy,
        onExpired: (error, _) => _pause(error),
      );
      // This lane is deliberately finite: it cannot advance source or wait for
      // new pages. Keep a target deadline but never restart a background timer.
      // Completion here belongs to this closed workload, not the body snapshot.
      _watch!.publication(pageCount: _snapshot!.length, isComplete: true);
      _ticket = _watch!.startTarget();
      final window = NovelReaderNativeViewWindow(
        session: _session!,
        anchors: _anchors!,
        parent: _lifetime,
        scheduler: _scheduler!,
        centerPageIndex: page,
        limits: NovelReaderNativeViewWindowLimits(
          radius: 0,
          maxRetainedFragments: limits.maxRetainedFragments,
          maxRetainedCoveragePoints: limits.maxRetainedCoveragePoints,
        ),
        jobLimits: old.jobLimits,
      );
      _window = window;
      _windowChanges = window.changes.listen((_) => _offerTarget());
      if (resolveAnchor) {
        unawaited(
          _preparePublishedAnchor(window, _requestId, ++_producerEpoch),
        );
      } else {
        unawaited(_preparePublishedTarget(window, _requestId));
      }
    } catch (error) {
      _pause(error);
    }
  }

  Future<void> _preparePublishedAnchor(
    NovelReaderNativeViewWindow window,
    int requestId,
    int epoch,
  ) async {
    final token = _anchorWork = NovelReaderPaginationCancellationToken();
    final remove = _lifetime.onCancel(token.cancel);
    bool current() =>
        !isClosed &&
        !_suspended &&
        _prefixNavigation &&
        requestId == _requestId &&
        identical(window, _window);
    try {
      await _resolveInitial(epoch, _snapshot!, token);
      _guard(epoch, token);
      if (!current()) return;
      if (_requestedPage == null) {
        await _anchorUnavailable(epoch, _snapshot!, token);
        return;
      }
      window.setCenter(_requestedPage!);
      await window.prepareAvailable();
      _guard(epoch, token);
      if (current()) _offerTarget();
    } catch (error) {
      if (current()) _pause(error);
    } finally {
      remove();
      token.cancel();
      if (identical(_anchorWork, token)) _anchorWork = null;
    }
  }

  void _cancelAnchorWork() {
    _anchorWork?.cancel();
    _anchorWork = null;
  }

  void _resetBootstrapRestore() {
    _resolvedEntryEdge = null;
    _userNavigation = false;
    _restore = NovelReaderNativeRestoreCursor(
      identity: _anchors!.identity,
      layoutId: _snapshot!.layoutId,
      episodeId: episodeId,
      paginationKey: paginationKey,
      position: _bootstrapPosition!,
      conversionAnchor: _bootstrapConversionAnchor,
    );
    _requestedPage = null;
    _readOnly = true;
    _restoredAnchor = null;
    _entryEdge = _bootstrapEntry;
    _scannedPages = 0;
  }

  void _resolveStartEntry() {
    if (_entryEdge != NovelReaderChapterEdge.start) return;
    _resolvedEntryEdge = NovelReaderChapterEdge.start;
    _requestedPage = 0;
    _userNavigation = true;
    _readOnly = false;
    _restore?.close();
    _restore = null;
  }

  /// An unavailable target is a command result, not a failed source. Retain
  /// actual visible authority; before first paint return to bootstrap input.
  Future<bool> _anchorUnavailable(
    int epoch,
    ForumBodyTextPageSnapshot prefix,
    NovelReaderPaginationCancellationToken token,
  ) async {
    _unavailableAnchorRevision = _requestId;
    final ticket = _ticket;
    if (ticket != null) _watch!.cancelTarget(ticket);
    _ticket = null;
    _target = null;
    _tableFocus = null;
    _restore?.close();
    _restore = null;
    _userNavigation = false;
    final position = _lastPosition;
    if (position != null || _error != null) {
      _requestedPage = position?.pageIndex;
      _restoredAnchor = position?.anchor;
      _readOnly = position?.isReadOnlyCompatibilityRestore ?? true;
      if (_error != null) {
        _prefixNavigation = false;
        _window!.close();
        _watch!.close();
      }
      _syncDemand();
      _notify();
      return false;
    }
    _resetBootstrapRestore();
    _ticket = _watch!.startTarget();
    _resolveStartEntry();
    if (_entryEdge == NovelReaderChapterEdge.end &&
        prefix.isComplete &&
        prefix.isNotEmpty) {
      _requestedPage = prefix.length - 1;
      _resolvedEntryEdge = NovelReaderChapterEdge.end;
      _entryEdge = null;
      _userNavigation = true;
      _readOnly = false;
      _restore?.close();
      _restore = null;
    }
    if (_requestedPage == null && _entryEdge != NovelReaderChapterEdge.end) {
      await _resolveInitial(epoch, prefix, token);
      _guard(epoch, token);
    }
    _syncDemand();
    _notify();
    return true;
  }

  Future<void> _preparePublishedTarget(
    NovelReaderNativeViewWindow window,
    int requestId, {
    bool afterFrame = false,
  }) async {
    bool current() =>
        !isClosed &&
        !_suspended &&
        _prefixNavigation &&
        requestId == _requestId &&
        identical(_window, window);
    try {
      if (afterFrame) await _scheduler!.nextFrame(_lifetime);
      if (!current()) return;
      await window.prepareAvailable();
      if (current()) _offerTarget();
    } catch (error) {
      if (current()) _pause(error);
    }
  }

  bool _wholePageVisible(
    NovelReaderNativePageDelivery delivery,
    List<ForumBodyPreparedTextFragment> fragments,
  ) {
    final snapshot = delivery.view.snapshot;
    if (delivery.view.coverage.hasClippedGlyphs ||
        delivery.view.coverage.hasClippedResources ||
        fragments.any((fragment) => !fragment.hasRenderedImages)) {
      return false;
    }
    // Coverage already checked actual visible glyphs against both clips.
    // Native vertical font extents also include leading and rounding overhang;
    // those extents are not the painted fragment's viewport rectangle.
    for (final (index, fragment)
        in snapshot[delivery.pageIndex].fragments.indexed) {
      if (fragment.top < -precisionErrorTolerance ||
          fragment.top + fragment.height >
              snapshot.height + precisionErrorTolerance) {
        return false;
      }
      for (final line in fragments[index].lines) {
        if (line.left < -precisionErrorTolerance ||
            line.left + line.width > fragment.width + precisionErrorTolerance ||
            fragment.left + line.left < -precisionErrorTolerance ||
            fragment.left + line.left + line.width >
                snapshot.width + precisionErrorTolerance) {
          return false;
        }
      }
    }
    return true;
  }

  List<ForumBodyPreparedTextFragment>? _legacyFragments(
    NovelReaderNativePageView view,
    List<ForumBodyParagraphLease> leases,
  ) {
    try {
      validateForumBodyTextPageBinding(
        snapshot: view.snapshot,
        pageIndex: view.pageIndex,
        layoutId: view.snapshot.layoutId,
        leases: leases,
      );
      return [
        for (final (index, lease) in leases.indexed)
          ForumBodyPreparedTextFragment.paragraph(
            lease: lease,
            startLine: view.snapshot[view.pageIndex].fragments[index].startLine,
            endLine: view.snapshot[view.pageIndex].fragments[index].endLine,
          ),
      ];
    } on ForumBodyTextPageSurfaceException {
      return null;
    }
  }

  void _restartProducer() {
    final epoch = ++_producerEpoch;
    _source?.close();
    try {
      final source = NovelReaderNativeSourceRun(
        session: _session!,
        demand: _demand!,
        parent: _lifetime,
        scheduler: _scheduler!,
        onPublication: (prefix, token) => _publication(epoch, prefix, token),
      );
      _source = source;
      unawaited(
        source.run().then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            if (!isClosed && epoch == _producerEpoch) _pause(error);
          },
        ),
      );
    } catch (error) {
      _pause(error);
    }
  }

  Future<void> _publication(
    int epoch,
    ForumBodyTextPageSnapshot prefix,
    NovelReaderPaginationCancellationToken token,
  ) async {
    _guard(epoch, token);
    final verifier = _verifier;
    if (verifier != null) {
      if (verifier.state != NovelReaderNativePrefixState.mismatched &&
          verifier.state != NovelReaderNativePrefixState.matched) {
        verifier.update(prefix, paginationKey: paginationKey);
      }
      while (verifier.state == NovelReaderNativePrefixState.active) {
        verifier.advance(maxPages: 8, maxFragments: 32);
        _guard(epoch, token);
        if (verifier.state == NovelReaderNativePrefixState.active) {
          await _scheduler!.nextFrame(token);
        }
      }
      if (verifier.state == NovelReaderNativePrefixState.mismatched) {
        throw const NovelReaderPaginationException(
          code: 'paginationPrefixMismatch',
          message: 'Native retry prefix changed.',
        );
      }
      if (verifier.state == NovelReaderNativePrefixState.matched) {
        verifier.close();
        _verifier = null;
      }
    }
    _guard(epoch, token);
    _snapshot = prefix;
    _watch!.publication(
      pageCount: prefix.length,
      isComplete: prefix.isComplete,
    );
    if (prefix.isComplete && prefix.isEmpty) {
      if (_restore?.isExplicitNavigation == true) {
        _unavailableAnchorRevision = _requestId;
        _restore?.close();
        _restore = null;
      }
      _phase = NovelReaderNativePagedPhase.empty;
      _ticket = null;
      _watch!.close();
      _notify();
      return;
    }
    if (_entryEdge == NovelReaderChapterEdge.end && prefix.isComplete) {
      _requestedPage = prefix.length - 1;
      _resolvedEntryEdge = NovelReaderChapterEdge.end;
      _entryEdge = null;
      _userNavigation = true;
      _readOnly = false;
      _restore?.close();
      _restore = null;
    }
    if (_requestedPage == null && _entryEdge != NovelReaderChapterEdge.end) {
      await _resolveInitial(epoch, prefix, token);
      _guard(epoch, token);
      if (_requestedPage == null &&
          prefix.isComplete &&
          _restore?.isExplicitNavigation == true) {
        final fallback = await _anchorUnavailable(epoch, prefix, token);
        _guard(epoch, token);
        if (!fallback) return;
      }
    }
    final requested = _requestedPage;
    if (requested != null) {
      if (prefix.isComplete && requested >= prefix.length) {
        throw const NovelReaderPaginationException(
          code: 'paginationTargetUnavailable',
          message: 'The requested native page is unavailable.',
        );
      }
      _window!.setCenter(requested);
      await _window!.prepareAvailable();
      _guard(epoch, token);
      _offerTarget();
    }
    _syncDemand();
    _notify();
  }

  Future<void> _resolveInitial(
    int epoch,
    ForumBodyTextPageSnapshot prefix,
    NovelReaderPaginationCancellationToken token,
  ) async {
    final restore = _restore!;
    final target = restore.targetAnchor;
    if (target != null && _scannedPages < prefix.length) {
      final search = NovelReaderNativePageHintSearch(
        snapshot: prefix,
        layoutId: prefix.layoutId,
        anchors: _anchors!,
        anchor: target,
        startPageIndex: _scannedPages,
        allowNodeCompatibility: !restore.isConversionRestore,
      );
      try {
        while (!search.isComplete && !restore.isResolved) {
          search.advance(maxPages: 8, maxFragments: 32);
          final candidates = search.takeCandidates().toList()
            ..sort((a, b) {
              final rank = b.kind.index.compareTo(a.kind.index);
              return rank != 0 ? rank : a.pageIndex.compareTo(b.pageIndex);
            });
          for (final hint in candidates) {
            if (prefix[hint.pageIndex].table != null) {
              final candidate = await probeNovelReaderNativeTableAnchor(
                session: _session!,
                anchors: _anchors!,
                pageIndex: hint.pageIndex,
                target: target,
                allowNodeCompatibility: !restore.isConversionRestore,
                scheduler: _scheduler!,
                token: token,
              );
              _guard(epoch, token);
              if (candidate == null) continue;
              restore.observeTableProbe(
                snapshot: prefix,
                pageIndex: hint.pageIndex,
                candidate: candidate.anchor,
              );
              final result = restore.resolve(prefix);
              if (result == null) continue;
              _requestedPage = result.pageIndex;
              _readOnly = result.isReadOnlyCompatibilityRestore;
              if (result.pageIndex == hint.pageIndex) {
                _restoredAnchor = candidate.anchor;
                _tableFocus = (
                  request: _requestId,
                  page: result.pageIndex,
                  bounds: candidate.bounds,
                );
              } else {
                _restoredAnchor = restore.resolvedNavigationAnchor ?? target;
              }
              break;
            }
            final job = NovelReaderNativePageViewJob(
              session: _session!,
              anchors: _anchors!,
              pageIndex: hint.pageIndex,
              parent: _lifetime,
              scheduler: _scheduler!,
            );
            _probe = job;
            final removeJobCancel = token.onCancel(job.close);
            NovelReaderNativePageView? view;
            try {
              view = await job.run();
              _guard(epoch, token);
              if (!view.isReady) {
                throw StateError('Native restore view retired');
              }
              restore.observe(snapshot: prefix, coverage: view.coverage);
              // Exhaust actual canonical candidates before permitting EOF or
              // layout/percentage compatibility to latch a different page.
              final result =
                  view.coverage.locate(target) != null ||
                      (!restore.isConversionRestore &&
                          !_anchors!.hasVerifiedTextIdentity(target))
                  ? restore.resolve(prefix)
                  : null;
              if (result != null) {
                _requestedPage = result.pageIndex;
                _readOnly = result.isReadOnlyCompatibilityRestore;
                _restoredAnchor = restore.resolvedNavigationAnchor ?? target;
                if (result.pageIndex == view.pageIndex) {
                  _window!.setCenter(result.pageIndex);
                  _window!.adoptTarget(view);
                  view = null;
                }
                break;
              }
            } finally {
              removeJobCancel();
              view?.close();
              job.close();
              if (identical(_probe, job)) _probe = null;
            }
          }
          if (!search.isComplete && !restore.isResolved) {
            await _scheduler!.nextFrame(token);
          }
          _guard(epoch, token);
        }
        _scannedPages = search.nextPageIndex;
      } finally {
        search.close();
      }
    }
    if (_requestedPage == null) {
      final result = restore.resolve(prefix);
      if (result != null) {
        _requestedPage = result.pageIndex;
        _readOnly = result.isReadOnlyCompatibilityRestore;
        _restoredAnchor = restore.resolvedNavigationAnchor ?? target;
      }
    }
  }

  void _offerTarget() {
    if (isClosed ||
        _suspended ||
        (_error != null && !_prefixNavigation) ||
        _ticket == null ||
        _requestedPage == null) {
      return;
    }
    final view = _window?.viewForPage(_requestedPage!);
    if (view == null ||
        view.pageIndex >= _snapshot!.length ||
        identical(_target?.view, view)) {
      return;
    }
    final focus = _tableFocus;
    _target = NovelReaderNativePageDelivery(
      requestId: _requestId,
      view: view,
      isReadOnlyCompatibilityRestore: _readOnly,
      hasUserNavigated: _userNavigation,
      restoredAnchor: _restoredAnchor,
      tableFocus:
          focus != null &&
              focus.request == _requestId &&
              focus.page == view.pageIndex
          ? focus.bounds
          : null,
      chapterEntryEdge: _resolvedEntryEdge,
    );
    _notify();
  }

  void _syncDemand() => _demand?.update(
    targetPending: _ticket != null,
    pageIndex: _requestedPage ?? _visible?.pageIndex ?? 0,
    requireComplete:
        _entryEdge == NovelReaderChapterEdge.end ||
        (_restore?.requiresCompletePageCount ?? false),
  );
  void _syncIdle() {
    if (_watch?.isClosed == false) _watch!.setDeferring(_demand!.isDeferring);
  }

  void _guard(int epoch, NovelReaderPaginationCancellationToken token) {
    token.throwIfCancelled();
    _lifetime.throwIfCancelled();
    if (isClosed ||
        _suspended ||
        epoch != _producerEpoch ||
        (_error != null && !_prefixNavigation)) {
      throw const NovelReaderPaginationException(
        code: 'paginationCancelled',
        message: 'Native reader request retired.',
      );
    }
  }

  void _pause(Object error) {
    if (isClosed) return;
    _resolvedEntryEdge = null;
    _error = error;
    _prefixNavigation = false;
    _phase = NovelReaderNativePagedPhase.paused;
    _producerEpoch++;
    _cancelAnchorWork();
    _source?.close();
    _source = null;
    _probe?.close();
    _probe = null;
    _watch?.close();
    _ticket = null;
    _target = null;
    _window?.close();
    _notify();
  }

  void _notify() => _changes?.add(null);
  void _bind(
    ForumBodyTextPageSession session,
    NovelReaderPaginationCancellationToken parent,
  ) {
    _demand!.addListener(_syncIdle);
    _windowChanges = _window!.changes.listen((_) => _offerTarget());
    _retirement = session.retirement.listen((_) => close(), onDone: close);
    _owner = session.layoutBudgetChanges.listen((_) {
      if (session.isLayoutOwnerRetired) close();
    }, onDone: close);
    final remove = parent.onCancel(close);
    if (isClosed) {
      remove();
    } else {
      _removeParent = remove;
    }
  }

  void close() {
    if (isClosed) return;
    _phase = NovelReaderNativePagedPhase.closed;
    _producerEpoch++;
    _cancelAnchorWork();
    _removeParent?.call();
    _removeParent = null;
    _lifetime.cancel();
    _source?.close();
    _source = null;
    _probe?.close();
    _probe = null;
    _window?.close();
    _window = null;
    _watch?.close();
    _watch = null;
    _restore?.close();
    _restore = null;
    _verifier?.close();
    _verifier = null;
    _demand?.removeListener(_syncIdle);
    _demand?.dispose();
    _demand = null;
    final subscriptions = [_windowChanges, _retirement, _owner];
    _windowChanges = null;
    _retirement = null;
    _owner = null;
    for (final subscription in subscriptions) {
      if (subscription != null) unawaited(subscription.cancel());
    }
    _session = null;
    _anchors = null;
    _scheduler = null;
    _snapshot = null;
    _target = null;
    _visible = null;
    _lastPosition = null;
    _unavailableAnchorRevision = null;
    _bootstrapPosition = null;
    _bootstrapConversionAnchor = null;
    _bootstrapEntry = null;
    _resolvedEntryEdge = null;
    _prefixNavigation = false;
    _restoredAnchor = null;
    _tableFocus = null;
    _ticket = null;
    _error = null;
    final changes = _changes;
    _changes = null;
    if (changes != null) unawaited(changes.close());
  }
}

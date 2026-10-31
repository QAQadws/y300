import 'dart:async';

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
  ) : episodeId = _anchors!.episodeId,
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
  ForumBodyTextPageSnapshot? _snapshot;
  final String paginationKey;
  final String episodeId;
  final _lifetime = NovelReaderPaginationCancellationToken();
  NovelReaderChapterEdge? _entryEdge;
  NovelReaderNativeTargetWait? _ticket;
  NovelReaderNativePageDelivery? _target;
  NovelReaderNativePageDelivery? _visible;
  NovelReaderTextAnchor? _restoredAnchor;
  int? _requestedPage;
  int _requestId = 0;
  int _producerEpoch = 0;
  int _scannedPages = 0;
  bool _userNavigation = false;
  bool _readOnly = true;
  bool _prefixNavigation = false;
  Object? _error;
  NovelReaderNativePagedPhase _phase = NovelReaderNativePagedPhase.created;
  StreamController<void>? _changes;
  StreamSubscription<void>? _windowChanges;
  StreamSubscription<void>? _retirement;
  StreamSubscription<int>? _owner;
  void Function()? _removeParent;

  NovelReaderNativePagedPhase get phase => _phase;
  bool get isClosed => _phase == NovelReaderNativePagedPhase.closed;
  Object? get error => _error;
  ForumBodyTextPageSnapshot? get snapshot => _snapshot;
  int? get requestedPageIndex => _requestedPage;
  int? get visiblePageIndex => _visible?.pageIndex;
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
    if (_entryEdge == NovelReaderChapterEdge.start) {
      _requestedPage = 0;
      _userNavigation = true;
      _readOnly = false;
      _restore?.close();
      _restore = null;
    }
    _syncDemand();
    _restartProducer();
  }

  /// Replaces the single pending seek/turn. No position changes until UI ack.
  bool requestPage(int page) {
    if (isClosed ||
        _phase == NovelReaderNativePagedPhase.created ||
        page < 0 ||
        (_error != null && page >= _snapshot!.length) ||
        (_snapshot!.isComplete && page >= _snapshot!.length)) {
      return false;
    }
    _requestId++;
    _probe?.close();
    _probe = null;
    _restore?.close();
    _restore = null;
    _entryEdge = null;
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

  /// Opposite gesture/drag cancels automatic arrival without confirming a new
  /// position. Keep the last actual visible page and retire the old ticket.
  bool cancelPendingNavigation() {
    if (isClosed ||
        _ticket == null ||
        _visible == null ||
        (_error != null && !_prefixNavigation)) {
      return false;
    }
    _requestId++;
    _target = null;
    _probe?.close();
    _probe = null;
    _requestedPage = _visible!.pageIndex;
    _userNavigation = false;
    _readOnly = _visible!.isReadOnlyCompatibilityRestore;
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
    if (isClosed ||
        (_error != null && !_prefixNavigation) ||
        !identical(_target, delivery) ||
        delivery.requestId != _requestId ||
        delivery.view.state != NovelReaderNativePageViewState.transferred ||
        _session!.isClosed ||
        _session!.isLayoutOwnerRetired) {
      return null;
    }
    try {
      validateForumBodyTextPageBinding(
        snapshot: delivery.view.snapshot,
        pageIndex: delivery.pageIndex,
        layoutId: _snapshot!.layoutId,
        leases: leases,
      );
    } on ForumBodyTextPageSurfaceException {
      return null;
    }
    final coverage = delivery.view.coverage;
    final anchor = delivery.restoredAnchor == null
        ? null
        : coverage.locate(delivery.restoredAnchor!);
    final actual =
        anchor?.anchor ??
        (coverage.points.isEmpty ? null : coverage.points.first.anchor);
    final wholePage = actual != null && _wholePageVisible(delivery, leases);
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
    return NovelReaderPaginationPosition(
      episodeId: episodeId,
      paginationKey: paginationKey,
      pageIndex: delivery.pageIndex,
      pageCount: _snapshot!.length,
      isPageCountFinal: _snapshot!.isComplete,
      anchor: (actual ?? NovelReaderTextAnchor(episodeId: episodeId)).copyWith(
        pageIndex: delivery.pageIndex,
      ),
      isReadOnlyCompatibilityRestore:
          delivery.isReadOnlyCompatibilityRestore || actual == null,
      hasUserNavigated: delivery.hasUserNavigated,
      isBodyEndVisible: wholePage,
      isWholeBodyVisible: wholePage,
    );
  }

  void forgetPage(int page, NovelReaderNativePageView view) {
    _window?.forgetPage(page, view);
    if (identical(_visible?.view, view)) _visible = null;
    if (identical(_target?.view, view)) {
      _target = null;
      if (!isClosed) {
        if (_error == null) {
          _restartProducer();
        } else if (_prefixNavigation) {
          unawaited(
            _preparePublishedTarget(_window!, _requestId, afterFrame: true),
          );
        }
      }
    }
  }

  void _startPublishedNavigation(int page) {
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
      unawaited(_preparePublishedTarget(window, _requestId));
    } catch (error) {
      _pause(error);
    }
  }

  Future<void> _preparePublishedTarget(
    NovelReaderNativeViewWindow window,
    int requestId, {
    bool afterFrame = false,
  }) async {
    bool current() =>
        !isClosed &&
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
    List<ForumBodyParagraphLease> leases,
  ) {
    final snapshot = delivery.view.snapshot;
    for (final (index, fragment)
        in snapshot[delivery.pageIndex].fragments.indexed) {
      final layout = leases[index].layout;
      if (layout.lines.isEmpty) continue;
      final window = layout.fragment(fragment.startLine, fragment.endLine);
      for (var row = fragment.startLine; row < fragment.endLine; row++) {
        final line = layout.lines[row];
        final top = fragment.top + line.top - window.top;
        if (line.left < -precisionErrorTolerance ||
            line.left + line.width > fragment.width + precisionErrorTolerance ||
            fragment.left + line.left < -precisionErrorTolerance ||
            fragment.left + line.left + line.width >
                snapshot.width + precisionErrorTolerance ||
            top < -precisionErrorTolerance ||
            fragment.top + line.bottom - window.top >
                snapshot.height + precisionErrorTolerance) {
          return false;
        }
      }
    }
    return true;
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
      _phase = NovelReaderNativePagedPhase.empty;
      _ticket = null;
      _watch!.close();
      _notify();
      return;
    }
    if (_entryEdge == NovelReaderChapterEdge.end && prefix.isComplete) {
      _requestedPage = prefix.length - 1;
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
            final job = NovelReaderNativePageViewJob(
              session: _session!,
              anchors: _anchors!,
              pageIndex: hint.pageIndex,
              parent: _lifetime,
              scheduler: _scheduler!,
            );
            _probe = job;
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
                _restoredAnchor = target;
                if (result.pageIndex == view.pageIndex) {
                  _window!.setCenter(result.pageIndex);
                  _window!.adoptTarget(view);
                  view = null;
                }
                break;
              }
            } finally {
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
        _restoredAnchor = target;
      }
    }
  }

  void _offerTarget() {
    if (isClosed ||
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
    _target = NovelReaderNativePageDelivery(
      requestId: _requestId,
      view: view,
      isReadOnlyCompatibilityRestore: _readOnly,
      hasUserNavigated: _userNavigation,
      restoredAnchor: _restoredAnchor,
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
    if (isClosed || epoch != _producerEpoch || _error != null) {
      throw const NovelReaderPaginationException(
        code: 'paginationCancelled',
        message: 'Native reader request retired.',
      );
    }
  }

  void _pause(Object error) {
    if (isClosed) return;
    _error = error;
    _prefixNavigation = false;
    _phase = NovelReaderNativePagedPhase.paused;
    _producerEpoch++;
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
    _prefixNavigation = false;
    _restoredAnchor = null;
    _ticket = null;
    _error = null;
    final changes = _changes;
    _changes = null;
    if (changes != null) unawaited(changes.close());
  }
}

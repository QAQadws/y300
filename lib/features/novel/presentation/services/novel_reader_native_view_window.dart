import 'dart:async';

import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../models/novel_reader_native_anchor_map.dart';
import '../models/novel_reader_native_page_view.dart';
import 'novel_reader_native_page_view_job.dart';
import 'novel_reader_native_work_scheduler.dart';
import 'novel_reader_pagination_cancellation.dart';

final class NovelReaderNativeViewWindowLimits {
  const NovelReaderNativeViewWindowLimits({
    this.radius = 1,
    this.maxRetainedFragments = 256,
    this.maxRetainedCoveragePoints = 24576,
  });
  final int radius;
  final int maxRetainedFragments;
  final int maxRetainedCoveragePoints;
}

final class NovelReaderNativeViewWindowBudgetException implements Exception {
  const NovelReaderNativeViewWindowBudgetException();
}

/// Owns only a bounded current/neighbor window and one serial view task.
/// Invoke prepareAvailable from the Host's source publication/priority lane;
/// this object does not advance source, run timers or confirm navigation.
/// Taking leases from a returned view transfers them to Surface. Window
/// retirement then drops only metadata; it never releases mounted leases.
final class NovelReaderNativeViewWindow {
  factory NovelReaderNativeViewWindow({
    required ForumBodyTextPageSession session,
    required NovelReaderNativeAnchorMap anchors,
    required NovelReaderPaginationCancellationToken parent,
    required int centerPageIndex,
    NovelReaderNativeWorkScheduler scheduler =
        const NovelReaderNativeWorkScheduler(),
    NovelReaderNativeViewWindowLimits limits =
        const NovelReaderNativeViewWindowLimits(),
    NovelReaderNativeViewJobLimits jobLimits =
        const NovelReaderNativeViewJobLimits(),
  }) {
    parent.throwIfCancelled();
    if (centerPageIndex < 0 ||
        limits.radius < 0 ||
        limits.radius > 2 ||
        limits.maxRetainedFragments < 0 ||
        limits.maxRetainedCoveragePoints < 0) {
      throw ArgumentError('Invalid native view window limits');
    }
    if (session.isClosed ||
        session.isLayoutOwnerRetired ||
        session.snapshot.identity != anchors.identity) {
      throw StateError('Native view window scope changed');
    }
    final window = NovelReaderNativeViewWindow._(
      session,
      anchors,
      parent,
      scheduler,
      limits,
      jobLimits,
      centerPageIndex,
    );
    window._bind(session, parent);
    return window;
  }

  NovelReaderNativeViewWindow._(
    this._session,
    this._anchors,
    this._parent,
    this._scheduler,
    this.limits,
    this.jobLimits,
    this._center,
  );
  ForumBodyTextPageSession? _session;
  NovelReaderNativeAnchorMap? _anchors;
  NovelReaderPaginationCancellationToken? _parent;
  NovelReaderNativeWorkScheduler? _scheduler;
  final NovelReaderNativeViewWindowLimits limits;
  final NovelReaderNativeViewJobLimits jobLimits;
  final _views = <int, NovelReaderNativePageView>{};
  final _deferred = <int, (int, int)>{};
  final _capacityDeferred = <int>{};
  NovelReaderNativePageViewJob? _active;
  int? _activePage;
  int _center;
  int _revision = 0;
  bool _closed = false;
  Future<void>? _running;
  void Function()? _removeParent;
  StreamSubscription<void>? _retirement;
  StreamSubscription<int>? _owner;
  StreamController<void>? _changes;

  bool get isClosed => _closed;
  int get centerPageIndex => _center;
  int get retainedPageCount => _views.length;
  int get retainedCoveragePoints =>
      _views.values.fold(0, (sum, view) => sum + view.coverage.locationCount);
  int get retainedFragments => _views.values.fold(
    0,
    (sum, view) => sum + view.snapshot[view.pageIndex].itemCount,
  );
  Stream<void> get changes => _closed
      ? const Stream<void>.empty()
      : (_changes ??= StreamController<void>.broadcast()).stream;

  NovelReaderNativePageView? viewForPage(int index) {
    final view = _views[index];
    return view != null && _usable(view) ? view : null;
  }

  /// Accept a target already prepared and proved by the same actual session.
  /// Ownership moves only on success; the caller closes a rejected view.
  void adoptTarget(NovelReaderNativePageView view) {
    if (_closed || !view.isReady) {
      throw StateError('Native target view is retired');
    }
    final snapshot = _session!.snapshot;
    if (view.pageIndex != _center ||
        view.snapshot.identity != snapshot.identity ||
        view.snapshot.layoutId != snapshot.layoutId ||
        view.pageIndex >= snapshot.length ||
        !identical(view.snapshot[view.pageIndex], snapshot[view.pageIndex])) {
      throw StateError('Native target view scope changed');
    }
    if (identical(_views[_center], view)) return;
    // A proved navigation target takes priority over unfinished window work.
    // Retire its task identity before cancellation can resume the serial drive.
    if (_active case final active?) {
      _revision++;
      _active = null;
      _activePage = null;
      active.close();
    }
    _remove(_center);
    if (!_admit(view)) throw const NovelReaderNativeViewWindowBudgetException();
    _views[_center] = view;
    _notify();
  }

  void setCenter(int index) {
    if (_closed) throw StateError('Native view window is closed');
    if (index < 0) throw ArgumentError.value(index, 'index');
    if (index == _center) return;
    _center = index;
    _revision++;
    _deferred.clear();
    _capacityDeferred.clear();
    if (viewForPage(index) == null) _dropOptionalOwned(index);
    if (_activePage == index) {
      _active?.promote();
    } else {
      _active?.close();
    }
    for (final page in _views.keys.toList(growable: false)) {
      if ((page - _center).abs() > limits.radius) _remove(page);
    }
    _notify();
  }

  /// UI unmount/remount acknowledgement. A late old Element cannot remove a
  /// newer delivery for the same page. Actual Surface owns transferred leases.
  /// Returns whether this unmount may unblock deferred neighbors. The Host
  /// retries on its existing source lane, after Surface releases its pins.
  bool forgetPage(int index, NovelReaderNativePageView view) {
    if (_closed || index != view.pageIndex || index < 0) return false;
    final previous = _views[index];
    if (previous != null && !identical(previous, view)) return false;
    final snapshot = _session!.snapshot;
    if (index >= snapshot.length ||
        view.snapshot.identity != snapshot.identity ||
        view.snapshot.layoutId != snapshot.layoutId ||
        !identical(view.snapshot[index], snapshot[index])) {
      return false;
    }
    bool optional(int page) => page != _center && _wanted(page);
    final retry =
        _deferred.keys.any(optional) || _capacityDeferred.any(optional);
    if (identical(previous, view)) {
      _remove(index);
      _deferred.remove(index);
      _notify();
    }
    return retry;
  }

  Future<void> prepareAvailable() {
    if (_closed) throw StateError('Native view window is closed');
    final running = _running;
    if (running != null) return running;
    final completion = Completer<void>();
    _running = completion.future;
    unawaited(
      _drive().then<void>(
        completion.complete,
        onError: (Object error, StackTrace stack) =>
            completion.completeError(error, stack),
      ),
    );
    return completion.future;
  }

  Future<void> _drive() async {
    var observedRevision = _revision;
    final attempted = <int>{};
    try {
      while (!_closed) {
        if (observedRevision != _revision) {
          observedRevision = _revision;
          attempted.clear();
        }
        final session = _session!;
        final prefix = session.snapshot;
        // A missing target has priority over preparing any optional neighbor.
        if (_center >= prefix.length) return;
        final candidates = [
          _center,
          for (var distance = 1; distance <= limits.radius; distance++) ...[
            _center + distance,
            _center - distance,
          ],
        ];
        int? selected;
        for (final page in candidates) {
          if (page < 0 || page >= prefix.length) continue;
          if (attempted.contains(page)) continue;
          final previous = _views[page];
          if (previous != null && _usable(previous)) continue;
          if (previous != null) _remove(page);
          if (page != _center &&
              (_capacityDeferred.contains(page) ||
                  _deferred[page] ==
                      (prefix.length, session.layoutBudgetRevision))) {
            continue;
          }
          selected = page;
          break;
        }
        if (selected == null) return;
        final page = selected;
        // Our own rolled-back neighbor leases also change cache revision.
        // They must not make two deferred neighbors repeatedly retry each other.
        attempted.add(page);
        if (page == _center) {
          // Optional unmounted pins must not block the requested page. Already
          // transferred/mounted views remain under their Surface/session owner.
          _dropOptionalOwned(page);
        }
        final revision = _revision;
        NovelReaderNativePageViewJob? job;
        NovelReaderNativePageView? ready;
        try {
          job = NovelReaderNativePageViewJob(
            session: session,
            anchors: _anchors!,
            pageIndex: page,
            parent: _parent!,
            waitForLayoutBudget: page == _center,
            scheduler: _scheduler!,
            limits: jobLimits,
          );
          _active = job;
          _activePage = page;
          ready = await job.run();
          if (!identical(_active, job)) {
            ready.close();
            ready = null;
          }
        } on NovelReaderNativeViewBudgetDeferred {
          if (!_closed && revision == _revision) {
            _deferred[page] = (
              session.snapshot.length,
              session.layoutBudgetRevision,
            );
          }
        } on ForumBodyTextPagePreparationException catch (error) {
          if (!_closed && revision == _revision) {
            if (page == _center ||
                error.failure !=
                    ForumBodyTextPagePreparationFailure.intrinsicBudget) {
              rethrow;
            }
            _capacityDeferred.add(page);
          }
        } on ForumBodyTextPageSessionException catch (error) {
          if (!_closed && revision == _revision) {
            if (page == _center ||
                (error.failure != ForumBodyTextPageSessionFailure.leaseLimit &&
                    error.failure !=
                        ForumBodyTextPageSessionFailure.preparationLimit)) {
              rethrow;
            }
            _deferred[page] = (
              session.snapshot.length,
              session.layoutBudgetRevision,
            );
          }
        } catch (_) {
          if (!_closed && revision == _revision) rethrow;
        } finally {
          job?.close();
          if (identical(_active, job)) {
            _active = null;
            _activePage = null;
          }
        }
        if (ready == null) continue;
        if (_closed || !_wanted(page) || !ready.isReady) {
          ready.close();
          continue;
        }
        if (!_admit(ready)) {
          ready.close();
          if (page == _center) {
            throw const NovelReaderNativeViewWindowBudgetException();
          }
          _capacityDeferred.add(page);
          continue;
        }
        _views[page] = ready;
        _deferred.remove(page);
        _notify();
      }
    } finally {
      _running = null;
    }
  }

  bool _admit(NovelReaderNativePageView view) {
    final fragments = view.snapshot[view.pageIndex].itemCount;
    final points = view.coverage.locationCount;
    if (fragments > limits.maxRetainedFragments ||
        points > limits.maxRetainedCoveragePoints) {
      return false;
    }
    bool fits() =>
        retainedFragments + fragments <= limits.maxRetainedFragments &&
        retainedCoveragePoints + points <= limits.maxRetainedCoveragePoints;
    if (view.pageIndex == _center) {
      for (final page in _views.keys.toList(growable: false)) {
        if (fits()) break;
        _remove(page);
      }
    }
    return fits();
  }

  bool _wanted(int page) => (page - _center).abs() <= limits.radius;
  bool _usable(NovelReaderNativePageView view) =>
      view.isReady || view.state == NovelReaderNativePageViewState.transferred;
  void _remove(int page) {
    final view = _views.remove(page);
    if (view == null) return;
    view.close();
    _capacityDeferred.clear();
  }

  void _dropOptionalOwned(int keep) {
    for (final entry in _views.entries.toList(growable: false)) {
      if (entry.key != keep &&
          entry.value.state == NovelReaderNativePageViewState.owned) {
        _remove(entry.key);
      }
    }
  }

  void _notify() => _changes?.add(null);

  void _bind(
    ForumBodyTextPageSession session,
    NovelReaderPaginationCancellationToken parent,
  ) {
    final remove = parent.onCancel(close);
    if (_closed) {
      remove();
      return;
    }
    _removeParent = remove;
    _retirement = session.retirement.listen((_) => close(), onDone: close);
    _owner = session.layoutBudgetChanges.listen((_) {
      if (session.isClosed || session.isLayoutOwnerRetired) close();
    }, onDone: close);
    if (session.isClosed ||
        session.isLayoutOwnerRetired ||
        parent.isCancelled) {
      close();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _revision++;
    _removeParent?.call();
    _removeParent = null;
    final retirement = _retirement;
    final owner = _owner;
    _retirement = null;
    _owner = null;
    if (retirement != null) unawaited(retirement.cancel());
    if (owner != null) unawaited(owner.cancel());
    _active?.close();
    _active = null;
    _activePage = null;
    for (final view in _views.values) {
      view.close();
    }
    _views.clear();
    _deferred.clear();
    _capacityDeferred.clear();
    _session = null;
    _anchors = null;
    _parent = null;
    _scheduler = null;
    final changes = _changes;
    _changes = null;
    if (changes != null) unawaited(changes.close());
  }
}

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import '../pagination/forum_body_text_page_composer.dart';
import '../pagination/forum_body_text_page_preparation.dart';
import '../pagination/forum_body_text_page_session.dart';
import '../pagination/forum_body_prepared_text_fragment.dart';

final class ForumBodyFlowPreparationCancelled implements Exception {
  const ForumBodyFlowPreparationCancelled();
}

typedef ForumBodyFlowSessionFactory =
    ForumBodyTextPageSession Function(double width, {required bool probe});

/// One active natural-flow source. The factory captures resolved inputs and
/// resources, not a Widget or Context. This owns sessions and sequential work;
/// consumers own display leases. A caller can transfer its listener without
/// restarting the source. This is transient work, not a cache entry.
/// Published prefixes prove source geometry, not mounted/image readiness.
final class ForumBodyFlowSource extends ChangeNotifier {
  ForumBodyFlowSource({
    required double width,
    double? compactMinWidth,
    required ForumBodyFlowSessionFactory openSession,
  }) : _width = width,
       _compactMinWidth = compactMinWidth,
       _openSession = openSession {
    if (!width.isFinite ||
        width <= 0 ||
        (compactMinWidth != null &&
            (!compactMinWidth.isFinite ||
                compactMinWidth < 0 ||
                compactMinWidth > width))) {
      throw ArgumentError('Invalid natural-flow geometry');
    }
  }

  final double _width;
  final double? _compactMinWidth;
  ForumBodyFlowSessionFactory? _openSession;
  ForumBodyTextPageSession? _session;
  ForumBodyTextPageSnapshot? _prefix;
  StreamSubscription<int>? _budget;
  StreamSubscription<void>? _retirement;
  final _preparations = <_FlowPreparation>{};
  Object? _error;
  StackTrace? _stack;
  bool _started = false, _closed = false, _stopped = false, _waiting = false;
  bool _probing = false, _notifying = false;
  bool _suspended = false;

  ForumBodyTextPageSession? get session => _session;
  ForumBodyTextPageSnapshot? get prefix => _prefix;
  Object? get error => _error;
  StackTrace? get errorStack => _stack;
  bool get isClosed => _closed;
  bool get isStopped => _stopped;
  bool get isSuspended => _suspended;

  /// Holds background source work after a requested prefix is available.
  /// Owned display preparation remains eligible for the shared frame budget.
  void suspend() {
    if (_closed || _stopped) return;
    _suspended = true;
    _FlowSourceQueue.remove(_advance);
  }

  void resume() {
    if (_closed || _stopped) throw StateError('Natural-flow source is retired');
    if (!_started) {
      _suspended = false;
      start();
      return;
    }
    if (!_suspended) return;
    _suspended = false;
    _waiting = false;
    if (_prefix?.isComplete != true) _FlowSourceQueue.add(_advance);
  }

  /// Takes an owned page/cell transaction and returns its display leases.
  /// Invalid/foreign transactions remain owned by their caller. The caller
  /// must close transferred fragments if its request retires before use.
  Future<List<ForumBodyPreparedTextFragment>> prepare(
    ForumBodyTextPagePreparation preparation,
  ) {
    if (_closed ||
        _stopped ||
        _session?.ownsPagePreparation(preparation) != true) {
      throw StateError('Preparation belongs to a different flow owner');
    }
    if (_preparations.length >= _session!.limits.maxPagePreparations) {
      throw const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.preparationLimit,
      );
    }
    final work = _FlowPreparation(this, preparation);
    _preparations.add(work);
    _FlowSourceQueue.add(work.advance);
    return work.result.future;
  }

  /// Cancels this demand's transaction without retiring a borrowed source.
  void cancelPreparation(ForumBodyTextPagePreparation preparation) {
    for (final work in _preparations.toList()) {
      if (identical(work.job, preparation)) work.cancel();
    }
  }

  /// Idempotent for a new display owner adopting already-started source work.
  void start() {
    if (_closed || _stopped) throw StateError('Natural-flow source is retired');
    if (_started) return;
    _started = true;
    _probing = _compactMinWidth != null;
    try {
      _useSession(_openSession!(_width, probe: _probing));
    } catch (error, stack) {
      if (!_closed && !_stopped) _fail(error, stack);
    }
  }

  void _useSession(ForumBodyTextPageSession session) {
    if (_closed || _stopped) {
      session.close();
      return;
    }
    unawaited(_budget?.cancel());
    unawaited(_retirement?.cancel());
    _session?.close();
    _session = session;
    _waiting = false;
    _budget = session.layoutBudgetChanges.listen((_) {
      if (!_closed && !_stopped && _error == null) {
        if (_waiting && !_suspended) {
          _waiting = false;
          _FlowSourceQueue.add(_advance);
        }
        if (_preparations.isNotEmpty) {
          for (final work in _preparations.toList()) {
            if (work.waiting) _FlowSourceQueue.add(work.advance);
          }
        }
      }
    }, onDone: () => _ownerRetired(session));
    _retirement = session.retirement.listen(
      (_) => _ownerRetired(session),
      onDone: () => _ownerRetired(session),
    );
    if (!_suspended) _FlowSourceQueue.add(_advance);
  }

  void _ownerRetired(ForumBodyTextPageSession session) {
    if (_closed || _stopped || !identical(_session, session)) return;
    _fail(
      const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.ownerRetired,
      ),
      StackTrace.current,
    );
  }

  void _advance() {
    if (_closed || _stopped || _suspended || _error != null) return;
    final session = _session!;
    try {
      final step = session.advance(maxEvents: 16, maxLines: 4);
      _waiting = step.waitingForLayoutBudget;
      if (_probing) {
        // Provisional intrinsic widths must never publish visible geometry.
        if (!step.isComplete) {
          if (!_waiting) _FlowSourceQueue.add(_advance);
          return;
        }
        _probing = false;
        final preferred = session.intrinsicWidths!.preferred;
        final width = preferred.isFinite && preferred > 0
            ? preferred
                  .ceilToDouble()
                  .clamp(_compactMinWidth!, _width)
                  .toDouble()
            : _width;
        if (width < _width) {
          _useSession(_openSession!(width, probe: false));
          return;
        }
      }
      final snapshot = session.snapshot;
      if (snapshot.length != _prefix?.length ||
          snapshot.isComplete != _prefix?.isComplete) {
        _prefix = snapshot;
        _publish();
      }
      if (!_closed &&
          !_stopped &&
          !_suspended &&
          !step.isComplete &&
          !_waiting) {
        _FlowSourceQueue.add(_advance);
      }
    } catch (error, stack) {
      if (!_closed && !_stopped) _fail(error, stack);
    }
  }

  void _fail(Object error, StackTrace stack) {
    _error = error;
    _stack = stack;
    stop();
    _publish();
  }

  void _publish() {
    _notifying = true;
    try {
      notifyListeners();
    } finally {
      _notifying = false;
      if (_closed) super.dispose();
    }
  }

  /// Shares the source frame's remaining allowance for first-mount delivery.
  /// A cache miss does not shape, record pictures or schedule another queue.
  static bool tryPrepareCached(ForumBodyTextPagePreparation job) =>
      _FlowSourceQueue.prepareCached(job);

  /// Retires source work after a consumer failure, preserving published views
  /// until their owner closes the task. Restart uses a new source generation.
  void stop() {
    _stopped = true;
    _FlowSourceQueue.remove(_advance);
    unawaited(_budget?.cancel());
    _budget = null;
    unawaited(_retirement?.cancel());
    _retirement = null;
    for (final work in _preparations.toList()) {
      work.cancel();
    }
  }

  void close() => dispose();

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    stop();
    _openSession = null;
    _session?.close();
    // A cancellation listener may retire its owner during publication.
    if (!_notifying) super.dispose();
  }
}

final class _FlowPreparation {
  _FlowPreparation(this.owner, this.job);
  final ForumBodyFlowSource owner;
  final ForumBodyTextPagePreparation job;
  final result = Completer<List<ForumBodyPreparedTextFragment>>.sync();
  bool waiting = false;

  void advance() {
    if (result.isCompleted) return;
    try {
      final step = job.advance(maxFragments: 8, maxParts: 32);
      waiting = step.waitingForLayoutBudget;
      if (step.isReady) {
        final fragments = job.takeFragments();
        _retire();
        result.complete(fragments);
      } else if (!waiting) {
        _FlowSourceQueue.add(advance);
      }
    } catch (error, stack) {
      _retire();
      result.completeError(error, stack);
    }
  }

  void _retire() {
    _FlowSourceQueue.remove(advance);
    owner._preparations.remove(this);
    job.close();
  }

  void cancel() {
    if (result.isCompleted) return;
    _retire();
    result.completeError(const ForumBodyFlowPreparationCancelled());
  }
}

/// Fair across mounted flows and explicit target work. The elapsed and step
/// allowances are shared; a new source never receives a separate frame budget.
abstract final class _FlowSourceQueue {
  static final _pending = <VoidCallback>{};
  static final _clock = Stopwatch();
  static int _steps = 0;
  static bool _initialized = false;
  static bool _scheduled = false;
  static bool _draining = false;

  static void add(VoidCallback work) {
    if (!_initialized) {
      _initialized = true;
      WidgetsBinding.instance.addPersistentFrameCallback((_) {
        _clock.reset();
        _steps = 0;
      });
    }
    _pending.add(work);
    if (_draining) return;
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.postFrameCallbacks) {
      _drain();
    } else {
      _schedule();
    }
  }

  static void remove(VoidCallback work) => _pending.remove(work);

  static bool prepareCached(ForumBodyTextPagePreparation job) {
    while (_draining && _steps < 64 && _clock.elapsedMicroseconds < 3000) {
      _steps++;
      if (job.tryPrepareCached(maxParts: 32)) return true;
      if (job.cacheMiss || job.waitingForLayoutBudget) return false;
    }
    return false;
  }

  static void _schedule() {
    if (_scheduled || _pending.isEmpty) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _drain();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  static void _drain() {
    if (_draining || _pending.isEmpty) return;
    _draining = true;
    _clock.start();
    try {
      while (_steps < 64 &&
          _pending.isNotEmpty &&
          _clock.elapsedMicroseconds < 3000) {
        _steps++;
        final step = _pending.first;
        _pending.remove(step);
        step();
      }
    } finally {
      _clock.stop();
      _draining = false;
      _schedule();
    }
  }
}

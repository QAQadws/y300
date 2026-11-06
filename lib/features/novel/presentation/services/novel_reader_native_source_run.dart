import 'dart:async';

import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../models/novel_reader_pagination_exception.dart';
import 'novel_reader_native_work_scheduler.dart';
import 'novel_reader_pagination_cancellation.dart';
import 'novel_reader_pagination_demand.dart';

typedef NovelReaderNativePagePublication = FutureOr<void> Function(
  ForumBodyTextPageSnapshot snapshot,
  NovelReaderPaginationCancellationToken token,
);

enum NovelReaderNativeSourceRunState {
  pending,
  running,
  complete,
  failed,
  closed,
}

final class NovelReaderNativeSourceRunLimits {
  const NovelReaderNativeSourceRunLimits({
    this.frameBudget = const Duration(milliseconds: 3),
    this.maxStepsPerFrame = 64,
    this.eventsPerStep = 32,
    this.linesPerStep = 8,
  });
  final Duration frameBudget;
  final int maxStepsPerFrame;
  final int eventsPerStep;
  final int linesPerStep;
}

/// Drives one sequential source, borrowing its session and demand owner.
/// Publications are awaited serially, so the Host can service a target view
/// before source work resumes. The callback must honor its child token and
/// generation; deadlines, visible views and retry prefix checks belong to Host.
/// The callback token owns work only and retires at termination. Views that
/// outlive the callback must bind to the actual layout parent, not this token.
/// This is the session's exclusive source driver; callbacks do not advance it.
/// Closing stops work without retiring the source or already mounted content.
final class NovelReaderNativeSourceRun {
  factory NovelReaderNativeSourceRun({
    required ForumBodyTextPageSession session,
    required NovelReaderPaginationDemand demand,
    required NovelReaderPaginationCancellationToken parent,
    required NovelReaderNativePagePublication onPublication,
    NovelReaderNativeWorkScheduler scheduler =
        const NovelReaderNativeWorkScheduler(),
    NovelReaderNativeSourceRunLimits limits =
        const NovelReaderNativeSourceRunLimits(),
  }) {
    parent.throwIfCancelled();
    if (limits.frameBudget <= Duration.zero ||
        limits.maxStepsPerFrame <= 0 ||
        limits.eventsPerStep <= 0 ||
        limits.linesPerStep <= 0) {
      throw ArgumentError('Invalid native source work limits');
    }
    if (session.isClosed || session.isLayoutOwnerRetired) {
      throw const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.ownerRetired,
      );
    }
    if (session.state == ForumBodyTextPageSessionState.failed) {
      throw StateError('Cannot resume a failed native source');
    }
    final run = NovelReaderNativeSourceRun._(
      session,
      demand,
      onPublication,
      scheduler,
      limits,
    );
    run._bind(session, parent);
    return run;
  }

  NovelReaderNativeSourceRun._(
    this._session,
    this._demand,
    this._publish,
    this._scheduler,
    this.limits,
  );
  ForumBodyTextPageSession? _session;
  NovelReaderPaginationDemand? _demand;
  NovelReaderNativePagePublication? _publish;
  NovelReaderNativeWorkScheduler? _scheduler;
  NovelReaderPaginationDemandLease? _demandLease;
  final NovelReaderNativeSourceRunLimits limits;
  final _token = NovelReaderPaginationCancellationToken();
  final _clock = Stopwatch();
  int _steps = 0;
  int _frames = 0;
  void Function()? _removeParent;
  StreamSubscription<void>? _retirement;
  StreamSubscription<int>? _owner;
  Future<ForumBodyTextPageSnapshot>? _running;
  NovelReaderNativeSourceRunState _state =
      NovelReaderNativeSourceRunState.pending;

  NovelReaderNativeSourceRunState get state => _state;
  int get framesWaited => _frames;

  void _bind(
    ForumBodyTextPageSession session,
    NovelReaderPaginationCancellationToken parent,
  ) {
    final remove = parent.onCancel(close);
    if (_state == NovelReaderNativeSourceRunState.closed) {
      remove();
      return;
    }
    _removeParent = remove;
    _retirement = session.retirement.listen((_) => close(), onDone: close);
    _owner = session.layoutBudgetChanges.listen((_) {
      if (session.isClosed || session.isLayoutOwnerRetired) close();
    }, onDone: close);
    if (parent.isCancelled ||
        session.isClosed ||
        session.isLayoutOwnerRetired) {
      close();
    }
  }

  Future<ForumBodyTextPageSnapshot> run({bool resumeFinalPlan = false}) {
    final current = _running;
    if (current != null) return current;
    if (_state != NovelReaderNativeSourceRunState.pending) {
      throw StateError('Native source run is retired');
    }
    final completion = Completer<ForumBodyTextPageSnapshot>();
    _running = completion.future;
    _state = NovelReaderNativeSourceRunState.running;
    unawaited(
      _drive(resumeFinalPlan).then<void>(
        completion.complete,
        onError: (Object error, StackTrace stack) =>
            completion.completeError(error, stack),
      ),
    );
    return completion.future;
  }

  Future<ForumBodyTextPageSnapshot> _drive(bool resumeFinalPlan) async {
    try {
      _demandLease = _demand!.start(_token);
      _guard();
      if (resumeFinalPlan && _session!.isComplete) {
        // Resume only republishes the immutable plan. Keep the callback
        // asynchronous and let the view job yield before acquiring leases.
        await Future<void>.value();
      } else {
        await _yieldFrame();
      }
      var published = 0;
      while (true) {
        _guard();
        final session = _session!;
        final prefix = session.snapshot;
        if (prefix.length != published || session.isComplete) {
          // Include an existing stable prefix when attaching/resuming. The
          // same final prefix can publish once more with actual EOF metadata.
          await _token.waitFor(
            Future<void>.sync(() => _publish!(prefix, _token)),
          );
          _guard();
          published = prefix.length;
          if (session.snapshot.length != prefix.length ||
              session.isComplete != prefix.isComplete) {
            throw StateError('Native source advanced outside its driver');
          }
          if (session.isComplete) {
            _state = NovelReaderNativeSourceRunState.complete;
            return prefix;
          }
          final demand = _demand!;
          final resume = _demandLease!.afterPublication(published);
          // Idle deferral has already yielded to the scheduler. Carry the
          // spent frame budget forward without charging the wait to it.
          if (demand.isDeferring) _clock.stop();
          await resume;
          _guard();
          _clock.start();
        }
        if (_steps >= limits.maxStepsPerFrame ||
            _clock.elapsed >= limits.frameBudget) {
          await _yieldFrame();
        }
        _guard();
        final revision = session.layoutBudgetRevision;
        final step = session.advance(
          maxEvents: limits.eventsPerStep,
          maxLines: limits.linesPerStep,
        );
        _steps++;
        _guard();
        if (step.waitingForLayoutBudget) {
          await _scheduler!.waitForLayoutBudget(
            session: session,
            afterRevision: revision,
            token: _token,
          );
          await _yieldFrame();
        } else if (!step.madeProgress) {
          throw const NovelReaderPaginationException(
            code: 'paginationNoProgress',
            message: 'Native pagination made no bounded progress.',
          );
        }
      }
    } catch (_) {
      if (_state != NovelReaderNativeSourceRunState.closed) {
        _state = NovelReaderNativeSourceRunState.failed;
      }
      _token.throwIfCancelled();
      rethrow;
    } finally {
      _token.cancel();
      _cleanup();
      _running = null;
    }
  }

  Future<void> _yieldFrame() async {
    _guard();
    await _scheduler!.nextFrame(_token);
    _guard();
    _frames++;
    _steps = 0;
    _clock.reset();
    _clock.start();
  }

  void _guard() {
    _token.throwIfCancelled();
    if (_session!.isClosed || _session!.isLayoutOwnerRetired) {
      close();
      _token.throwIfCancelled();
    }
  }

  void _cleanup() {
    _removeParent?.call();
    _removeParent = null;
    final retirement = _retirement;
    final owner = _owner;
    _retirement = null;
    _owner = null;
    if (retirement != null) unawaited(retirement.cancel());
    if (owner != null) unawaited(owner.cancel());
    _demandLease?.close();
    _demandLease = null;
    _session = null;
    _demand = null;
    _publish = null;
    _scheduler = null;
    _clock.stop();
  }

  void close() {
    if (_state == NovelReaderNativeSourceRunState.closed) return;
    _state = NovelReaderNativeSourceRunState.closed;
    _token.cancel();
    _cleanup();
  }
}

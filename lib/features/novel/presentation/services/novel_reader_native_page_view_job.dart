import 'dart:async';

import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../models/novel_reader_native_anchor_map.dart';
import '../models/novel_reader_native_page_view.dart';
import '../models/novel_reader_native_page_work.dart';
import 'novel_reader_native_page_coverage_cursor.dart';
import 'novel_reader_native_work_scheduler.dart';
import 'novel_reader_pagination_cancellation.dart';

enum NovelReaderNativeViewJobState {
  pending,
  preparing,
  waitingForBudget,
  checkingCoverage,
  complete,
  deferred,
  failed,
  closed,
}

/// Optional neighbor work met real external pressure. Retrying requires new
/// demand/budget evidence; intrinsic capacity failures retain their own type.
final class NovelReaderNativeViewBudgetDeferred implements Exception {
  const NovelReaderNativeViewBudgetDeferred();
}

final class NovelReaderNativeViewJobLimits {
  const NovelReaderNativeViewJobLimits({
    this.frameBudget = const Duration(milliseconds: 3),
    this.maxStepsPerFrame = 64,
    this.preparationFragments = 8,
    this.coverageGraphemes = 64,
    this.coverageFragments = 4,
    this.coverage = const NovelReaderNativeCoverageLimits(),
  });
  final Duration frameBudget;
  final int maxStepsPerFrame;
  final int preparationFragments;
  final int coverageGraphemes;
  final int coverageFragments;
  final NovelReaderNativeCoverageLimits coverage;
}

/// One published-page task, subordinate to a layout's cancellation token.
/// Work starts outside build after a frame, and coverage shares the prepared
/// native layouts. The Host serializes priority; this task does not own source
/// pagination, deadlines, reading mode, navigation or persisted positions.
final class NovelReaderNativePageViewJob {
  factory NovelReaderNativePageViewJob({
    required ForumBodyTextPageSession session,
    required NovelReaderNativeAnchorMap anchors,
    required int pageIndex,
    required NovelReaderPaginationCancellationToken parent,
    bool waitForLayoutBudget = true,
    NovelReaderNativeWorkScheduler scheduler =
        const NovelReaderNativeWorkScheduler(),
    NovelReaderNativeViewJobLimits limits =
        const NovelReaderNativeViewJobLimits(),
  }) {
    parent.throwIfCancelled();
    if (limits.frameBudget <= Duration.zero ||
        limits.maxStepsPerFrame <= 0 ||
        limits.preparationFragments <= 0 ||
        limits.coverageGraphemes <= 0 ||
        limits.coverageFragments <= 0 ||
        limits.coverage.maxFragments < 0 ||
        limits.coverage.maxGraphemes < 0 ||
        limits.coverage.maxPoints < 0) {
      throw ArgumentError('Invalid native page-view work limits');
    }
    if (anchors.identity != session.snapshot.identity) {
      throw const NovelReaderNativeCoverageException(
        NovelReaderNativeCoverageFailure.identity,
      );
    }
    if (session.isClosed || session.isLayoutOwnerRetired) {
      throw const ForumBodyTextPageSessionException(
        ForumBodyTextPageSessionFailure.ownerRetired,
      );
    }
    RangeError.checkValidIndex(pageIndex, session.snapshot, 'pageIndex');
    final job = NovelReaderNativePageViewJob._(
      session,
      anchors,
      parent,
      pageIndex,
      scheduler,
      limits,
      waitForLayoutBudget,
    );
    job._bind(session, parent);
    return job;
  }

  NovelReaderNativePageViewJob._(
    this._session,
    this._anchors,
    this._parent,
    this._pageIndex,
    this._scheduler,
    this.limits,
    this._waitForLayoutBudget,
  );
  ForumBodyTextPageSession? _session;
  NovelReaderNativeAnchorMap? _anchors;
  NovelReaderPaginationCancellationToken? _parent;
  final int _pageIndex;
  ForumBodyTextPagePreparation? _preparation;
  NovelReaderNativeWorkScheduler? _scheduler;
  final NovelReaderNativeViewJobLimits limits;
  bool _waitForLayoutBudget;
  final _token = NovelReaderPaginationCancellationToken();
  final _clock = Stopwatch();
  int _steps = 0;
  int _frames = 0;
  NovelReaderNativePageCoverageCursor? _coverage;
  List<ForumBodyPreparedTextFragment> _fragments = const [];
  Future<NovelReaderNativePageView>? _running;
  NovelReaderNativeViewJobState _state = NovelReaderNativeViewJobState.pending;
  void Function()? _removeParent;
  StreamSubscription<void>? _retirement;
  StreamSubscription<int>? _owner;

  NovelReaderNativeViewJobState get state => _state;
  int get framesWaited => _frames;

  /// Promotion keeps the same preparation. Never revive terminal work.
  bool promote() {
    if (_state == NovelReaderNativeViewJobState.complete ||
        _state == NovelReaderNativeViewJobState.deferred ||
        _state == NovelReaderNativeViewJobState.failed ||
        _state == NovelReaderNativeViewJobState.closed) {
      return false;
    }
    _waitForLayoutBudget = true;
    return true;
  }

  void _bind(
    ForumBodyTextPageSession session,
    NovelReaderPaginationCancellationToken parent,
  ) {
    final remove = parent.onCancel(close);
    if (_state == NovelReaderNativeViewJobState.closed) {
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

  Future<NovelReaderNativePageView> run() {
    final current = _running;
    if (current != null) return current;
    if (_state != NovelReaderNativeViewJobState.pending) {
      throw StateError('Native page view job is retired');
    }
    final completion = Completer<NovelReaderNativePageView>();
    _running = completion.future;
    _state = NovelReaderNativeViewJobState.preparing;
    unawaited(
      _drive().then<void>(
        completion.complete,
        onError: (Object error, StackTrace stack) =>
            completion.completeError(error, stack),
      ),
    );
    return completion.future;
  }

  Future<NovelReaderNativePageView> _drive() async {
    final elapsed = Stopwatch()..start();
    var preparationAdvanceUs = 0;
    var coverageAdvanceUs = 0;
    var preparationSteps = 0;
    var coverageSteps = 0;
    var layoutsBuilt = 0;
    var picturesBuilt = 0;
    try {
      await _yieldFrame();
      // The previous origin loses keepAlive when arrival is confirmed. Let
      // that frame unmount it before reserving aliases for another dense page.
      // This is the task's existing initial yield, not an extra wait/retry.
      final preparation = _session!.openPagePreparation(_pageIndex);
      _preparation = preparation;
      _guard();
      while (!preparation.isReady) {
        await _beforeStep();
        final start = elapsed.elapsedMicroseconds;
        final step = preparation.advance(
          maxFragments: limits.preparationFragments,
        );
        preparationAdvanceUs += elapsed.elapsedMicroseconds - start;
        preparationSteps++;
        layoutsBuilt += step.layoutsBuilt;
        picturesBuilt += step.picturesBuilt;
        _guard();
        if (step.waitingForLayoutBudget) {
          if (!_waitForLayoutBudget) {
            throw const NovelReaderNativeViewBudgetDeferred();
          }
          _state = NovelReaderNativeViewJobState.waitingForBudget;
          final session = _session!;
          await _scheduler!.waitForLayoutBudget(
            session: session,
            afterRevision: session.layoutBudgetRevision,
            token: _token,
          );
          _guard();
          _state = NovelReaderNativeViewJobState.preparing;
          await _yieldFrame();
        } else if (step.layoutsBuilt > 0 && !preparation.isReady) {
          // At most one new native paragraph per frame for this task. Warm
          // acquisitions and box checks share the remaining bounded slice.
          await _yieldFrame();
        }
      }
      _fragments = preparation.takeFragments();
      _guard();
      final preparationUs = elapsed.elapsedMicroseconds;
      final preparationFrames = _frames;
      final coverage = NovelReaderNativePageCoverageCursor.prepared(
        anchors: _anchors!,
        snapshot: preparation.snapshot,
        pageIndex: preparation.pageIndex,
        layoutId: preparation.snapshot.layoutId,
        fragments: _fragments,
        limits: limits.coverage,
      );
      _coverage = coverage;
      _state = NovelReaderNativeViewJobState.checkingCoverage;
      while (coverage.state == NovelReaderNativeCoverageState.active) {
        await _beforeStep();
        final start = elapsed.elapsedMicroseconds;
        coverage.advance(
          maxGraphemes: limits.coverageGraphemes,
          maxFragments: limits.coverageFragments,
        );
        coverageAdvanceUs += elapsed.elapsedMicroseconds - start;
        coverageSteps++;
        _guard();
      }
      final view = NovelReaderNativePageView.ownPrepared(
        session: _session!,
        pageIndex: preparation.pageIndex,
        fragments: _fragments,
        coverage: coverage.result,
        parent: _parent!,
        work: NovelReaderNativePageWork(
          preparationUs: preparationUs,
          coverageUs: elapsed.elapsedMicroseconds - preparationUs,
          preparationAdvanceUs: preparationAdvanceUs,
          coverageAdvanceUs: coverageAdvanceUs,
          preparationFrames: preparationFrames,
          coverageFrames: _frames - preparationFrames,
          preparationSteps: preparationSteps,
          coverageSteps: coverageSteps,
          layoutsBuilt: layoutsBuilt,
          picturesBuilt: picturesBuilt,
          checkedGraphemes: coverage.checkedGraphemes,
        ),
      );
      try {
        _guard();
        _fragments = const [];
        _state = NovelReaderNativeViewJobState.complete;
        return view;
      } catch (_) {
        view.close();
        rethrow;
      }
    } on NovelReaderNativeViewBudgetDeferred {
      _state = NovelReaderNativeViewJobState.deferred;
      rethrow;
    } catch (_) {
      if (_token.isCancelled) {
        _token.throwIfCancelled();
      }
      if (_state != NovelReaderNativeViewJobState.closed) {
        _state = NovelReaderNativeViewJobState.failed;
      }
      rethrow;
    } finally {
      elapsed.stop();
      _cleanup();
      _running = null;
    }
  }

  Future<void> _beforeStep() async {
    _guard();
    if (_steps >= limits.maxStepsPerFrame ||
        _clock.elapsed >= limits.frameBudget) {
      await _yieldFrame();
    }
    _guard();
    _steps++;
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
    final session = _session!;
    if (session.isClosed || session.isLayoutOwnerRetired) {
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
    _coverage?.close();
    _coverage = null;
    _preparation?.close();
    _preparation = null;
    for (final fragment in _fragments) {
      fragment.close();
    }
    _fragments = const [];
    _session = null;
    _anchors = null;
    _parent = null;
    _scheduler = null;
    _clock.stop();
  }

  void close() {
    if (_state == NovelReaderNativeViewJobState.closed) return;
    _state = NovelReaderNativeViewJobState.closed;
    _token.cancel();
    _cleanup();
  }
}

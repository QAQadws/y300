import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import 'novel_reader_pagination_cancellation.dart';

typedef NovelReaderNativeFrameYield = Future<void> Function();

/// Stateless waiting ports. No work, cache or token is retained after a wait.
/// Target deadlines and demand/idle priority remain the owning run's concern.
final class NovelReaderNativeWorkScheduler {
  const NovelReaderNativeWorkScheduler({
    NovelReaderNativeFrameYield nextFrame = _nextFrame,
  }) : _frame = nextFrame;
  final NovelReaderNativeFrameYield _frame;

  Future<void> nextFrame(NovelReaderPaginationCancellationToken token) async {
    token.throwIfCancelled();
    await token.waitFor(_frame());
    token.throwIfCancelled();
  }

  Future<void> waitForLayoutBudget({
    required ForumBodyTextPageSession session,
    required int afterRevision,
    required NovelReaderPaginationCancellationToken token,
  }) async {
    token.throwIfCancelled();
    if (afterRevision < 0 || afterRevision > session.layoutBudgetRevision) {
      throw ArgumentError.value(afterRevision, 'afterRevision');
    }
    final completion = Completer<void>();
    void retire() {
      if (!completion.isCompleted) {
        completion.completeError(
          const ForumBodyTextPageSessionException(
            ForumBodyTextPageSessionFailure.ownerRetired,
          ),
        );
      }
    }

    void check() {
      if (session.isClosed || session.isLayoutOwnerRetired) {
        retire();
      } else if (session.layoutBudgetRevision != afterRevision &&
          !completion.isCompleted) {
        completion.complete();
      }
    }

    final budget = session.layoutBudgetChanges.listen(
      (_) => check(),
      onDone: retire,
    );
    final retirement = session.retirement.listen(
      (_) => retire(),
      onDone: retire,
    );
    // Release/retirement may have happened after the rejected admission and
    // before subscription. The revision and current owner close that race.
    check();
    try {
      await token.waitFor(completion.future);
      token.throwIfCancelled();
    } finally {
      await Future.wait([budget.cancel(), retirement.cancel()]);
    }
  }

  static Future<void> _nextFrame() {
    final binding = SchedulerBinding.instance;
    // During post-frame callbacks, endOfFrame queues completion on the next
    // frame but only requests a frame itself when the scheduler is idle.
    if (binding.schedulerPhase == SchedulerPhase.postFrameCallbacks) {
      binding.ensureVisualUpdate();
    }
    return binding.endOfFrame;
  }
}

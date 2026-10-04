import 'dart:async';

import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';

/// Cooperative cancellation for derived pagination work.
///
/// Synchronous Flutter layout must finish its current step. Host/probe waits
/// can stop immediately; a cancelled run must never publish a plan.
final class NovelReaderPaginationCancellationToken {
  bool _cancelled = false;
  final _pendingYields = <Completer<void>, Timer>{};
  final _listeners = <void Function()>{};

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final entry in _pendingYields.entries) {
      entry.value.cancel();
      entry.key.complete();
    }
    _pendingYields.clear();
    final listeners = _listeners.toList(growable: false);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  /// Own only this subscription; removing it never cancels another waiter.
  void Function() onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Releases this wait on cancellation while still observing a late result.
  Future<T> waitFor<T>(Future<T> operation) {
    final completion = Completer<T>();
    final removeListener = onCancel(() {
      if (!completion.isCompleted) {
        completion.completeError(
          const NovelReaderPaginationException(
            code: 'paginationCancelled',
            message: 'Pagination was cancelled by a newer layout request.',
          ),
        );
      }
    });
    unawaited(
      operation.then<void>(
        (value) {
          if (!completion.isCompleted) completion.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          if (!completion.isCompleted) completion.completeError(error, stack);
        },
      ),
    );
    unawaited(
      completion.future.then<void>(
        (_) => removeListener(),
        onError: (Object error, StackTrace stack) => removeListener(),
      ),
    );
    return completion.future;
  }

  /// Yield UI execution without leaving a timer behind when the page exits.
  Future<void> yieldToEventLoop() async {
    throwIfCancelled();
    final completion = Completer<void>();
    final timer = Timer(Duration.zero, () {
      _pendingYields.remove(completion);
      completion.complete();
    });
    _pendingYields[completion] = timer;
    await completion.future;
    throwIfCancelled();
  }

  void throwIfCancelled() {
    if (_cancelled) {
      throw const NovelReaderPaginationException(
        code: 'paginationCancelled',
        message: 'Pagination was cancelled by a newer layout request.',
      );
    }
  }
}

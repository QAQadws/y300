import 'dart:async';

import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';

/// Cooperative cancellation for derived pagination work.
///
/// HTML layout still has to finish the current Flutter frame, so cancellation
/// is intentionally cooperative. A cancelled run must never publish a plan.
final class NovelReaderPaginationCancellationToken {
  bool _cancelled = false;
  final _pendingYields = <Completer<void>, Timer>{};

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    for (final entry in _pendingYields.entries) {
      entry.value.cancel();
      entry.key.complete();
    }
    _pendingYields.clear();
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

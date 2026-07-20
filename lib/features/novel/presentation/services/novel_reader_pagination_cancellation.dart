import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';

/// Cooperative cancellation for derived pagination work.
///
/// HTML layout still has to finish the current Flutter frame, so cancellation
/// is intentionally cooperative. A cancelled run must never publish a plan.
final class NovelReaderPaginationCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
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

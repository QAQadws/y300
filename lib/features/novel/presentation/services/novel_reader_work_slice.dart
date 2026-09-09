import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';

/// Cooperatively limits consecutive UI work, including cache-hit paths whose
/// completed futures otherwise only drain microtasks and starve frame events.
final class NovelReaderWorkSlice {
  NovelReaderWorkSlice({
    this.budget = const Duration(milliseconds: 3),
    this.cancellationToken,
  });

  final Duration budget;
  final NovelReaderPaginationCancellationToken? cancellationToken;
  final Stopwatch _clock = Stopwatch()..start();

  Future<void> yieldIfNeeded() async {
    cancellationToken?.throwIfCancelled();
    if (_clock.elapsed < budget) {
      return;
    }
    final token = cancellationToken;
    if (token == null) {
      await Future<void>.delayed(Duration.zero);
    } else {
      await token.yieldToEventLoop();
    }
    _clock.reset();
  }
}

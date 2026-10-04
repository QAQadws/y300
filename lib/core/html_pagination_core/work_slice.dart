import 'ports.dart';

/// Cooperatively limits consecutive work, including cache-hit paths whose
/// completed futures otherwise only drain microtasks and starve frame events.
final class HtmlPaginationWorkSlice {
  HtmlPaginationWorkSlice({
    this.budget = const Duration(milliseconds: 3),
    this.cancellationToken,
  });

  final Duration budget;
  final HtmlPaginationCancellation? cancellationToken;
  final Stopwatch _clock = Stopwatch()..start();
  Duration _longestSynchronousStepDuration = Duration.zero;

  Duration get longestSynchronousStepDuration =>
      _longestSynchronousStepDuration;

  /// Observes selected synchronous steps only; async frame/probe waits and
  /// time between yield checks are not continuous synchronous work.
  T trackSynchronous<T>(T Function() step) {
    final stopwatch = Stopwatch()..start();
    try {
      return step();
    } finally {
      stopwatch.stop();
      if (stopwatch.elapsed > _longestSynchronousStepDuration) {
        _longestSynchronousStepDuration = stopwatch.elapsed;
      }
    }
  }

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

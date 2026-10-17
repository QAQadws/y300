/// Event-driven calibration is enabled; periodic foreground probing is opt-in.
final class MessageAttentionProbePolicy {
  const MessageAttentionProbePolicy({
    this.freshness = const Duration(minutes: 2),
    this.coalesceDelay = const Duration(milliseconds: 750),
    this.initialRetryDelay = const Duration(seconds: 30),
    this.maximumRetryDelay = const Duration(minutes: 5),
    this.maximumAttempts = 2,
    this.foregroundInterval,
  });

  final Duration freshness;
  final Duration coalesceDelay;
  final Duration initialRetryDelay;
  final Duration maximumRetryDelay;
  final int maximumAttempts;
  final Duration? foregroundInterval;

  Duration retryDelay(int failures) {
    var delay = initialRetryDelay;
    for (var i = 1; i < failures && delay < maximumRetryDelay; ++i) {
      delay *= 2;
    }
    return delay > maximumRetryDelay ? maximumRetryDelay : delay;
  }

  void validate() {
    if (freshness <= Duration.zero ||
        coalesceDelay < Duration.zero ||
        initialRetryDelay <= Duration.zero ||
        maximumRetryDelay < initialRetryDelay ||
        maximumAttempts < 1 ||
        (foregroundInterval != null && foregroundInterval! < freshness)) {
      throw ArgumentError('invalid_message_attention_probe_policy');
    }
  }
}

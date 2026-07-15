import 'package:y300/features/reader_shared/domain/image_session/reader_image_preparation.dart';

class ReaderPerformanceMetrics {
  const ReaderPerformanceMetrics({
    required this.decodeCount,
    required this.averageDecodeLatencyMs,
    required this.maxDecodeLatencyMs,
    required this.preloadRequestCount,
    required this.preloadHitCount,
    required this.preloadHitRatio,
    required this.staleTaskCount,
    required this.providerMismatchCount,
    required this.seekCount,
    required this.averageSeekLatencyMs,
    required this.maxSeekLatencyMs,
    required this.lastCorrectionDelta,
    required this.maxCorrectionDelta,
  });

  final int decodeCount;
  final double averageDecodeLatencyMs;
  final int maxDecodeLatencyMs;
  final int preloadRequestCount;
  final int preloadHitCount;
  final double preloadHitRatio;
  final int staleTaskCount;
  final int providerMismatchCount;
  final int seekCount;
  final double averageSeekLatencyMs;
  final int maxSeekLatencyMs;
  final double lastCorrectionDelta;
  final double maxCorrectionDelta;

  String toLogFields() {
    return 'decodeAvgMs=${averageDecodeLatencyMs.toStringAsFixed(1)} '
        'decodeMaxMs=$maxDecodeLatencyMs '
        'preloadHitRatio=${preloadHitRatio.toStringAsFixed(3)} '
        'staleTasks=$staleTaskCount '
        'providerMismatches=$providerMismatchCount '
        'seekAvgMs=${averageSeekLatencyMs.toStringAsFixed(1)} '
        'seekMaxMs=$maxSeekLatencyMs '
        'lastCorrection=${lastCorrectionDelta.toStringAsFixed(1)} '
        'maxCorrection=${maxCorrectionDelta.toStringAsFixed(1)}';
  }
}

/// Bounded counters for one reader owner session.
///
/// No URL, image bytes, task objects, or latency samples are retained. The
/// collector therefore has constant memory cost even for very long sessions.
class ReaderPerformanceMetricsCollector {
  int _decodeCount = 0;
  int _decodeLatencyTotalMs = 0;
  int _maxDecodeLatencyMs = 0;
  int _preloadRequestCount = 0;
  int _preloadHitCount = 0;
  int _staleTaskCount = 0;
  int _providerMismatchCount = 0;
  int _seekCount = 0;
  int _seekLatencyTotalMs = 0;
  int _maxSeekLatencyMs = 0;
  double _lastCorrectionDelta = 0;
  double _maxCorrectionDelta = 0;

  void reset() {
    _decodeCount = 0;
    _decodeLatencyTotalMs = 0;
    _maxDecodeLatencyMs = 0;
    _preloadRequestCount = 0;
    _preloadHitCount = 0;
    _staleTaskCount = 0;
    _providerMismatchCount = 0;
    _seekCount = 0;
    _seekLatencyTotalMs = 0;
    _maxSeekLatencyMs = 0;
    _lastCorrectionDelta = 0;
    _maxCorrectionDelta = 0;
  }

  void recordPreloadRequest() {
    _preloadRequestCount += 1;
  }

  void recordPreloadHit() {
    _preloadHitCount += 1;
  }

  void recordPreloadResult({
    required ReaderImageSessionPreloadKind kind,
    required Duration elapsed,
    required bool fromDiskCache,
    required bool stale,
    required bool providerMatched,
  }) {
    if (stale) {
      _staleTaskCount += 1;
      return;
    }
    final elapsedMs = elapsed.inMilliseconds;
    if (kind == ReaderImageSessionPreloadKind.decoded) {
      _decodeCount += 1;
      _decodeLatencyTotalMs += elapsedMs;
      if (elapsedMs > _maxDecodeLatencyMs) {
        _maxDecodeLatencyMs = elapsedMs;
      }
    }
    if (fromDiskCache) {
      _preloadHitCount += 1;
    }
    if (!providerMatched) {
      _providerMismatchCount += 1;
    }
  }

  void recordSeek({
    required Duration elapsed,
    required double correctionDelta,
  }) {
    final elapsedMs = elapsed.inMilliseconds;
    final absoluteDelta = correctionDelta.abs();
    _seekCount += 1;
    _seekLatencyTotalMs += elapsedMs;
    if (elapsedMs > _maxSeekLatencyMs) {
      _maxSeekLatencyMs = elapsedMs;
    }
    _lastCorrectionDelta = correctionDelta;
    if (absoluteDelta > _maxCorrectionDelta) {
      _maxCorrectionDelta = absoluteDelta;
    }
  }

  ReaderPerformanceMetrics get snapshot {
    final preloadHits = _preloadHitCount.clamp(0, _preloadRequestCount);
    return ReaderPerformanceMetrics(
      decodeCount: _decodeCount,
      averageDecodeLatencyMs: _decodeCount == 0
          ? 0
          : _decodeLatencyTotalMs / _decodeCount,
      maxDecodeLatencyMs: _maxDecodeLatencyMs,
      preloadRequestCount: _preloadRequestCount,
      preloadHitCount: preloadHits,
      preloadHitRatio: _preloadRequestCount == 0
          ? 0
          : preloadHits / _preloadRequestCount,
      staleTaskCount: _staleTaskCount,
      providerMismatchCount: _providerMismatchCount,
      seekCount: _seekCount,
      averageSeekLatencyMs: _seekCount == 0
          ? 0
          : _seekLatencyTotalMs / _seekCount,
      maxSeekLatencyMs: _maxSeekLatencyMs,
      lastCorrectionDelta: _lastCorrectionDelta,
      maxCorrectionDelta: _maxCorrectionDelta,
    );
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/domain/image_session/reader_image_session.dart';
import 'package:y300/features/reader_shared/domain/metrics/reader_performance_metrics.dart';

void main() {
  test('keeps bounded preload, decode and seek aggregates', () {
    final collector = ReaderPerformanceMetricsCollector();
    for (var i = 0; i < 4; i++) {
      collector.recordPreloadRequest();
    }
    collector.recordPreloadHit();
    collector.recordPreloadResult(
      kind: ReaderImageSessionPreloadKind.decoded,
      elapsed: const Duration(milliseconds: 10),
      fromDiskCache: true,
      stale: false,
      providerMatched: true,
    );
    collector.recordPreloadResult(
      kind: ReaderImageSessionPreloadKind.decoded,
      elapsed: const Duration(milliseconds: 30),
      fromDiskCache: false,
      stale: true,
      providerMatched: true,
    );
    collector.recordPreloadResult(
      kind: ReaderImageSessionPreloadKind.disk,
      elapsed: const Duration(milliseconds: 5),
      fromDiskCache: false,
      stale: false,
      providerMatched: false,
    );
    collector.recordSeek(
      elapsed: const Duration(milliseconds: 20),
      correctionDelta: -100,
    );
    collector.recordSeek(
      elapsed: const Duration(milliseconds: 40),
      correctionDelta: 50,
    );

    final metrics = collector.snapshot;
    expect(metrics.decodeCount, 1);
    expect(metrics.averageDecodeLatencyMs, 10);
    expect(metrics.maxDecodeLatencyMs, 10);
    expect(metrics.preloadRequestCount, 4);
    expect(metrics.preloadHitCount, 2);
    expect(metrics.preloadHitRatio, 0.5);
    expect(metrics.staleTaskCount, 1);
    expect(metrics.providerMismatchCount, 1);
    expect(metrics.seekCount, 2);
    expect(metrics.averageSeekLatencyMs, 30);
    expect(metrics.maxSeekLatencyMs, 40);
    expect(metrics.lastCorrectionDelta, 50);
    expect(metrics.maxCorrectionDelta, 100);
  });

  test('reset starts a fresh owner session without retained samples', () {
    final collector = ReaderPerformanceMetricsCollector()
      ..recordPreloadRequest()
      ..recordPreloadHit()
      ..recordSeek(
        elapsed: const Duration(milliseconds: 12),
        correctionDelta: 30,
      )
      ..reset();

    final metrics = collector.snapshot;
    expect(metrics.preloadRequestCount, 0);
    expect(metrics.preloadHitRatio, 0);
    expect(metrics.seekCount, 0);
    expect(metrics.maxCorrectionDelta, 0);
  });
}

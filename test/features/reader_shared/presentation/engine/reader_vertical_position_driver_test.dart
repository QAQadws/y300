import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_vertical_position_driver.dart';

void main() {
  test(
    'corrects a large estimate delta caused by a preceding tall image',
    () async {
      var offset = 0.0;
      var layoutPass = 0;
      final jumps = <double>[];
      final driver = ReaderVerticalPositionDriver(
        isReady: () => true,
        currentOffset: () => offset,
        clampOffset: (value) => value.clamp(0, 20000).toDouble(),
        jumpTo: (value) {
          offset = value;
          jumps.add(value);
        },
        estimateOffset: (_) => 900,
        exactOffset: (_) => layoutPass == 0 ? null : 9200,
        waitForLayout: () async {
          layoutPass += 1;
        },
      );

      final result = await driver.seekToIndex(8);

      expect(result.status, ReaderVerticalSeekStatus.exact);
      expect(result.correctionDelta, 8300);
      expect(jumps, <double>[900, 9200]);
    },
  );

  test(
    'unknown dimensions can refine before the target anchor is built',
    () async {
      var offset = 0.0;
      var pass = 0;
      final driver = ReaderVerticalPositionDriver(
        isReady: () => true,
        currentOffset: () => offset,
        clampOffset: (value) => value.clamp(0, 5000).toDouble(),
        jumpTo: (value) => offset = value,
        estimateOffset: (_) => pass == 0 ? 700 : 1200,
        exactOffset: (_) => pass < 2 ? null : 1260,
        waitForLayout: () async {
          pass += 1;
        },
      );

      final result = await driver.seekToIndex(4);

      expect(result.status, ReaderVerticalSeekStatus.exact);
      expect(result.correctionPasses, 2);
      expect(offset, 1260);
      expect(result.correctionDelta, 60);
    },
  );

  test(
    'a failed image placeholder still provides an exact list anchor',
    () async {
      var offset = 0.0;
      var placeholderBuilt = false;
      final driver = ReaderVerticalPositionDriver(
        isReady: () => true,
        currentOffset: () => offset,
        clampOffset: (value) => value.clamp(0, 4000).toDouble(),
        jumpTo: (value) => offset = value,
        estimateOffset: (_) => 1400,
        exactOffset: (_) => placeholderBuilt ? 1520 : null,
        waitForLayout: () async {
          placeholderBuilt = true;
        },
      );

      final result = await driver.seekToIndex(3);

      expect(result.status, ReaderVerticalSeekStatus.exact);
      expect(offset, 1520);
    },
  );

  test(
    'manual scrolling cancels pending exact correction immediately',
    () async {
      var offset = 0.0;
      final layout = Completer<void>();
      final driver = ReaderVerticalPositionDriver(
        isReady: () => true,
        currentOffset: () => offset,
        clampOffset: (value) => value.clamp(0, 4000).toDouble(),
        jumpTo: (value) => offset = value,
        estimateOffset: (_) => 1000,
        exactOffset: (_) => null,
        waitForLayout: () => layout.future,
      );

      final pending = driver.seekToIndex(3);
      expect(driver.hasActiveSeek, isTrue);
      expect(
        driver.cancelActive(ReaderVerticalSeekCancelReason.userScroll),
        isTrue,
      );
      final result = await pending;

      expect(result.status, ReaderVerticalSeekStatus.cancelled);
      expect(result.cancelReason, ReaderVerticalSeekCancelReason.userScroll);
      expect(driver.hasActiveSeek, isFalse);
    },
  );
}

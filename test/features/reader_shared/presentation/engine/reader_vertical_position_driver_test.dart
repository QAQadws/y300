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

  for (final failingStep in ['layout', 'exact', 'estimate', 'jump']) {
    test(
      '$failingStep failure releases the request and permits another seek',
      () async {
        var fail = true;
        var offset = 0.0;
        final failure = StateError('$failingStep fixture');
        final driver = ReaderVerticalPositionDriver(
          isReady: () => true,
          currentOffset: () => offset,
          clampOffset: (value) => value,
          jumpTo: (value) {
            if (fail && failingStep == 'jump') throw failure;
            offset = value;
          },
          estimateOffset: (_) {
            if (fail && failingStep == 'estimate') throw failure;
            return 700;
          },
          exactOffset: (_) {
            if (fail && failingStep == 'exact') throw failure;
            return failingStep == 'exact' ? 700 : null;
          },
          waitForLayout: () => fail && failingStep == 'layout'
              ? Future<void>.error(failure)
              : Future<void>.value(),
          maxCorrectionPasses: 1,
        );
        addTearDown(driver.dispose);

        await expectLater(driver.seekToIndex(3), throwsA(same(failure)));
        expect(driver.hasActiveSeek, isFalse);
        fail = false;
        final result = await driver.seekToIndex(4);
        expect(result.reached, isTrue);
        expect(offset, 700);
        expect(driver.hasActiveSeek, isFalse);
      },
    );
  }

  test('superseded request cleanup cannot clear a newer layout wait', () async {
    var offset = 0.0;
    var waits = 0;
    final oldLayout = Completer<void>();
    final newLayout = Completer<void>();
    final driver = ReaderVerticalPositionDriver(
      isReady: () => true,
      currentOffset: () => offset,
      clampOffset: (value) => value,
      jumpTo: (value) => offset = value,
      estimateOffset: (index) => index * 100.0,
      exactOffset: (_) => null,
      waitForLayout: () => waits++ == 0 ? oldLayout.future : newLayout.future,
      maxCorrectionPasses: 1,
    );
    addTearDown(driver.dispose);

    final oldSeek = driver.seekToIndex(1);
    final newSeek = driver.seekToIndex(2);
    final cancelled = await oldSeek;
    expect(cancelled.cancelReason, ReaderVerticalSeekCancelReason.superseded);
    expect(driver.hasActiveSeek, isTrue);
    oldLayout.complete();
    await Future<void>.delayed(Duration.zero);
    expect(driver.hasActiveSeek, isTrue);
    expect(offset, 200);
    newLayout.complete();
    expect((await newSeek).reached, isTrue);
    expect(driver.hasActiveSeek, isFalse);
  });

  test(
    'dispose cancels the current seek while an older cancellation settles',
    () async {
      var offset = 0.0;
      final layouts = [Completer<void>(), Completer<void>()];
      var waits = 0;
      final jumps = <double>[];
      final driver = ReaderVerticalPositionDriver(
        isReady: () => true,
        currentOffset: () => offset,
        clampOffset: (value) => value,
        jumpTo: (value) {
          offset = value;
          jumps.add(value);
        },
        estimateOffset: (index) => index * 100.0,
        exactOffset: (_) => null,
        waitForLayout: () => layouts[waits++].future,
        maxCorrectionPasses: 1,
      );
      final oldSeek = driver.seekToIndex(1);
      final currentSeek = driver.seekToIndex(2);
      driver.dispose();

      expect(
        (await oldSeek).cancelReason,
        ReaderVerticalSeekCancelReason.superseded,
      );
      expect(
        (await currentSeek).cancelReason,
        ReaderVerticalSeekCancelReason.disposed,
      );
      expect(driver.hasActiveSeek, isFalse);
      for (final layout in layouts) {
        layout.complete();
      }
      await Future<void>.delayed(Duration.zero);
      expect(jumps, [100, 200]);
      expect(
        (await driver.seekToIndex(3)).status,
        ReaderVerticalSeekStatus.unavailable,
      );
      expect(driver.hasActiveSeek, isFalse);
    },
  );
}

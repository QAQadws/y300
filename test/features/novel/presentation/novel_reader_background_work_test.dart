import 'dart:async';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_background_work.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_work_slice.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';

void main() {
  testWidgets('cancelling a yielded slice removes its pending timer', (
    tester,
  ) async {
    final token = NovelReaderPaginationCancellationToken();
    final slice = NovelReaderWorkSlice(
      budget: Duration.zero,
      cancellationToken: token,
    );
    final result = expectLater(
      slice.yieldIfNeeded(),
      throwsA(
        isA<NovelReaderPaginationException>().having(
          (error) => error.code,
          'code',
          'paginationCancelled',
        ),
      ),
    );
    token.cancel();
    await result;
    // Intentionally do not pump: cancellation must remove the timer itself.
  });
  test(
    'small transforms stay local and large transforms leave the UI isolate',
    () async {
      final local = Isolate.current.hashCode;
      expect(
        await NovelReaderBackgroundWork.run(
          codeUnits: 10,
          transform: () => Isolate.current.hashCode,
        ),
        local,
      );
      expect(
        await NovelReaderBackgroundWork.run(
          codeUnits: NovelReaderBackgroundWork.codeUnitThreshold,
          transform: () => Isolate.current.hashCode,
        ),
        isNot(local),
      );
    },
  );

  test(
    'background errors propagate without retrying on the UI isolate',
    () async {
      await expectLater(
        NovelReaderBackgroundWork.run<void>(
          codeUnits: NovelReaderBackgroundWork.codeUnitThreshold,
          transform: () => throw StateError('fixture-failure'),
        ),
        throwsStateError,
      );
    },
  );

  test('UI work slices let frame and cancellation events through', () async {
    var eventRan = false;
    Timer.run(() => eventRan = true);
    final slice = NovelReaderWorkSlice(budget: Duration.zero);
    await slice.yieldIfNeeded();
    expect(eventRan, isTrue);
  });
}

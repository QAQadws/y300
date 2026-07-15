import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_position_state.dart';

void main() {
  group('ReaderPositionState', () {
    test(
      'consumes initial restore once while retaining committed position',
      () {
        final state = ReaderPositionState(
          ownerId: 'thread:100:post:p1',
          initialLogicalIndex: 2,
        );

        expect(state.needsInitialRestore, isTrue);
        expect(state.committedLogicalIndex, 2);

        state.consumeInitialRestore();
        state.commitLogicalIndex(4);

        expect(state.needsInitialRestore, isFalse);
        expect(state.committedLogicalIndex, 4);
        expect(state.initialLogicalIndex, 2);
      },
    );

    test('keeps pending paged seek until the same request is applied', () {
      final state = ReaderPositionState(
        ownerId: 'episode-1',
        initialLogicalIndex: 1,
      );

      state.queuePagedSeek(index: 3, generation: 7);
      final pending = state.pendingPagedSeek!;
      expect(pending.logicalIndex, 3);
      expect(pending.generation, 7);

      state.clearPendingPagedSeek(
        const ReaderPendingPagedSeek(logicalIndex: 3, generation: 7),
      );
      expect(state.pendingPagedSeek, same(pending));

      state.clearPendingPagedSeek(pending);
      expect(state.pendingPagedSeek, isNull);
    });
  });
}

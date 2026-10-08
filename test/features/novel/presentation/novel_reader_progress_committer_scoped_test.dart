import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/models/novel_reading_progress.dart';
import 'package:y300/features/novel/domain/repositories/novel_reading_state_repository.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_progress_committer.dart';

void main() {
  const snapshot = NovelReaderProgressSnapshot(
    novelId: 'novel',
    episodeId: 'chapter',
    flowMode: NovelReaderFlowMode.vertical,
    scrollOffset: 420,
    pageIndex: 0,
    progressPercent: .42,
    isProgressPercentValid: true,
    percentBasis: NovelProgressPercentBasis.bodyGeometryV1,
  );

  test(
    'cancel retires an executing transaction and queued optional writes',
    () async {
      final repository = _ControlledRepository();
      final entered = Completer<void>();
      final release = Completer<void>();
      repository.beforeWrite = (_) async {
        entered.complete();
        await release.future;
      };
      final committer = DefaultNovelReaderProgressCommitter(
        repository: repository,
      );
      var callbacks = 0;
      final first = committer.flushScoped(
        snapshot,
        scope: Object(),
        canCommit: () => true,
        onCommitted: () => callbacks++,
      );
      await entered.future;
      final queued = committer.flushScoped(
        snapshot.copyWith(scrollOffset: 430),
        scope: Object(),
        canCommit: () => true,
        onCommitted: () => callbacks++,
      );
      committer.cancel();
      release.complete();
      expect(await first, false);
      expect(await queued, false);
      expect(repository.calls, 1);
      expect(repository.writes, isEmpty);
      expect(callbacks, 0);
    },
  );

  test(
    'producer guard retirement is checked by the actual persistence boundary',
    () async {
      final repository = _ControlledRepository();
      final entered = Completer<void>();
      final release = Completer<void>();
      repository.beforeWrite = (_) async {
        entered.complete();
        await release.future;
      };
      final committer = DefaultNovelReaderProgressCommitter(
        repository: repository,
      );
      var eligible = true;
      var callbacks = 0;
      final pending = committer.flushScoped(
        snapshot,
        scope: Object(),
        canCommit: () => eligible,
        onCommitted: () => callbacks++,
      );
      await entered.future;
      eligible = false;
      release.complete();
      expect(await pending, false);
      expect(repository.writes, isEmpty);
      expect(callbacks, 0);
    },
  );

  test(
    'same position is deduplicated only within the same authority scope',
    () async {
      final repository = _ControlledRepository();
      final committer = DefaultNovelReaderProgressCommitter(
        repository: repository,
      );
      final scope = Object();
      expect(
        await committer.flushScoped(
          snapshot,
          scope: scope,
          canCommit: () => true,
        ),
        true,
      );
      expect(
        await committer.flushScoped(
          snapshot,
          scope: scope,
          canCommit: () => true,
        ),
        true,
      );
      expect(repository.writes, hasLength(1));
      expect(
        await committer.flushScoped(
          snapshot,
          scope: Object(),
          canCommit: () => true,
        ),
        true,
      );
      expect(repository.writes, hasLength(2));
      expect(
        repository.writes.last.percentBasis,
        NovelProgressPercentBasis.bodyGeometryV1,
      );
    },
  );

  test(
    'new generation must persist even an identical position after cancellation',
    () async {
      final repository = _ControlledRepository();
      final committer = DefaultNovelReaderProgressCommitter(
        repository: repository,
      );
      final scope = Object();
      await committer.flushScoped(
        snapshot,
        scope: scope,
        canCommit: () => true,
      );
      committer.cancel();
      await committer.flushScoped(
        snapshot,
        scope: scope,
        canCommit: () => true,
      );
      expect(repository.writes, hasLength(2));
    },
  );

  test(
    'a failed write does not poison the serial queue or deduplicate its retry',
    () async {
      final repository = _ControlledRepository();
      var fail = true;
      repository.beforeWrite = (_) async {
        if (fail) {
          fail = false;
          throw StateError('controlled failure');
        }
      };
      final committer = DefaultNovelReaderProgressCommitter(
        repository: repository,
      );
      final scope = Object();
      final failed = committer.flushScoped(
        snapshot,
        scope: scope,
        canCommit: () => true,
      );
      final retried = committer.flushScoped(
        snapshot,
        scope: scope,
        canCommit: () => true,
      );
      await expectLater(failed, throwsStateError);
      expect(await retried, true);
      expect(repository.calls, 2);
      expect(repository.writes, hasLength(1));
    },
  );

  test('retired queued scope cannot replace a later active owner', () async {
    final repository = _ControlledRepository();
    final entered = Completer<void>();
    final release = Completer<void>();
    repository.beforeWrite = (call) async {
      if (call == 1) {
        entered.complete();
        await release.future;
      }
    };
    final committer = DefaultNovelReaderProgressCommitter(
      repository: repository,
    );
    var firstEligible = true;
    final first = committer.flushScoped(
      snapshot,
      scope: Object(),
      canCommit: () => firstEligible,
    );
    await entered.future;
    final next = committer.flushScoped(
      snapshot.copyWith(scrollOffset: 999),
      scope: Object(),
      canCommit: () => true,
    );
    firstEligible = false;
    release.complete();
    expect(await first, false);
    expect(await next, true);
    expect(repository.writes.single.scrollOffset, 999);
  });
}

class _ControlledRepository
    implements NovelRepository, NovelReadingStateRepository {
  int calls = 0;
  Future<void> Function(int)? beforeWrite;
  final List<NovelReadingProgress> writes = [];
  @override
  Future<bool> commitProgress({
    required NovelReadingProgress progress,
    bool markCompleted = false,
    bool Function()? canCommit,
  }) async {
    calls++;
    await beforeWrite?.call(calls);
    if (canCommit?.call() == false) return false;
    writes.add(progress);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

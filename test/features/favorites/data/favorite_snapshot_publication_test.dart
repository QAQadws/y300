import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/favorites/data/services/favorite_execution_queue.dart';
import 'package:y300/features/favorites/data/services/favorite_snapshot_publication.dart';

void main() {
  test('waiting foreground publications share one latest-state snapshot write per owner', () async {
    final publication = FavoriteSnapshotPublication();
    final queue = FavoriteExecutionQueue();
    final entered = Completer<void>(), release = Completer<void>();
    final blocker = queue.run(() async {
      entered.complete();
      await release.future;
    });
    await entered.future;
    var writes = 0, state = 0, savedState = -1;
    Future<void> publish() => queue.run(() async {
      writes++;
      savedState = state;
    });
    final requests = [
      for (var i = 0; i < 8; i++) publication.request('owner', publish),
    ];
    state = 8;
    release.complete();
    await blocker;
    await Future.wait(requests);
    expect(writes, 1);
    expect(savedState, 8);
    await publication.request('owner', publish);
    expect(writes, 2);
  });

  test(
    'a failed publication cannot poison another owner or a later retry',
    () async {
      final publication = FavoriteSnapshotPublication();
      final gate = Completer<void>();
      final failed = expectLater(
        publication.request('old', () async {
          await gate.future;
          throw StateError('fixture');
        }),
        throwsStateError,
      );
      var saved = false;
      await publication.request('new', () async => saved = true);
      expect(saved, isTrue);
      gate.complete();
      await failed;
      await publication.request('old', () async {});
    },
  );
}

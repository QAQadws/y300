import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/presentation/services/comic_reader_image_recovery_coordinator.dart';

void main() {
  test(
    'manual retry can take over after probe completion before publication',
    () async {
      final probe = _Probe();
      final recovery = ComicReaderImageRecoveryCoordinator(
        probeEpisode: probe.call,
      );
      final session = _open(recovery);
      final retry = _automatic(recovery, session, 0)!;
      probe.pending.single.complete();
      await retry.ready;
      final manual = recovery.prepareManualRetry(
        session: session,
        imageIndex: 0,
        imageUrl: 'image-0',
      );
      expect(retry.claimRetry(), isFalse);
      expect(probe.tids, ['source-A', 'source-A']);
      probe.pending.last.complete();
      await manual;
    },
  );

  test(
    'concurrent failures and chapter-only retry share one active probe',
    () async {
      final probe = _Probe();
      final recovery = ComicReaderImageRecoveryCoordinator(
        probeEpisode: probe.call,
      );
      final session = _open(recovery);
      expect(_open(recovery), same(session));
      final first = _automatic(recovery, session, 0)!;
      final second = _automatic(recovery, session, 1)!;
      final manual = recovery.prepareManualRetry(session: session);
      expect(probe.tids, ['source-A']);
      expect(_automatic(recovery, session, 0), isNull);
      expect(first.claimRetry(), isFalse);

      probe.pending.single.complete();
      await Future.wait([first.ready, second.ready, manual]);
      expect(first.claimRetry(), isTrue);
      expect(first.claimRetry(), isFalse);
      expect(second.claimRetry(), isTrue);
      expect(_automatic(recovery, session, 0), isNull);
    },
  );

  test(
    'manual retry takes over only its image, including a failed probe',
    () async {
      final probe = _Probe();
      final recovery = ComicReaderImageRecoveryCoordinator(
        probeEpisode: probe.call,
      );
      final session = _open(recovery);
      final first = _automatic(recovery, session, 0)!;
      final second = _automatic(recovery, session, 1)!;
      final manual = recovery.prepareManualRetry(
        session: session,
        imageIndex: 0,
        imageUrl: 'image-0',
      );
      probe.pending.single.completeError(
        StateError('parse failed after recovery'),
      );
      await Future.wait([first.ready, second.ready, manual]);
      expect(first.claimRetry(), isFalse);
      expect(second.claimRetry(), isTrue);

      final later = recovery.prepareManualRetry(
        session: session,
        imageIndex: 0,
        imageUrl: 'image-0',
      );
      expect(probe.tids, ['source-A', 'source-A']);
      probe.pending.last.complete();
      await later;
    },
  );

  test('a different later failure starts a new probe without looping an old failure', () async {
    final probe = _Probe();
    final recovery = ComicReaderImageRecoveryCoordinator(
      probeEpisode: probe.call,
    );
    final session = _open(recovery);
    final first = _automatic(recovery, session, 0)!;
    probe.pending.single.complete();
    await first.ready;
    expect(first.claimRetry(), isTrue);
    expect(_automatic(recovery, session, 0), isNull);
    final next = _automatic(recovery, session, 1)!;
    expect(probe.tids, ['source-A', 'source-A']);
    probe.pending.last.complete();
    await next.ready;
    expect(next.claimRetry(), isTrue);
  });

  test(
    'resolution retires a pending attempt before the same image fails again',
    () async {
      final probe = _Probe();
      final recovery = ComicReaderImageRecoveryCoordinator(
        probeEpisode: probe.call,
      );
      final session = _open(recovery);
      final old = _automatic(recovery, session, 0)!;
      recovery.imageResolved(
        session: session,
        imageIndex: 0,
        imageUrl: 'image-0',
      );
      final current = _automatic(recovery, session, 0)!;
      expect(probe.tids, ['source-A']);
      probe.pending.single.complete();
      await Future.wait([old.ready, current.ready]);
      expect(old.claimRetry(), isFalse);
      expect(current.claimRetry(), isTrue);
    },
  );

  test('A-B-A identities retire old callbacks and old cleanup cannot release a new probe', () async {
    final probe = _Probe();
    final recovery = ComicReaderImageRecoveryCoordinator(
      probeEpisode: probe.call,
    );
    final oldSession = _open(recovery);
    final old = _automatic(recovery, oldSession, 0)!;
    _open(recovery, episode: 'B', source: 'source-B');
    final currentSession = _open(recovery);
    final current = _automatic(recovery, currentSession, 0)!;
    expect(currentSession, isNot(same(oldSession)));
    probe.pending.first.complete();
    await old.ready;
    expect(old.claimRetry(), isFalse);
    final joined = recovery.prepareManualRetry(session: currentSession);
    expect(probe.tids, ['source-A', 'source-A']);
    probe.pending.last.complete();
    await Future.wait([current.ready, joined]);
    expect(current.claimRetry(), isTrue);
  });

  for (final change in ['retire', 'generation', 'source', 'close']) {
    test(
      '$change immediately rejects late retries and stale manual work',
      () async {
        final probe = _Probe();
        final recovery = ComicReaderImageRecoveryCoordinator(
          probeEpisode: probe.call,
        );
        final session = _open(recovery);
        final retry = _automatic(recovery, session, 0)!;
        switch (change) {
          case 'retire':
            recovery.retire();
          case 'generation':
            _open(recovery, generation: 2);
          case 'source':
            _open(recovery, source: 'new-source');
          case 'close':
            recovery.close();
        }
        await recovery.prepareManualRetry(session: session);
        expect(_automatic(recovery, session, 1), isNull);
        expect(probe.tids, ['source-A']);
        probe.pending.single.complete();
        await retry.ready;
        expect(retry.claimRetry(), isFalse);
        if (change == 'close') {
          recovery.close();
          expect(() => _open(recovery), throwsStateError);
        }
      },
    );
  }

  test(
    'a synchronous probe failure still permits one direct automatic retry',
    () async {
      final recovery = ComicReaderImageRecoveryCoordinator(
        probeEpisode: (_) => throw StateError('probe'),
      );
      final retry = _automatic(recovery, _open(recovery), 0)!;
      await retry.ready;
      expect(retry.claimRetry(), isTrue);
    },
  );
}

ComicReaderImageRecoverySession _open(
  ComicReaderImageRecoveryCoordinator recovery, {
  String episode = 'A',
  String source = 'source-A',
  int generation = 1,
}) => recovery.activate(
  episodeId: episode,
  sourceTid: source,
  generation: generation,
);

ComicReaderAutomaticImageRetry? _automatic(
  ComicReaderImageRecoveryCoordinator recovery,
  ComicReaderImageRecoverySession session,
  int index,
) => recovery.startAutomaticRetry(
  session: session,
  imageIndex: index,
  imageUrl: 'image-$index',
);

final class _Probe {
  final tids = <String>[];
  final pending = <Completer<void>>[];
  Future<void> call(String tid) {
    tids.add(tid);
    final result = Completer<void>();
    pending.add(result);
    return result.future;
  }
}

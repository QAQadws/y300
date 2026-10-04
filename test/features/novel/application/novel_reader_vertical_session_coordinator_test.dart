import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/application/novel_reader_vertical_session_coordinator.dart';

void main() {
  test('ordinary rebuild keeps the current lease and restored position', () {
    final coordinator = NovelReaderVerticalSessionCoordinator();
    final first = _bind(coordinator, 'A');
    coordinator.markContentReady(first);
    coordinator.claimPosition(first);
    expect(_bind(coordinator, 'A'), same(first));
    expect(coordinator.contentReady, isTrue);
    expect(coordinator.hasRestoredOffset, isTrue);
  });

  test('returning to the same owner never revives the first lease', () {
    final coordinator = NovelReaderVerticalSessionCoordinator();
    final first = _bind(coordinator, 'A');
    coordinator.markContentReady(first);
    final oldRestore = coordinator.beginRestore(first)!;
    _bind(coordinator, 'B');
    final current = _bind(coordinator, 'A');
    coordinator.markContentReady(current);
    final newRestore = coordinator.beginRestore(current)!;
    expect(current, isNot(same(first)));
    expect(coordinator.markContentReady(first), isFalse);
    expect(coordinator.finishRestore(oldRestore, applied: true), isFalse);
    expect(coordinator.ownsRestore(newRestore), isTrue);
    expect(coordinator.hasRestoredOffset, isFalse);
    expect(coordinator.finishRestore(newRestore, applied: true), isTrue);
  });

  test('old scheduled callbacks cannot take the new frame request', () {
    final coordinator = NovelReaderVerticalSessionCoordinator();
    final first = _bind(coordinator, 'A');
    coordinator.markContentReady(first);
    final oldFrame = coordinator.scheduleRestore(first)!;
    coordinator.retire();
    final current = _bind(coordinator, 'A');
    coordinator.markContentReady(current);
    final newFrame = coordinator.scheduleRestore(current)!;
    expect(coordinator.takeScheduledRestore(oldFrame), isFalse);
    expect(coordinator.hasScheduledRestore(current), isTrue);
    expect(coordinator.takeScheduledRestore(newFrame), isTrue);
    expect(coordinator.hasScheduledRestore(current), isFalse);
  });

  test(
    'failed same-content switch restores known readiness under a new lease',
    () {
      final coordinator = NovelReaderVerticalSessionCoordinator();
      final first = _bind(coordinator, 'A');
      coordinator.markContentReady(first);
      coordinator.claimPosition(first);
      final transition = coordinator.beginChapterTransition(
        surfaceIdentity: 'A',
        episodeId: 'A',
        visibleOffset: 321,
      );
      coordinator.suspendForChapterTransition(visibleOffset: 321);
      final dormant = coordinator.bind(
        surfaceIdentity: 'A',
        episodeId: 'A',
        isTransitioning: true,
      );
      expect(coordinator.isCurrent(dormant), isFalse);
      expect(coordinator.markContentReady(first), isFalse);
      final recovered = coordinator.recoverChapterTransition(transition)!;
      expect(recovered, isNot(same(first)));
      expect(coordinator.contentReady, isTrue);
      expect(coordinator.restoreOffsetOverride, 321);
      expect(coordinator.hasRestoredOffset, isFalse);
      final restore = coordinator.beginRestore(recovered)!;
      expect(coordinator.finishRestore(restore, applied: true), isTrue);
      expect(coordinator.restoreOffsetOverride, isNull);
    },
  );

  test(
    'first ready or terminal during transition is retained as proof only',
    () {
      final coordinator = NovelReaderVerticalSessionCoordinator();
      final first = _bind(coordinator, 'A');
      coordinator.suspendForChapterTransition();
      coordinator.markSuspendedContent(first);
      coordinator.markSuspendedContent(first, terminal: true);
      expect(coordinator.session, isNull);
      final recovered = _bind(coordinator, 'A');
      expect(recovered, isNot(same(first)));
      expect(coordinator.contentReady, isTrue);
      expect(coordinator.terminalReady, isTrue);
      expect(coordinator.hasRestoredOffset, isFalse);
    },
  );

  test('another surface and provider retirement drop suspended proof', () {
    final coordinator = NovelReaderVerticalSessionCoordinator();
    final first = _bind(coordinator, 'A');
    coordinator.markContentReady(first);
    coordinator.suspendForChapterTransition(visibleOffset: 321);
    _bind(coordinator, 'B');
    final returned = _bind(coordinator, 'A');
    expect(coordinator.contentReady, isFalse);
    coordinator.markContentReady(returned);
    final transition = coordinator.beginChapterTransition(
      surfaceIdentity: 'A',
      episodeId: 'A',
    );
    coordinator.suspendForChapterTransition();
    coordinator.retire();
    coordinator.markSuspendedContent(returned);
    _bind(coordinator, 'A');
    expect(coordinator.contentReady, isFalse);
    expect(coordinator.ownsChapterTransition(transition), isFalse);
  });

  test(
    'theme signatures returning to the same value keep request identity',
    () {
      final coordinator = NovelReaderVerticalSessionCoordinator();
      final session = _bind(coordinator, 'A');
      coordinator.markContentReady(session);
      coordinator.claimPosition(session);
      final first = coordinator.trackTheme(
        session,
        'light',
        visibleOffset: 123,
      );
      final middle = coordinator.trackTheme(
        session,
        'dark',
        visibleOffset: 321,
      );
      final latest = coordinator.trackTheme(session, 'light', visibleOffset: 0);
      expect(latest, isNot(same(first)));
      expect(coordinator.themeRestoreOffset(latest), 321);
      coordinator.clearThemeRestore(first);
      coordinator.clearThemeRestore(middle);
      expect(coordinator.themeRestoreOffset(latest), 321);
      coordinator.clearThemeRestore(latest);
      expect(coordinator.hasPendingThemeRestore, isFalse);
    },
  );

  test('a cancelled restore releases only its request and permits retry', () {
    final coordinator = NovelReaderVerticalSessionCoordinator();
    final session = _bind(coordinator, 'A');
    coordinator.markContentReady(session);
    final first = coordinator.beginRestore(session)!;
    expect(coordinator.beginRestore(session), isNull);
    expect(coordinator.finishRestore(first, applied: false), isFalse);
    final latest = coordinator.beginRestore(session)!;
    expect(coordinator.finishRestore(first, applied: true), isFalse);
    expect(coordinator.ownsRestore(latest), isTrue);
    coordinator.claimPosition(session);
    expect(coordinator.finishRestore(latest, applied: true), isFalse);
    expect(coordinator.hasRestoredOffset, isTrue);
  });

  test('old transition completion cannot clear or recover a newer request', () {
    final coordinator = NovelReaderVerticalSessionCoordinator();
    _bind(coordinator, 'A');
    final first = coordinator.beginChapterTransition(
      surfaceIdentity: 'A',
      episodeId: 'A',
    );
    final latest = coordinator.beginChapterTransition(
      surfaceIdentity: 'A',
      episodeId: 'A',
    );
    coordinator.finishChapterTransition(first);
    expect(coordinator.recoverChapterTransition(first), isNull);
    expect(coordinator.ownsChapterTransition(latest), isTrue);
    coordinator.finishChapterTransition(latest);
    expect(coordinator.ownsChapterTransition(latest), isFalse);
  });

  test(
    'reload preserves only confirmed readiness and rejects the old callback',
    () {
      final coordinator = NovelReaderVerticalSessionCoordinator();
      final first = _bind(coordinator, 'A');
      coordinator.markContentReady(first);
      coordinator.claimPosition(first);
      final transition = coordinator.beginChapterTransition(
        surfaceIdentity: 'A',
        episodeId: 'A',
        visibleOffset: 321,
      );
      coordinator.retire(preserveContentProof: true);
      coordinator.retire(preserveContentProof: true);
      coordinator.markSuspendedContent(first, terminal: true);
      expect(coordinator.isCurrent(first), isFalse);
      expect(coordinator.ownsChapterTransition(transition), isFalse);
      final current = _bind(coordinator, 'A');
      expect(current, isNot(same(first)));
      expect(coordinator.contentReady, isTrue);
      expect(coordinator.terminalReady, isFalse);
      expect(coordinator.restoreOffsetOverride, isNull);
    },
  );

  test('a rendered loading surface discards the physical content proof', () {
    final coordinator = NovelReaderVerticalSessionCoordinator();
    final first = _bind(coordinator, 'A');
    coordinator.markContentReady(first);
    coordinator.retire(preserveContentProof: true);
    coordinator.retire();
    coordinator.markSuspendedContent(first);
    _bind(coordinator, 'A');
    expect(coordinator.contentReady, isFalse);
    expect(coordinator.restoreOffsetOverride, isNull);
  });

  test(
    'a loaded different surface drops old position before an unpainted return',
    () {
      final coordinator = NovelReaderVerticalSessionCoordinator();
      final first = _bind(coordinator, 'A');
      coordinator.markContentReady(first);
      coordinator.claimPosition(first);
      coordinator.suspendForChapterTransition(visibleOffset: 321);
      coordinator.observeSurface('B');
      coordinator.markSuspendedContent(first, terminal: true);
      final returned = _bind(coordinator, 'A');
      expect(returned, isNot(same(first)));
      expect(coordinator.contentReady, isTrue);
      expect(coordinator.terminalReady, isFalse);
      expect(coordinator.restoreOffsetOverride, isNull);
    },
  );

  test('disposal makes all outstanding callbacks inert', () {
    final coordinator = NovelReaderVerticalSessionCoordinator();
    final session = _bind(coordinator, 'A');
    coordinator.markContentReady(session);
    final frame = coordinator.scheduleRestore(session)!;
    final theme = coordinator.trackTheme(session, 'light');
    final transition = coordinator.beginChapterTransition(
      surfaceIdentity: 'A',
      episodeId: 'A',
    );
    coordinator.dispose();
    expect(coordinator.markContentReady(session), isFalse);
    expect(coordinator.takeScheduledRestore(frame), isFalse);
    expect(coordinator.ownsTheme(theme), isFalse);
    expect(coordinator.recoverChapterTransition(transition), isNull);
  });
}

NovelReaderVerticalSessionToken _bind(
  NovelReaderVerticalSessionCoordinator coordinator,
  String owner,
) => coordinator.bind(surfaceIdentity: owner, episodeId: owner);

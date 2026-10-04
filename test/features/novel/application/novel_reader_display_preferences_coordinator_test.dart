import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/application/novel_reader_display_preferences_coordinator.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';

void main() {
  test('previews leading and latest trailing values, debounces one save', () {
    fakeAsync((clock) {
      final fixture = _PreferencesFixture();
      final first = fixture.initial.copyWith(fontSize: 20);
      final latest = fixture.initial.copyWith(fontSize: 23);
      fixture.coordinator.change(first);
      expect(fixture.previews, [first]);
      clock.elapse(const Duration(milliseconds: 30));
      fixture.coordinator.change(latest);
      expect(fixture.previews, [first]);
      clock.elapse(const Duration(milliseconds: 60));
      expect(fixture.previews, [first, latest]);
      clock.elapse(const Duration(milliseconds: 459));
      expect(fixture.saves, isEmpty);
      clock.elapse(const Duration(milliseconds: 1));
      expect(fixture.saves.map((save) => save.preferences), [latest]);
      fixture.saves.single.complete();
      clock.flushMicrotasks();
      fixture.coordinator.flush();
      clock.flushMicrotasks();
      expect(fixture.saves, hasLength(1));
      expect(fixture.persisted, latest);
      fixture.coordinator.dispose();
    });
  });

  test(
    'dismissal previews pending value and awaits an identical active save',
    () {
      fakeAsync((clock) {
        final fixture = _PreferencesFixture();
        final first = fixture.initial.copyWith(fontSize: 20);
        final latest = fixture.initial.copyWith(fontSize: 23);
        fixture.coordinator.change(first);
        fixture.coordinator.change(latest);
        var firstFlushDone = false;
        fixture.coordinator.flush().then((_) => firstFlushDone = true);
        clock.flushMicrotasks();
        expect(fixture.effective, latest);
        expect(fixture.saves, hasLength(1));
        var secondFlushDone = false;
        fixture.coordinator.flush().then((_) => secondFlushDone = true);
        clock.flushMicrotasks();
        expect(firstFlushDone, isFalse);
        expect(secondFlushDone, isFalse);
        fixture.saves.single.complete();
        clock.flushMicrotasks();
        expect(firstFlushDone, isTrue);
        expect(secondFlushDone, isTrue);
        clock.elapse(const Duration(seconds: 1));
        expect(fixture.saves, hasLength(1));
        fixture.coordinator.dispose();
      });
    },
  );

  test(
    'returning to the original preference waits then durably restores it',
    () {
      fakeAsync((clock) {
        final fixture = _PreferencesFixture();
        final first = fixture.initial.copyWith(fontSize: 20);
        fixture.coordinator.commitImmediately(first);
        clock.flushMicrotasks();
        var restored = false;
        fixture.coordinator
            .commitImmediately(fixture.initial)
            .then((_) => restored = true);
        clock.flushMicrotasks();
        expect(fixture.saves, hasLength(1));
        expect(fixture.effective, fixture.initial);
        fixture.saves.first.complete();
        clock.flushMicrotasks();
        expect(fixture.saves.map((save) => save.preferences), [
          first,
          fixture.initial,
        ]);
        expect(restored, isFalse);
        fixture.saves.last.complete();
        clock.flushMicrotasks();
        expect(restored, isTrue);
        expect(fixture.persisted, fixture.initial);
        fixture.coordinator.dispose();
      });
    },
  );

  test('queued intermediate choices are superseded while a save is active', () {
    fakeAsync((clock) {
      final fixture = _PreferencesFixture();
      final first = fixture.initial.copyWith(fontSize: 20);
      final middle = fixture.initial.copyWith(fontSize: 22);
      final latest = fixture.initial.copyWith(fontSize: 24);
      fixture.coordinator.commitImmediately(first);
      clock.flushMicrotasks();
      fixture.coordinator.commitImmediately(middle);
      fixture.coordinator.commitImmediately(latest);
      clock.flushMicrotasks();
      expect(fixture.saves, hasLength(1));
      fixture.saves.first.complete();
      clock.flushMicrotasks();
      expect(fixture.saves.map((save) => save.preferences), [first, latest]);
      fixture.saves.last.complete();
      clock.flushMicrotasks();
      expect(fixture.persisted, latest);
      fixture.coordinator.dispose();
    });
  });

  test('old save failure preserves a newer preview and its pending save', () {
    fakeAsync((clock) {
      final fixture = _PreferencesFixture();
      final first = fixture.initial.copyWith(fontSize: 20);
      final latest = fixture.initial.copyWith(fontSize: 24);
      fixture.coordinator.commitImmediately(first);
      clock.flushMicrotasks();
      fixture.coordinator.change(latest);
      fixture.saves.first.fail();
      clock.flushMicrotasks();
      expect(fixture.effective, latest);
      expect(fixture.rollbackCount, 0);
      expect(fixture.failureCount, 0);
      clock.elapse(const Duration(milliseconds: 520));
      expect(fixture.saves.map((save) => save.preferences), [first, latest]);
      fixture.saves.last.complete();
      clock.flushMicrotasks();
      expect(fixture.persisted, latest);
      fixture.coordinator.dispose();
    });
  });

  test('latest failure rolls back once and an explicit flush can retry', () {
    fakeAsync((clock) {
      final fixture = _PreferencesFixture();
      final next = fixture.initial.copyWith(fontSize: 24);
      fixture.coordinator.commitImmediately(next);
      clock.flushMicrotasks();
      fixture.saves.single.fail();
      clock.flushMicrotasks();
      expect(fixture.effective, fixture.initial);
      expect(fixture.rollbackCount, 1);
      expect(fixture.failureCount, 1);
      fixture.coordinator.flush();
      clock.flushMicrotasks();
      expect(fixture.effective, next);
      expect(fixture.saves, hasLength(2));
      fixture.saves.last.complete();
      clock.flushMicrotasks();
      expect(fixture.persisted, next);
      fixture.coordinator.dispose();
    });
  });

  test(
    'immediate fallback shares the save queue and uses its failure callback',
    () {
      fakeAsync((clock) {
        final fixture = _PreferencesFixture();
        final next = fixture.initial.copyWith(fontSize: 24);
        final vertical = next.copyWith(flowMode: NovelReaderFlowMode.vertical);
        fixture.coordinator.commitImmediately(next);
        clock.flushMicrotasks();
        var fallbackFailures = 0;
        fixture.coordinator.commitImmediately(
          vertical,
          onFailure: () => fallbackFailures += 1,
        );
        clock.flushMicrotasks();
        expect(fixture.saves, hasLength(1));
        fixture.saves.first.complete();
        clock.flushMicrotasks();
        fixture.saves.last.fail();
        clock.flushMicrotasks();
        expect(fixture.effective, next);
        expect(fallbackFailures, 1);
        expect(fixture.failureCount, 0);
        fixture.coordinator.dispose();
      });
    },
  );

  test('reopening settings keeps an active save ahead of the new choice', () {
    fakeAsync((clock) {
      final fixture = _PreferencesFixture();
      final first = fixture.initial.copyWith(fontSize: 20);
      final latest = fixture.initial.copyWith(fontSize: 24);
      fixture.coordinator.commitImmediately(first);
      clock.flushMicrotasks();
      fixture.coordinator.begin(
        preferences: first,
        persistedPreferences: fixture.initial,
      );
      fixture.coordinator.change(latest);
      fixture.coordinator.flush();
      clock.flushMicrotasks();
      expect(fixture.saves, hasLength(1));
      fixture.saves.first.complete();
      clock.flushMicrotasks();
      expect(fixture.saves.map((save) => save.preferences), [first, latest]);
      fixture.saves.last.complete();
      clock.flushMicrotasks();
      expect(fixture.persisted, latest);
      fixture.coordinator.dispose();
    });
  });

  test('dispose cancels delayed choices and ignores a late active failure', () {
    fakeAsync((clock) {
      final fixture = _PreferencesFixture();
      fixture.coordinator.commitImmediately(
        fixture.initial.copyWith(fontSize: 20),
      );
      clock.flushMicrotasks();
      fixture.coordinator.change(fixture.initial.copyWith(fontSize: 24));
      fixture.coordinator.dispose();
      fixture.saves.single.fail();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      expect(fixture.saves, hasLength(1));
      expect(fixture.rollbackCount, 0);
      expect(fixture.failureCount, 0);
    });
  });

  test('replacement coordinator waits for the retired active save', () {
    fakeAsync((clock) {
      final old = _PreferencesFixture();
      old.coordinator.commitImmediately(old.initial.copyWith(fontSize: 20));
      clock.flushMicrotasks();
      final replacement = _PreferencesFixture(
        precedingCommit: old.coordinator.dispose(),
      );
      final next = replacement.initial.copyWith(fontSize: 24);
      replacement.coordinator.commitImmediately(next);
      clock.flushMicrotasks();
      expect(replacement.saves, isEmpty);
      old.saves.single.fail();
      clock.flushMicrotasks();
      expect(old.failureCount, 0);
      expect(replacement.saves, hasLength(1));
      replacement.saves.single.complete();
      clock.flushMicrotasks();
      expect(replacement.persisted, next);
      replacement.coordinator.dispose();
    });
  });

  test(
    'replacement confirms a baseline selected after an old successful write',
    () {
      fakeAsync((clock) {
        final old = _PreferencesFixture();
        old.coordinator.commitImmediately(old.initial.copyWith(fontSize: 20));
        clock.flushMicrotasks();
        final replacement = _PreferencesFixture(
          precedingCommit: old.coordinator.dispose(),
        );
        replacement.coordinator.change(
          replacement.initial.copyWith(fontSize: 24),
        );
        replacement.coordinator.change(replacement.initial);
        replacement.coordinator.flush();
        clock.flushMicrotasks();
        expect(replacement.saves, isEmpty);
        old.saves.single.complete();
        clock.flushMicrotasks();
        expect(replacement.saves.map((save) => save.preferences), [
          replacement.initial,
        ]);
        replacement.saves.single.complete();
        clock.flushMicrotasks();
        expect(replacement.persisted, replacement.initial);
        replacement.coordinator.dispose();
      });
    },
  );
}

class _PreferencesFixture {
  _PreferencesFixture({Future<void>? precedingCommit}) {
    persisted = initial;
    effective = initial;
    coordinator = NovelReaderDisplayPreferencesCoordinator(
      preview: (preferences) {
        previews.add(preferences);
        effective = preferences;
      },
      commit: (preferences) async {
        final save = _PendingSave(preferences);
        saves.add(save);
        await save.completer.future;
        persisted = preferences;
      },
      revertPreview: () {
        rollbackCount += 1;
        effective = persisted;
      },
      onFailure: () => failureCount += 1,
      precedingCommit: precedingCommit,
    )..begin(preferences: initial, persistedPreferences: initial);
  }

  final initial = NovelReaderPreferences.defaults();
  late NovelReaderPreferences persisted;
  late NovelReaderPreferences effective;
  late final NovelReaderDisplayPreferencesCoordinator coordinator;
  final previews = <NovelReaderPreferences>[];
  final saves = <_PendingSave>[];
  int rollbackCount = 0;
  int failureCount = 0;
}

class _PendingSave {
  _PendingSave(this.preferences);

  final NovelReaderPreferences preferences;
  final completer = Completer<void>();

  void complete() => completer.complete();
  void fail() => completer.completeError(StateError('preference save failed'));
}

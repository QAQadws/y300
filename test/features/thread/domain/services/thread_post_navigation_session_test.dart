import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/thread/domain/services/thread_post_navigation_session.dart';

void main() {
  test('double click shares one action, completion is not cached', () async {
    final session = ThreadPostNavigationSession();
    final pending = Completer<void>();
    var calls = 0;
    Future<void> run() => session.run(
      key: ('100', '200'),
      isCurrent: () => true,
      action: (_) async {
        calls++;
        await pending.future;
      },
    );
    final first = run();
    final second = run();
    expect(first, same(second));
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    pending.complete();
    await first;
    await run();
    expect(calls, 2);
  });

  test(
    'same target starts fresh after its pending source lease is retired',
    () async {
      final session = ThreadPostNavigationSession();
      final oldResponse = Completer<void>();
      final newResponse = Completer<void>();
      final opened = <String>[];
      var oldCurrent = true;
      var newCalls = 0;
      final first = session.run(
        key: 'target',
        isCurrent: () => oldCurrent,
        action: (current) async {
          await oldResponse.future;
          if (current()) opened.add('old');
        },
      );
      await Future<void>.delayed(Duration.zero);
      oldCurrent = false;
      Future<void> runNew() => session.run(
        key: 'target',
        isCurrent: () => true,
        action: (current) async {
          newCalls++;
          await newResponse.future;
          if (current()) opened.add('new');
        },
      );
      final second = runNew();
      expect(second, isNot(same(first)));
      await Future<void>.delayed(Duration.zero);
      expect(newCalls, 1);
      // Restoring the old predicate cannot revive a retired generation, and
      // its late completion cannot clear the replacement's single-flight slot.
      oldCurrent = true;
      oldResponse.complete();
      await first;
      expect(opened, isEmpty);
      expect(runNew(), same(second));
      newResponse.complete();
      await second;
      expect(opened, ['new']);
      expect(newCalls, 1);
      await runNew();
      expect(newCalls, 2);
      session.dispose();
    },
  );

  test('same target replaces a retired lease before work starts', () async {
    final session = ThreadPostNavigationSession();
    var oldCurrent = true;
    final started = <String>[];
    final first = session.run(
      key: 'target',
      isCurrent: () => oldCurrent,
      action: (_) async => started.add('old'),
    );
    oldCurrent = false;
    final second = session.run(
      key: 'target',
      isCurrent: () => true,
      action: (_) async => started.add('new'),
    );
    expect(second, isNot(same(first)));
    await Future.wait([first, second]);
    expect(started, ['new']);
    session.dispose();
  });

  test(
    'new target supersedes old response without clearing new flight',
    () async {
      final session = ThreadPostNavigationSession();
      final oldResponse = Completer<void>();
      final newResponse = Completer<void>();
      final opened = <String>[];
      Future<void> run(String target, Completer<void> response) => session.run(
        key: target,
        isCurrent: () => true,
        action: (current) async {
          await response.future;
          if (current()) opened.add(target);
        },
      );
      final first = run('old', oldResponse);
      await Future<void>.delayed(Duration.zero);
      final second = run('new', newResponse);
      oldResponse.complete();
      await first;
      expect(run('new', newResponse), same(second));
      newResponse.complete();
      await second;
      expect(opened, ['new']);
    },
  );

  for (final change in ['chapter', 'exit', 'owner']) {
    test('$change discards a late result', () async {
      final session = ThreadPostNavigationSession();
      final pending = Completer<void>();
      var ownerCurrent = true;
      var opened = false;
      final result = session.run(
        key: 'target',
        isCurrent: () => ownerCurrent,
        action: (current) async {
          await pending.future;
          opened = current();
        },
      );
      await Future<void>.delayed(Duration.zero);
      switch (change) {
        case 'chapter':
          session.invalidate();
        case 'exit':
          session.dispose();
        case 'owner':
          ownerCurrent = false;
      }
      pending.complete();
      await result;
      expect(opened, isFalse);
    });
  }

  test('failed action can be attempted again', () async {
    final session = ThreadPostNavigationSession();
    final first = session.run(
      key: 'target',
      isCurrent: () => true,
      action: (_) async => throw StateError('fixture failure'),
    );
    await expectLater(first, throwsStateError);
    var retried = false;
    await session.run(
      key: 'target',
      isCurrent: () => true,
      action: (_) async {
        retried = true;
      },
    );
    expect(retried, isTrue);
  });
}

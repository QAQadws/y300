import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_recursive_thread_request_governor.dart';

void main() {
  test('default recursive cooldown is 700ms', () {
    expect(
      comicRecursiveThreadRequestCooldown,
      const Duration(milliseconds: 700),
    );
  });

  test('waits 700ms after the previous request completes', () async {
    var now = DateTime(2026);
    final waits = <Duration>[];
    final governor = DefaultComicRecursiveThreadRequestGovernor(
      nowProvider: () => now,
      delay: (duration) async {
        waits.add(duration);
        now = now.add(duration);
      },
    );

    expect(await governor.schedule(() async => 'first'), 'first');
    now = now.add(const Duration(milliseconds: 200));
    expect(await governor.schedule(() async => 'second'), 'second');

    expect(waits, const <Duration>[Duration(milliseconds: 500)]);
  });

  test('failed requests still consume the cooldown', () async {
    var now = DateTime(2026);
    final waits = <Duration>[];
    final governor = DefaultComicRecursiveThreadRequestGovernor(
      nowProvider: () => now,
      delay: (duration) async {
        waits.add(duration);
        now = now.add(duration);
      },
    );

    await expectLater(
      governor.schedule<void>(() async => throw StateError('failed')),
      throwsStateError,
    );
    await governor.schedule(() async => 'recovered');

    expect(waits, const <Duration>[Duration(milliseconds: 700)]);
  });

  test('serializes concurrent callers through one shared tail', () async {
    var now = DateTime(2026);
    final firstCompleter = Completer<void>();
    final order = <String>[];
    final governor = DefaultComicRecursiveThreadRequestGovernor(
      nowProvider: () => now,
      delay: (duration) async {
        now = now.add(duration);
        order.add('wait:${duration.inMilliseconds}');
      },
    );

    final first = governor.schedule(() async {
      order.add('first:start');
      await firstCompleter.future;
      order.add('first:end');
    });
    final second = governor.schedule(() async {
      order.add('second:start');
    });

    await Future<void>.delayed(Duration.zero);
    expect(order, <String>['first:start']);
    firstCompleter.complete();
    await Future.wait(<Future<void>>[first, second]);

    expect(order, <String>[
      'first:start',
      'first:end',
      'wait:700',
      'second:start',
    ]);
  });
}

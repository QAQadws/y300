import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/data/services/default_novel_sync_request_governor.dart';

void main() {
  test('default novel request cooldown is 700ms', () {
    expect(novelSyncRequestGovernorCooldown, const Duration(milliseconds: 700));
    expect(
      DefaultNovelSyncRequestGovernor().cooldown,
      const Duration(milliseconds: 700),
    );
  });

  test('provider reuses one governor inside a container', () {
    final firstContainer = ProviderContainer();
    final secondContainer = ProviderContainer();
    addTearDown(firstContainer.dispose);
    addTearDown(secondContainer.dispose);

    final first = firstContainer.read(novelSyncRequestGovernorProvider);
    expect(firstContainer.read(novelSyncRequestGovernorProvider), same(first));
    expect(
      secondContainer.read(novelSyncRequestGovernorProvider),
      isNot(same(first)),
    );
  });

  test('requests are strictly serial', () async {
    final events = <String>[];
    final firstGate = Completer<void>();
    final governor = DefaultNovelSyncRequestGovernor(cooldown: Duration.zero);

    final first = governor.schedule<void>(() async {
      events.add('first-start');
      await firstGate.future;
      events.add('first-end');
    });
    final second = governor.schedule<void>(() async {
      events.add('second-start');
      events.add('second-end');
    });

    await Future<void>.delayed(Duration.zero);
    expect(events, <String>['first-start']);
    firstGate.complete();
    await Future.wait(<Future<void>>[first, second]);

    expect(events, <String>[
      'first-start',
      'first-end',
      'second-start',
      'second-end',
    ]);
  });

  test('a later request waits only the remaining cooldown', () async {
    var now = DateTime(2026, 7, 13, 12);
    final waits = <Duration>[];
    final governor = DefaultNovelSyncRequestGovernor(
      cooldown: const Duration(milliseconds: 700),
      nowProvider: () => now,
      delay: (duration) async {
        waits.add(duration);
        now = now.add(duration);
      },
    );

    await governor.schedule<void>(() async {});
    now = now.add(const Duration(milliseconds: 250));
    await governor.schedule<void>(() async {});

    expect(waits, <Duration>[const Duration(milliseconds: 450)]);
  });

  test('a failed request does not poison the queue', () async {
    final governor = DefaultNovelSyncRequestGovernor(cooldown: Duration.zero);
    final events = <String>[];

    await expectLater(
      governor.schedule<void>(() async {
        events.add('failed');
        throw StateError('request failed');
      }),
      throwsStateError,
    );
    await governor.schedule<void>(() async {
      events.add('recovered');
    });

    expect(events, <String>['failed', 'recovered']);
  });
}

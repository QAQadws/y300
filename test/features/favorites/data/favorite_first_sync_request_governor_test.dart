import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/favorites/data/services/favorite_first_sync_request_governor.dart';

void main() {
  test('default favorite sync cooldown is 700ms (all sync modes)', () {
    expect(favoriteSyncGovernorCooldown, const Duration(milliseconds: 700));
    // Default governor (used by the provider) inherits the 700ms pacing.
    expect(
      DefaultFavoriteFirstSyncRequestGovernor().cooldown,
      const Duration(milliseconds: 700),
    );
  });

  test('governor runs requests strictly serially across kinds', () async {
    final governor = DefaultFavoriteFirstSyncRequestGovernor(
      cooldown: Duration.zero,
    );
    final events = <String>[];
    final firstGate = Completer<void>();

    final first = governor.run<void>(
      kind: FavoriteFirstSyncRequestKind.favoriteListPage,
      action: () async {
        events.add('first-start');
        await firstGate.future;
        events.add('first-end');
      },
    );
    final second = governor.run<void>(
      kind: FavoriteFirstSyncRequestKind.comicCatalogHtml,
      action: () async {
        events.add('second-start');
        events.add('second-end');
      },
    );

    await Future<void>.delayed(Duration.zero);
    expect(events, <String>['first-start']);

    firstGate.complete();
    await Future.wait(<Future<void>>[first, second]);

    expect(
      events,
      <String>['first-start', 'first-end', 'second-start', 'second-end'],
    );
  });

  test('governor waits cooldown after each governed request', () async {
    var now = DateTime(2026, 6, 14, 12, 0, 0);
    final waits = <Duration>[];
    final governor = DefaultFavoriteFirstSyncRequestGovernor(
      cooldown: const Duration(seconds: 1),
      nowProvider: () => now,
      delay: (duration) async {
        waits.add(duration);
        now = now.add(duration);
      },
    );

    await governor.run<void>(
      kind: FavoriteFirstSyncRequestKind.favoriteListPage,
      action: () async {},
    );
    now = now.add(const Duration(milliseconds: 250));
    await governor.run<void>(
      kind: FavoriteFirstSyncRequestKind.novelEpisodePage,
      action: () async {},
    );

    expect(waits, <Duration>[const Duration(milliseconds: 750)]);
  });
}

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/comic/data/providers/comic_episode_refresh_providers.dart';
import 'package:y300/features/comic/domain/repositories/comic_catalog_directory_reader.dart';
import 'package:y300/features/comic/domain/services/comic_episode_discovery_service.dart';
import 'package:y300/features/comic/domain/services/comic_incremental_episode_discovery.dart';

void main() {
  for (final keepMounted in [false, true]) {
    testWidgets(
      keepMounted
          ? 'comic discovery resumes a paused dependency graph without build errors'
          : 'comic discovery remounts a stale dependency graph without build errors',
      (tester) async {
        var repository = _UnusedThreadRepository();
        final overrides = [
          comicThreadDiscoveryRepositoryProvider.overrideWith(
            (ref) => repository,
          ),
          comicCatalogDirectoryReaderProvider.overrideWithValue(
            _UnusedCatalogReader(),
          ),
        ];
        ComicEpisodeDiscoveryService? fullDiscovery;
        ComicIncrementalEpisodeDiscovery? incrementalDiscovery;

        Widget page({required bool active}) => ProviderScope(
          overrides: overrides,
          child: TickerMode(
            enabled: active,
            child: !active && !keepMounted
                ? const SizedBox()
                : Consumer(
                    builder: (context, ref, child) {
                      fullDiscovery = ref.watch(
                        comicEpisodeDiscoveryServiceProvider,
                      );
                      incrementalDiscovery = ref.watch(
                        comicIncrementalEpisodeDiscoveryProvider,
                      );
                      return const SizedBox();
                    },
                  ),
          ),
        );

        await tester.pumpWidget(page(active: true));
        final container = ProviderScope.containerOf(
          tester.element(find.byType(Consumer)),
        );
        final initialFull = fullDiscovery;
        final initialIncremental = incrementalDiscovery;
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(page(active: false));
        // An account/source refresh can leave this shared, non-autoDispose
        // graph dirty while its page is absent or its route is offstage.
        repository = _UnusedThreadRepository();
        container.invalidate(comicThreadDiscoveryRepositoryProvider);
        await tester.pump();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(page(active: true));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(fullDiscovery, isNot(same(initialFull)));
        expect(incrementalDiscovery, isNot(same(initialIncremental)));

        // Checking only the return frame misses a partially registered refresh
        // task: later dependency changes must still reach the visible page.
        final returnedFull = fullDiscovery;
        final returnedIncremental = incrementalDiscovery;
        repository = _UnusedThreadRepository();
        container.invalidate(comicThreadDiscoveryRepositoryProvider);
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(fullDiscovery, isNot(same(returnedFull)));
        expect(incrementalDiscovery, isNot(same(returnedIncremental)));
      },
    );
  }
}

// Only provider composition is exercised; any remote call is a test failure.
final class _UnusedThreadRepository implements ComicThreadDiscoveryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected thread repository call: $invocation');
}

final class _UnusedCatalogReader implements ComicCatalogDirectoryReader {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected catalog reader call: $invocation');
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/startup/main_shell_startup_coordinator.dart';
import 'package:y300/app/startup/main_shell_startup_providers.dart';
import 'package:y300/app/storage/storage_accounting_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/data/services/cache_budget_scheduler.dart';
import 'package:y300/features/cache/data/services/cache_mutation_bus.dart';
import 'package:y300/features/cache/domain/models/cache_maintenance_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/comic/data/providers/comic_download_queue_providers.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/data/providers/comic_refresh_workflow_providers.dart';
import 'package:y300/features/comic/domain/repositories/comic_repository.dart';
import 'package:y300/features/comic/domain/services/comic_download_queue.dart';
import 'package:y300/features/library_shared/data/providers/library_cover_migration_providers.dart';
import 'package:y300/features/library_shared/data/providers/library_cover_thumbnail_providers.dart';
import 'package:y300/features/library_shared/data/providers/library_task_notification_providers.dart';
import 'package:y300/features/library_shared/data/services/library_cover_legacy_migrator.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_service.dart';
import 'package:y300/features/more/data/data_storage_settings_repository.dart';
import 'package:y300/features/more/presentation/data_storage_controller.dart';
import 'package:y300/features/storage/data/storage_providers.dart';
import 'package:y300/features/storage/domain/storage_root_access_gate.dart';
import 'package:y300/features/storage/domain/storage_root_migration.dart';

void main() {
  test(
    'cover recovery precedes custom adoption and detached maintenance',
    () async {
      final recovery = Completer<void>();
      final custom = Completer<void>();
      final source = Completer<void>();
      final fixture = _BackgroundFixture(
        recovery: () => recovery.future,
        custom: () => custom.future,
        source: () => source.future,
      );
      addTearDown(fixture.dispose);
      var ready = false;
      final operation = fixture.start(() => true).then((_) => ready = true);
      expect(fixture.events, ['recovery']);
      recovery.complete();
      await _flush();
      expect(fixture.events, ['recovery', 'custom']);
      expect(ready, isFalse);
      custom.complete();
      await operation;
      expect(ready, isTrue);
      // Download recovery remains detached behind the storage-gate await.
      await _flush();
      expect(fixture.events, [
        'recovery',
        'custom',
        'budget',
        'search',
        'gate',
        'source',
        'thumbnails',
        'download',
      ]);
      // Pending regenerable source-cover work does not hold shell readiness.
      source.complete();
      await _flush();
    },
  );

  for (final barrier in ['recovery', 'custom']) {
    test('dispose during $barrier suppresses remaining startup work', () async {
      final pending = Completer<void>();
      var active = true;
      final fixture = _BackgroundFixture(
        recovery: barrier == 'recovery' ? () => pending.future : null,
        custom: barrier == 'custom' ? () => pending.future : null,
      );
      addTearDown(fixture.dispose);
      final operation = fixture.start(() => active);
      await _flush();
      active = false;
      pending.complete();
      await operation;
      expect(
        fixture.events,
        barrier == 'recovery' ? ['recovery'] : ['recovery', 'custom'],
      );
    });
  }

  test('failed cover and independent tasks still complete readiness', () async {
    final fixture = _BackgroundFixture(
      recovery: () async => throw StateError('recovery fixture'),
      custom: () async => throw StateError('custom fixture'),
      source: () async => throw StateError('source fixture'),
    );
    addTearDown(fixture.dispose);
    await expectLater(fixture.start(() => true), completes);
    await _flush();
    expect(
      fixture.events,
      containsAll(['budget', 'search', 'source', 'thumbnails', 'download']),
    );
  });

  for (final disposeContainer in [false, true]) {
    test(
      'download waits for storage gate and ignores late ${disposeContainer ? 'container' : 'shell'} result',
      () async {
        final pending = Completer<StorageRootMigrationResult>();
        var active = true;
        final fixture = _BackgroundFixture(gate: pending.future);
        addTearDown(fixture.dispose);
        await fixture.start(() => active);
        expect(fixture.events, contains('gate'));
        expect(fixture.events, isNot(contains('download')));
        if (disposeContainer) {
          fixture.container.dispose();
        } else {
          active = false;
        }
        pending.complete(_readyStorage);
        await _flush();
        expect(fixture.events, isNot(contains('download')));
      },
    );
  }

  test(
    'coordinator starts once and isolates sync and async detached failures',
    () async {
      final pending = Completer<void>();
      final calls = <String>[];
      final coordinator = MainShellStartupCoordinator(
        prepareLibrary: (_) async {
          calls.add('prepare');
          await pending.future;
        },
        initializeNotifications: (_) {
          calls.add('notification');
          throw StateError('sync notification fixture');
        },
        warmups: [
          () async {
            calls.add('draft');
            throw StateError('draft fixture');
          },
          () {
            calls.add('session');
            throw StateError('sync session fixture');
          },
          () async {
            calls.add('image');
          },
        ],
      );
      final first = coordinator.start();
      expect(coordinator.start(), same(first));
      expect(calls, ['prepare', 'notification', 'draft', 'session', 'image']);
      pending.complete();
      await expectLater(first, completes);
      coordinator.dispose();
      expect(coordinator.isActive, isFalse);
      await coordinator.start();
      expect(calls, hasLength(5));
    },
  );

  test(
    'factory creates separate shell tokens and container invalidates both',
    () async {
      final tokens = <bool Function()>[];
      var warmups = 0;
      final container = ProviderContainer(
        overrides: [
          mainShellBackgroundTaskStarterProvider.overrideWithValue((
            isActive,
          ) async {
            tokens.add(isActive);
          }),
          mainShellNotificationInitializerProvider.overrideWithValue(
            (_) async {},
          ),
          mainShellReplyDraftAttachmentMaintenanceStarterProvider
              .overrideWithValue(() async {
                warmups++;
              }),
          mainShellYamiboSessionWarmupProvider.overrideWithValue(() async {}),
          mainShellImageCacheWarmupProvider.overrideWithValue(() async {}),
        ],
      );
      final factory = container.read(
        mainShellStartupCoordinatorFactoryProvider,
      );
      final first = factory();
      await first.start();
      first.dispose();
      final second = factory();
      await second.start();
      expect(tokens.map((token) => token()), [false, true]);
      expect(warmups, 2);
      container.dispose();
      expect(tokens.map((token) => token()), [false, false]);
    },
  );

  for (final disposeContainer in [false, true]) {
    test(
      'notification permission is suppressed after late ${disposeContainer ? 'container' : 'shell'} disposal',
      () async {
        final pending = Completer<void>();
        final service = _Notifications(initialize: () => pending.future);
        addTearDown(service.dispose);
        final container = ProviderContainer(
          overrides: [
            libraryTaskNotificationServiceProvider.overrideWithValue(service),
          ],
        );
        addTearDown(container.dispose);
        var active = true;
        final operation = container.read(
          mainShellNotificationInitializerProvider,
        )(() => active);
        expect(service.initializeCalls, 1);
        if (disposeContainer) {
          container.dispose();
        } else {
          active = false;
        }
        pending.complete();
        await operation;
        expect(service.permissionCalls, 0);
      },
    );
  }

  for (final failInitialization in [false, true]) {
    test(
      'notification ${failInitialization ? 'initialization' : 'permission'} failure is best effort',
      () async {
        final service = _Notifications(
          initialize: () async {
            if (failInitialization) throw StateError('channel fixture');
          },
          failPermission: !failInitialization,
        );
        addTearDown(service.dispose);
        final container = ProviderContainer(
          overrides: [
            libraryTaskNotificationServiceProvider.overrideWithValue(service),
          ],
        );
        addTearDown(container.dispose);
        await expectLater(
          container.read(mainShellNotificationInitializerProvider)(() => true),
          completes,
        );
        expect(service.permissionCalls, failInitialization ? 0 : 1);
      },
    );
  }

  testWidgets(
    'budget scheduler remains shared across shells and stops with container',
    (tester) async {
      final bus = CacheMutationBus();
      addTearDown(bus.dispose);
      final settings = _Settings(() async => 4321);
      final maintenance = _Maintenance();
      final container = ProviderContainer(
        overrides: [
          cacheMutationBusProvider.overrideWithValue(bus),
          dataStorageSettingsRepositoryProvider.overrideWithValue(settings),
          cacheMaintenanceServiceProvider.overrideWithValue(maintenance),
        ],
      );
      final scheduler = container.read(mainShellCacheBudgetSchedulerProvider);
      final first = _budgetCoordinator(scheduler);
      await first.start();
      await tester.pump();
      first.dispose();
      final second = _budgetCoordinator(
        container.read(mainShellCacheBudgetSchedulerProvider),
      );
      await second.start();
      await tester.pump();
      expect(
        container.read(mainShellCacheBudgetSchedulerProvider),
        same(scheduler),
      );
      expect(maintenance.budgets, [4321, 4321]);
      bus.reportMutation(CacheNamespace.image);
      await tester.pump(const Duration(seconds: 2));
      expect(maintenance.budgets, [4321, 4321, 4321]);
      second.dispose();
      // Shell disposal must not tear down the shared mutation subscription.
      bus.reportMutation(CacheNamespace.document);
      await tester.pump(const Duration(seconds: 2));
      expect(maintenance.budgets, hasLength(4));
      container.dispose();
      bus.reportMutation(CacheNamespace.snapshot);
      await tester.pump(const Duration(seconds: 2));
      await scheduler.start();
      expect(maintenance.budgets, hasLength(4));
    },
  );

  test(
    'budget settings finishing after disposal cannot start pruning',
    () async {
      final pending = Completer<int>();
      final bus = CacheMutationBus();
      addTearDown(bus.dispose);
      final maintenance = _Maintenance();
      final container = ProviderContainer(
        overrides: [
          cacheMutationBusProvider.overrideWithValue(bus),
          dataStorageSettingsRepositoryProvider.overrideWithValue(
            _Settings(() => pending.future),
          ),
          cacheMaintenanceServiceProvider.overrideWithValue(maintenance),
        ],
      );
      final operation = container
          .read(mainShellCacheBudgetSchedulerProvider)
          .start();
      container.dispose();
      pending.complete(1234);
      await operation;
      expect(maintenance.budgets, isEmpty);
    },
  );
}

MainShellStartupCoordinator _budgetCoordinator(
  CacheBudgetScheduler scheduler,
) => MainShellStartupCoordinator(
  prepareLibrary: (isActive) => runMainShellBackgroundTasks(
    isActive: isActive,
    migrateCustomCovers: () async {},
    maintenance: [scheduler.start],
  ),
  initializeNotifications: (_) async {},
  warmups: [],
);

Future<void> _flush() => Future<void>.delayed(Duration.zero);

const _readyStorage = StorageRootMigrationResult(
  disposition: StorageRootMigrationDisposition.notRequired,
  status: StorageRootMigrationStatus(
    phase: StorageRootMigrationPhase.completed,
    blocksStorageAccess: false,
  ),
);

class _BackgroundFixture {
  _BackgroundFixture({
    Future<void> Function()? recovery,
    Future<void> Function()? custom,
    Future<void> Function()? source,
    Future<StorageRootMigrationResult>? gate,
  }) {
    scheduler = CacheBudgetScheduler(
      source: bus,
      enforce: () async {
        events.add('budget');
      },
    );
    container = ProviderContainer(
      overrides: [
        libraryCoverLegacyMigratorProvider.overrideWithValue(
          _CoverMigrator(
            custom: () async {
              events.add('custom');
              await custom?.call();
            },
            source: () async {
              events.add('source');
              await source?.call();
            },
          ),
        ),
        comicCoverMergeRecoveryProvider.overrideWithValue(
          _Recovery(() async {
            events.add('recovery');
            await recovery?.call();
          }),
        ),
        mainShellCacheBudgetSchedulerProvider.overrideWithValue(scheduler),
        comicSearchRefreshQueueServiceProvider.overrideWith((ref) {
          events.add('search');
          throw StateError('isolated search construction fixture');
        }),
        storageRootAccessGateProvider.overrideWithValue(
          _StorageGate(() {
            events.add('gate');
            return gate ?? Future.value(_readyStorage);
          }),
        ),
        comicDownloadQueueProvider.overrideWithValue(
          _DownloadQueue(() async {
            events.add('download');
          }),
        ),
        libraryCoverLegacyThumbnailCleanupProvider.overrideWith((ref) {
          events.add('thumbnails');
          throw StateError('isolated cleanup construction fixture');
        }),
      ],
    );
  }
  final events = <String>[];
  final bus = CacheMutationBus();
  late final CacheBudgetScheduler scheduler;
  late final ProviderContainer container;
  Future<void> start(bool Function() isActive) =>
      container.read(mainShellBackgroundTaskStarterProvider)(isActive);
  Future<void> dispose() async {
    container.dispose();
    await scheduler.dispose();
    await bus.dispose();
  }
}

class _CoverMigrator implements LibraryCoverLegacyMigrator {
  _CoverMigrator({required this.custom, required this.source});
  final Future<void> Function() custom;
  final Future<void> Function() source;
  @override
  Future<void> migrateCustomAssets() => custom();
  @override
  Future<void> migrateSourceAssets({int batchSize = 32}) => source();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Recovery implements ComicCoverMergeRecovery {
  _Recovery(this.recover);
  final Future<void> Function() recover;
  @override
  Future<void> recoverPendingCoverMerges() => recover();
}

class _StorageGate implements StorageRootAccessGate {
  _StorageGate(this.ready);
  final Future<StorageRootMigrationResult> Function() ready;
  @override
  Future<StorageRootMigrationResult> ensureReady() => ready();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DownloadQueue implements ComicDownloadQueue {
  _DownloadQueue(this.startQueue);
  final Future<void> Function() startQueue;
  @override
  Future<void> start() => startQueue();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Notifications implements LibraryTaskNotificationService {
  _Notifications({
    required Future<void> Function() initialize,
    this.failPermission = false,
  }) : _initialize = initialize;
  final Future<void> Function() _initialize;
  final bool failPermission;
  final state = ValueNotifier<LibraryTaskNotificationPermissionState?>(null);
  int initializeCalls = 0;
  int permissionCalls = 0;
  @override
  ValueListenable<LibraryTaskNotificationPermissionState?>
  get permissionState => state;
  @override
  Future<void> initialize() async {
    initializeCalls++;
    await _initialize();
  }

  @override
  Future<LibraryTaskNotificationPermissionState> ensurePermission() async {
    permissionCalls++;
    if (failPermission) throw StateError('permission fixture');
    return LibraryTaskNotificationPermissionState.denied;
  }

  @override
  Future<void> clear(LibraryTaskNotificationKey key) async {}
  @override
  Future<void> showOrUpdate(LibraryTaskNotification notification) async {}
  void dispose() => state.dispose();
}

class _Settings implements DataStorageSettingsRepository {
  _Settings(this.loadBudget);
  final Future<int> Function() loadBudget;
  @override
  Future<int> getCacheMaxBytes() => loadBudget();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Maintenance implements CacheMaintenanceService {
  final budgets = <int>[];
  @override
  Future<CachePruneResult> prune(CachePruneRequest request) async {
    budgets.add(request.maxCacheBytes);
    return const CachePruneResult(
      deletedDocuments: 0,
      deletedSnapshots: 0,
      deletedProtectedCoverRecords: 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

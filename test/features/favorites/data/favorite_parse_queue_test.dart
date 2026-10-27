import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/auth/application/verified_session_owner.dart';
import 'package:y300/features/favorites/data/providers/favorite_directory_providers.dart';
import 'package:y300/features/favorites/data/providers/favorite_parse_providers.dart';
import 'package:y300/features/favorites/data/providers/favorite_providers.dart';
import 'package:y300/features/favorites/data/repositories/favorite_parse_job_repository.dart';
import 'package:y300/features/favorites/data/repositories/local_favorite_repository.dart';
import 'package:y300/features/favorites/data/services/default_favorite_sync_request_governor.dart';
import 'package:y300/features/favorites/data/services/favorite_content_ingest_registry.dart';
import 'package:y300/features/favorites/data/services/favorite_detail_context_loader.dart';
import 'package:y300/features/favorites/data/services/favorite_link_service_impl.dart';
import 'package:y300/features/favorites/data/services/favorite_parse_coordinator.dart';
import 'package:y300/features/favorites/data/services/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/services/library_post_ingest_task_runner.dart';
import 'package:y300/features/favorites/data/use_cases/unfavorite_use_cases_impl.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/favorites/domain/services/favorite_parse_service.dart';
import 'package:y300/features/favorites/presentation/adapters/favorite_shelf_adapter.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_selection_action_adapter.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/work_purge_service.dart';
import 'package:y300/features/novel/data/repositories/sqflite_novel_source_metadata_repository.dart';
import 'package:y300/features/novel/data/services/novel_favorite_ingest_service.dart';
import 'package:y300/features/novel/data/services/novel_source_metadata_ingest_service.dart';
import 'package:y300/features/novel/domain/services/novel_source_metadata_parser.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';
import 'package:y300/features/thread/data/providers/thread_favorite_providers.dart';
import 'package:y300/features/thread/domain/models/thread_favorite_models.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

import '../../../support/favorite_command_test_support.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory directory;
  late String path;
  late Database db;
  late SqfliteLocalFavoriteRepository local;
  late FavoriteParseJobRepository jobs;
  late LibraryShelfRefreshBus bus;
  final coordinators = <DefaultFavoriteParseCoordinator>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('favorite-parse-queue-');
    path = p.join(directory.path, 'queue.db');
    db = await AppDatabase.open(databaseName: path);
    local = SqfliteLocalFavoriteRepository(Future.value(db));
    jobs = FavoriteParseJobRepository(Future.value(db));
    bus = LibraryShelfRefreshBus();
  });
  tearDown(() async {
    for (final service in coordinators) {
      service.close();
      await service.settled;
    }
    coordinators.clear();
    bus.dispose();
    await db.close();
    await deleteDatabase(path);
    await directory.delete();
  });

  NetworkFavoriteSyncService executor(
    _Source source, {
    _Directory? remote,
    Object? Function()? readOwner,
  }) {
    const forum = ForumFavoriteContentIngestHandler();
    return NetworkFavoriteSyncService(
      remoteRepository: remote ?? _Directory(),
      localRepository: local,
      detailContextLoader: DefaultFavoriteDetailContextLoader(
        threadRepository: source,
        loadTagLookup: () async => ForumTagLookup(const []),
        classifier: const ThreadContentClassifier(),
      ),
      contentIngestRegistry: DefaultFavoriteContentIngestRegistry(
        comicHandler: forum,
        forumHandler: forum,
        novelHandler: NovelFavoriteContentIngestHandler(
          ingestService: RepositoryNovelFavoriteIngestService(
            metadataIngestService: DefaultNovelSourceMetadataIngestService(
              parser: const DefaultNovelSourceMetadataParser(),
              repository: SqfliteNovelSourceMetadataRepository(
                Future.value(db),
              ),
            ),
            removeFromShelf: ({required workId}) async {},
          ),
        ),
      ),
      postIngestTaskRunner: DefaultLibraryPostIngestTaskRunner(
        shelfRefreshBus: bus,
      ),
      shelfRefreshBus: bus,
      governorFactory: () =>
          DefaultFavoriteSyncRequestGovernor(cooldown: Duration.zero),
      readOwner: readOwner,
    );
  }

  DefaultFavoriteParseCoordinator coordinator(
    FavoriteThreadParseExecutor parser, {
    String account = '123',
    bool Function()? valid,
  }) {
    final service = DefaultFavoriteParseCoordinator(
      accountId: account,
      repository: jobs,
      executor: parser,
      isOwnerCurrent: valid ?? () => true,
    );
    coordinators.add(service);
    return service;
  }

  ThreadFavoriteReceipt confirmed() => const ThreadFavoriteReceipt(
    tid: '200',
    targetState: FavoriteTargetState.favorited,
    disposition: FavoriteMutationDisposition.changed,
    remoteFavoriteId: '88',
  );
  Future<void> seed() => local.upsertRemoteThreads(const [
    FavoriteThreadCacheUpsert(tid: '200', title: 'Novel', replyCount: 1),
  ]);
  Future<void> expectNovel() async {
    final record = await local.getActiveThreadByTid('200');
    expect(record?.contentKind, ThreadContentKind.novel);
    expect(record?.workId, 'novel:55:200');
    expect(record?.detailState, FavoriteDetailState.resolved);
    expect(await db.query(AppDatabase.worksTable), hasLength(1));
  }

  test('startup recovery provider resumes durable jobs for the verified account only', () async {
    await jobs.enqueue(
      '123',
      const FavoriteParseTarget(tid: '200', confirmed: true, title: 'Novel'),
      isCurrent: () => true,
    );
    await jobs.enqueue(
      '456',
      const FavoriteParseTarget(tid: '300', confirmed: true, title: 'Other'),
      isCurrent: () => true,
    );
    final source = _Source(() async {});
    final remote = _Directory();
    final container = ProviderContainer(
      overrides: [
        verifiedSessionOwnerProvider.overrideWithValue((
          uid: '123',
          revision: 1,
        )),
        favoriteParseJobRepositoryProvider.overrideWithValue(jobs),
        favoriteSyncServiceProvider.overrideWithValue(
          executor(source, remote: remote),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(favoriteParseRecoveryProvider);
    await container.read(favoriteParseServiceProvider).resume();
    expect(source.calls, 1);
    expect(remote.calls, 0);
    await expectNovel();
    final other = await db.query(
      AppDatabase.favoriteParseJobsTable,
      where: 'account_id = ?',
      whereArgs: ['456'],
    );
    expect(other.single['state'], 'queued');
  });

  test('production favorite action returns after durable acceptance without a directory read', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final source = _Source(() async {
      started.complete();
      await gate.future;
    });
    final remote = _Directory();
    final service = coordinator(executor(source, remote: remote));
    final command = FakeFavoriteThreadCommand(
      handler: (_) async => DataCommandApplied(confirmed()),
    );
    final container = ProviderContainer(
      overrides: [
        verifiedSessionOwnerProvider.overrideWithValue((
          uid: '123',
          revision: 1,
        )),
        favoriteParseServiceProvider.overrideWithValue(service),
        favoriteThreadCommandProvider.overrideWithValue(command),
        libraryShelfRefreshBusProvider.overrideWithValue(bus),
      ],
    );
    addTearDown(container.dispose);
    final result = await container
        .read(threadFavoriteActionServiceProvider)
        .favoriteThread(tid: '200', title: 'Novel');
    expect(
      (result as DataCommandApplied<ThreadFavoriteActionResult>)
          .receipt
          .parseQueued,
      isTrue,
    );
    expect(command.requests, hasLength(1));
    expect(
      (await db.query(AppDatabase.favoriteParseJobsTable)).single['favid'],
      '88',
    );
    await started.future;
    expect(await local.getSyncSnapshot(), isNull);
    expect(remote.calls, 0);
    gate.complete();
    await service.settled;
    await expectNovel();
    expect((await local.getActiveThreadByTid('200'))?.remoteFavoriteId, '88');
    expect(await local.getSyncSnapshot(), isNull);
  });

  test(
    'manual selection parses with no baseline and coalesces a running target',
    () async {
      await seed();
      await local.updateThreadDetailMeta(
        tid: '200',
        fid: '1',
        typeid: '',
        tagName: null,
        contentKind: ThreadContentKind.forum,
        workId: 'thread:200',
      );
      final category = await local.createCategory(name: 'Custom');
      await local.moveThreadToCategory(tid: '200', toCategoryId: category);
      final started = Completer<void>(), gate = Completer<void>();
      final source = _Source(() async {
        started.complete();
        await gate.future;
      });
      final parser = executor(source);
      final service = coordinator(parser);
      final adapter = FavoriteShelfAdapter(
        local,
        syncService: parser,
        parseServiceResolver: () => service,
      );
      expect(
        adapter.selectionActions.map((e) => e.id),
        contains(SelectionActionIds.parse),
      );
      final result = await adapter.runSelectionAction(
        const SelectionActionExecutionRequest(
          actionId: SelectionActionIds.parse,
          workIds: {'favorite:200'},
          activeCategoryId: favoriteDefaultCategoryId,
        ),
      );
      expect(result.enqueuedCount, 1);
      await started.future;
      final duplicate = await service.requestThreads({'200'});
      expect(duplicate.existing, 1);
      gate.complete();
      await service.settled;
      expect(source.calls, 1);
      await expectNovel();
      expect(
        (await local.getActiveThreadByTid('200'))?.customCategoryId,
        category,
      );
      expect(await local.getSyncSnapshot(), isNull);
    },
  );

  test('parse failure remains retryable and does not change a valid directory baseline', () async {
    await seed();
    await local.finishSync(mode: FavoriteSyncMode.fullDiff, remoteCount: 1);
    final baseline = await local.getSyncSnapshot();
    final source = _Source(() async {})..fail = true;
    final service = coordinator(executor(source));
    await service.requestThreads({'200'});
    await service.settled;
    expect(
      (await db.query(AppDatabase.favoriteParseJobsTable)).single['state'],
      'failed',
    );
    expect(
      (await local.getActiveThreadByTid('200'))?.detailState,
      FavoriteDetailState.pending,
    );
    expect(
      (await local.getSyncSnapshot())?.lastSyncedAt,
      baseline?.lastSyncedAt,
    );
    expect((await local.getSyncSnapshot())?.status, 'ok');
    source.fail = false;
    await service.requestThreads({'200'});
    await service.settled;
    await expectNovel();
    expect(source.calls, 2);
  });

  test(
    'a failed recovery future does not permanently reject later admissions',
    () async {
      await seed();
      jobs = _RecoveryFailsOnce(Future.value(db));
      final source = _Source(() async {});
      final service = coordinator(executor(source));
      await expectLater(service.requestThreads({'200'}), throwsStateError);
      expect((await service.requestThreads({'200'})).enqueued, 1);
      await service.settled;
      await expectNovel();
      expect(source.calls, 1);
    },
  );

  test(
    'reopening the disk database resumes a running job without re-favoriting',
    () async {
      final started = Completer<void>(), gate = Completer<void>();
      final old = coordinator(
        executor(
          _Source(() async {
            started.complete();
            await gate.future;
          }),
        ),
      );
      await old.requestConfirmed(confirmed(), title: 'Novel');
      await started.future;
      old.close();
      gate.complete();
      await old.settled;
      expect(
        (await db.query(AppDatabase.favoriteParseJobsTable)).single['state'],
        'running',
      );
      await db.close();
      db = await AppDatabase.open(databaseName: path);
      local = SqfliteLocalFavoriteRepository(Future.value(db));
      jobs = FavoriteParseJobRepository(Future.value(db));
      final source = _Source(() async {});
      final next = coordinator(executor(source));
      await next.resume();
      expect(source.calls, 1);
      await expectNovel();
      expect(
        (await db.query(AppDatabase.favoriteParseJobsTable)).single['state'],
        'completed',
      );
    },
  );

  test('confirmed unfavorite settles an in-flight parse and removes its final work binding', () async {
    final started = Completer<void>(), gate = Completer<void>();
    final service = coordinator(
      executor(
        _Source(() async {
          started.complete();
          await gate.future;
        }),
      ),
    );
    await service.requestConfirmed(confirmed(), title: 'Novel');
    await started.future;
    final retiring = Completer<void>();
    final purge = _DatabasePurge(db);
    final unfavorite = DefaultUnfavoriteThreadUseCase(
      favoriteThreadCommand: FakeFavoriteThreadCommand(),
      favoriteLinkService: DefaultFavoriteLinkService(repository: local),
      localFavoriteRepository: local,
      workPurgeService: purge,
      shelfRefreshBus: bus,
      cancelParseJobs: (tids) {
        final pending = service.cancelThreads(tids);
        retiring.complete();
        return pending;
      },
    );
    final result = unfavorite.call('200');
    await retiring.future;
    gate.complete();
    expect((await result).succeededTids, ['200']);
    await service.settled;
    expect(await local.getActiveThreadByTid('200'), isNull);
    expect(await db.query(AppDatabase.worksTable), isEmpty);
    expect(purge.workIds, ['novel:55:200']);
    expect(
      (await db.query(AppDatabase.favoriteParseJobsTable)).single['state'],
      'cancelled',
    );
  });

  test('owner invalidation prevents late classification and another account cannot recover the job', () async {
    var valid = true;
    final started = Completer<void>(), gate = Completer<void>();
    final service = coordinator(
      executor(
        _Source(() async {
          started.complete();
          await gate.future;
        }),
      ),
      valid: () => valid,
    );
    await service.requestConfirmed(confirmed(), title: 'Novel');
    await started.future;
    valid = false;
    gate.complete();
    await service.settled;
    expect(await db.query(AppDatabase.worksTable), isEmpty);
    final source = _Source(() async {});
    await coordinator(executor(source), account: '456').resume();
    expect(source.calls, 0);
  });

  for (final ordinary in [false, true]) {
    test(
      'manual queue jumps ahead of the cached auto batch (ordinary=$ordinary)',
      () async {
        await local.upsertRemoteThreads([
          for (final tid in ['100', '200', '300'])
            FavoriteThreadCacheUpsert(tid: tid, title: 'Novel', replyCount: 1),
        ]);
        if (ordinary) {
          await local.finishSync(
            mode: FavoriteSyncMode.fullDiff,
            remoteCount: 3,
          );
        }
        final started = Completer<void>(),
            gate = Completer<void>(),
            submitted = Completer<void>();
        final source = _Source(() async {})
          ..beforeTid = (tid) async {
            if (tid == '100') {
              started.complete();
              await gate.future;
            }
          };
        final remote = _Directory(tids: const ['100', '200', '300']);
        final parser = executor(source, remote: remote);
        final sync = parser.sync();
        await started.future;
        final service = coordinator(_ObservedExecutor(parser, submitted));
        await service.requestThreads({'300'});
        await submitted.future;
        gate.complete();
        final result = await sync;
        await service.settled;
        expect(source.tids, ['100', '300', '200']);
        expect(await db.query(AppDatabase.worksTable), hasLength(3));
        expect(remote.calls, 1);
        expect(result.needsReconciliation, isFalse);
        expect(
          (await local.getActiveThreadByTid('300'))?.detailState,
          FavoriteDetailState.resolved,
        );
      },
    );
  }

  test('a manual request joins a currently reading novel without a second detail read', () async {
    final started = Completer<void>(),
        gate = Completer<void>(),
        submitted = Completer<void>();
    final source = _Source(() async {})
      ..beforeTid = (tid) async {
        if (tid == '200') {
          started.complete();
          await gate.future;
        }
      };
    final parser = executor(source, remote: _Directory(tids: const ['200']));
    final sync = parser.sync();
    await started.future;
    final service = coordinator(_ObservedExecutor(parser, submitted));
    await service.requestThreads({'200'});
    await submitted.future;
    gate.complete();
    await sync;
    await service.settled;
    expect(source.tids, ['200']);
    await expectNovel();
  });

  test('a confirmed add during automatic parsing survives the older directory and leaves reconciliation pending', () async {
    final started = Completer<void>(),
        gate = Completer<void>(),
        submitted = Completer<void>();
    final source = _Source(() async {})
      ..beforeTid = (tid) async {
        if (tid == '100') {
          started.complete();
          await gate.future;
        }
      };
    final parser = executor(
      source,
      remote: _Directory(tids: const ['100', '300']),
    );
    final sync = parser.sync();
    await started.future;
    final service = coordinator(_ObservedExecutor(parser, submitted));
    await service.requestConfirmed(confirmed(), title: 'Novel');
    await submitted.future;
    gate.complete();
    final result = await sync;
    await service.settled;
    expect(source.tids, ['100', '200', '300']);
    expect((await local.getActiveThreadByTid('200'))?.workId, 'novel:55:200');
    expect(result.needsReconciliation, isTrue);
    final baseline = await local.getSyncSnapshot();
    expect(baseline?.status, 'failed');
    expect(baseline?.lastFullSyncedAt, isNull);
  });

  test('an applied unfavorite retires an unstarted automatic target', () async {
    final started = Completer<void>(),
        gate = Completer<void>(),
        retiring = Completer<void>();
    final source = _Source(() async {})
      ..beforeTid = (tid) async {
        if (tid == '100') {
          started.complete();
          await gate.future;
        }
      };
    final parser = executor(
      source,
      remote: _Directory(tids: const ['100', '200']),
    );
    final sync = parser.sync();
    await started.future;
    final service = coordinator(parser);
    final unfavorite = DefaultUnfavoriteThreadUseCase(
      favoriteThreadCommand: FakeFavoriteThreadCommand(),
      favoriteLinkService: DefaultFavoriteLinkService(repository: local),
      localFavoriteRepository: local,
      workPurgeService: _DatabasePurge(db),
      shelfRefreshBus: bus,
      cancelParseJobs: (tids) {
        final future = service.cancelThreads(tids);
        retiring.complete();
        return future;
      },
    );
    final removal = unfavorite.call('200');
    await retiring.future;
    gate.complete();
    expect((await removal).succeededTids, ['200']);
    expect((await sync).needsReconciliation, isTrue);
    expect(source.tids, ['100']);
    expect(await local.getActiveThreadByTid('200'), isNull);
  });

  test('a newer confirmed favorite supersedes an older unfavorite waiting for the slot', () async {
    final started = Completer<void>(),
        gate = Completer<void>(),
        retiring = Completer<void>(),
        submitted = Completer<void>();
    final source = _Source(() async {})
      ..beforeTid = (tid) async {
        if (tid == '100') {
          started.complete();
          await gate.future;
        }
      };
    final parser = executor(
      source,
      remote: _Directory(tids: const ['100', '200']),
    );
    final sync = parser.sync();
    await started.future;
    final service = coordinator(_ObservedExecutor(parser, submitted));
    final unfavorite = DefaultUnfavoriteThreadUseCase(
      favoriteThreadCommand: FakeFavoriteThreadCommand(),
      favoriteLinkService: DefaultFavoriteLinkService(repository: local),
      localFavoriteRepository: local,
      workPurgeService: _DatabasePurge(db),
      shelfRefreshBus: bus,
      cancelParseJobs: (tids) {
        final future = service.cancelThreads(tids);
        retiring.complete();
        return future;
      },
    );
    final removal = unfavorite.call('200');
    await retiring.future;
    await service.requestConfirmed(confirmed(), title: 'Novel');
    await submitted.future;
    gate.complete();
    expect((await removal).purgedWorkIds, isEmpty);
    await sync;
    await service.settled;
    expect((await local.getActiveThreadByTid('200'))?.remoteFavoriteId, '88');
    expect(source.tids.where((tid) => tid == '200'), hasLength(1));
  });

  test(
    'automatic parsing rejects late results after the verified owner changes',
    () async {
      Object owner = (uid: '123', revision: 1);
      final started = Completer<void>(), gate = Completer<void>();
      final parser = executor(
        _Source(() async {
          started.complete();
          await gate.future;
        }),
        remote: _Directory(tids: const ['200']),
        readOwner: () => owner,
      );
      final sync = expectLater(parser.sync(), throwsA(isA<Exception>()));
      await started.future;
      owner = (uid: '456', revision: 2);
      gate.complete();
      await sync;
      expect(await db.query(AppDatabase.worksTable), isEmpty);
      expect(await local.getSyncSnapshot(), isNull);
    },
  );

  test(
    'a cached automatic record with a dangling work binding is reloaded',
    () async {
      final started = Completer<void>(), gate = Completer<void>();
      final source = _Source(() async {})
        ..beforeTid = (tid) async {
          if (tid == '100') {
            started.complete();
            await gate.future;
          }
        };
      final parser = executor(
        source,
        remote: _Directory(tids: const ['100', '200']),
      );
      final sync = parser.sync();
      await started.future;
      await local.updateThreadDetailMeta(
        tid: '200',
        fid: '55',
        typeid: '295',
        tagName: null,
        contentKind: ThreadContentKind.novel,
        workId: 'novel:55:missing',
      );
      gate.complete();
      await sync;
      expect(source.tids, ['100', '200']);
      expect((await local.getActiveThreadByTid('200'))?.workId, 'novel:55:200');
    },
  );

  test('a stronger persisted request survives an obsolete acknowledgement and reopening', () async {
    await seed();
    await jobs.enqueue(
      '123',
      const FavoriteParseTarget(tid: '200'),
      isCurrent: () => true,
    );
    final obsolete = (await jobs.claim('123'))!;
    await jobs.enqueue(
      '123',
      const FavoriteParseTarget(
        tid: '200',
        confirmed: true,
        remoteFavoriteId: '88',
        title: 'Novel',
      ),
      isCurrent: () => true,
    );
    await jobs.finish(obsolete);
    final pending = (await db.query(AppDatabase.favoriteParseJobsTable)).single;
    expect(pending['state'], 'queued');
    expect(pending['revision'], greaterThan(obsolete.revision));
    await db.close();
    db = await AppDatabase.open(databaseName: path);
    local = SqfliteLocalFavoriteRepository(Future.value(db));
    jobs = FavoriteParseJobRepository(Future.value(db));
    final source = _Source(() async {});
    await coordinator(executor(source)).resume();
    expect(source.calls, 1);
    await expectNovel();
    expect((await local.getActiveThreadByTid('200'))?.remoteFavoriteId, '88');
  });

  test(
    'an older directory response cannot overwrite a newly unfavorited row',
    () async {
      await local.upsertRemoteThreads(const [
        FavoriteThreadCacheUpsert(tid: '200', title: 'Original', replyCount: 1),
      ]);
      final started = Completer<void>(),
          gate = Completer<void>(),
          retiring = Completer<void>();
      final source = _Source(() async {});
      final parser = executor(
        source,
        remote: _Directory(
          tids: const ['200'],
          beforeRead: () async {
            started.complete();
            await gate.future;
          },
        ),
      );
      final sync = parser.sync();
      await started.future;
      final service = coordinator(parser);
      final unfavorite = DefaultUnfavoriteThreadUseCase(
        favoriteThreadCommand: FakeFavoriteThreadCommand(),
        favoriteLinkService: DefaultFavoriteLinkService(repository: local),
        localFavoriteRepository: local,
        workPurgeService: _DatabasePurge(db),
        shelfRefreshBus: bus,
        cancelParseJobs: (tids) {
          final future = service.cancelThreads(tids);
          retiring.complete();
          return future;
        },
      );
      final removal = unfavorite.call('200');
      await retiring.future;
      gate.complete();
      await removal;
      expect((await sync).needsReconciliation, isTrue);
      expect(source.calls, 0);
      expect(await local.getActiveThreadByTid('200'), isNull);
      expect(
        (await db.query(AppDatabase.favoriteThreadsTable)).single['title'],
        'Original',
      );
    },
  );

  test(
    'a delayed claimed confirmation cannot replay over a newer cancellation',
    () async {
      final started = Completer<void>(),
          gate = Completer<void>(),
          claimed = Completer<void>(),
          claimGate = Completer<void>(),
          retiring = Completer<void>(),
          submitted = Completer<void>();
      final source = _Source(() async {})
        ..beforeTid = (tid) async {
          if (tid == '100') {
            started.complete();
            await gate.future;
          }
        };
      final parser = executor(
        source,
        remote: _Directory(tids: const ['100', '200']),
      );
      final sync = parser.sync();
      await started.future;
      jobs = _DelayedEligibility(Future.value(db), claimed, claimGate);
      final service = coordinator(_ObservedExecutor(parser, submitted));
      await service.requestConfirmed(confirmed(), title: 'Novel');
      await claimed.future;
      final unfavorite = DefaultUnfavoriteThreadUseCase(
        favoriteThreadCommand: FakeFavoriteThreadCommand(),
        favoriteLinkService: DefaultFavoriteLinkService(repository: local),
        localFavoriteRepository: local,
        workPurgeService: _DatabasePurge(db),
        shelfRefreshBus: bus,
        cancelParseJobs: (tids) {
          final future = service.cancelThreads(tids);
          retiring.complete();
          return future;
        },
      );
      final removal = unfavorite.call('200');
      await retiring.future;
      claimGate.complete();
      await submitted.future;
      gate.complete();
      await removal;
      await sync;
      await service.settled;
      expect(source.tids, ['100']);
      expect(await local.getActiveThreadByTid('200'), isNull);
    },
  );

  test('admission stays fast behind an entire sync and does not start another directory scan', () async {
    final started = Completer<void>(), gate = Completer<void>();
    final remote = _Directory(
      beforeRead: () async {
        started.complete();
        await gate.future;
      },
    );
    final parser = executor(_Source(() async {}), remote: remote);
    final sync = expectLater(parser.sync(), throwsStateError);
    await started.future;
    final service = coordinator(parser);
    await service.requestConfirmed(confirmed(), title: 'Novel');
    expect(await db.query(AppDatabase.favoriteThreadsTable), isEmpty);
    expect(await db.query(AppDatabase.favoriteParseJobsTable), hasLength(1));
    gate.complete();
    await sync;
    await service.settled;
    await expectNovel();
    expect(remote.calls, 1);
    expect((await local.getSyncSnapshot())?.status, 'failed');
  });
}

class _Source implements ThreadRepository {
  _Source(this.beforeRead);
  final Future<void> Function() beforeRead;
  Future<void> Function(String)? beforeTid;
  final List<String> tids = [];
  int calls = 0;
  bool fail = false;
  @override
  final capabilities = ThreadDetailSourceCapabilities(
    values: DataCapabilitySet.supported(ThreadDetailCapability.values),
    paginationPrecision: PaginationPrecision.exact,
  );
  @override
  Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  getThreadDetail({
    required String tid,
    int page = 1,
    ThreadDetailQuery query = const ThreadDetailQuery(),
  }) async {
    calls++;
    tids.add(tid);
    if (beforeTid != null) {
      await beforeTid!(tid);
    } else {
      await beforeRead();
    }
    if (fail) {
      return const DataReadFailure(
        kind: DataReadFailureKind.network,
        diagnosticMessage: 'fixture_failure',
      );
    }
    return DataReadSuccess(
      data: ThreadDetailData(
        tid: tid,
        fid: '55',
        typeid: '295',
        subject: 'Novel',
        author: 'Author',
        replies: 1,
        views: 1,
        currentPage: 1,
        perPage: 20,
        posts: [
          ThreadPost(
            pid: '${tid}1',
            author: 'Author',
            authorId: '123',
            message: '<p>Novel</p>',
            number: 1,
            isFirst: true,
            dateline: '',
          ),
        ],
      ),
      capabilities: capabilities.toReadCapabilities(),
      metadata: const DataReadMetadata.network(),
    );
  }
}

class _Directory implements FavoriteThreadDirectoryRepository {
  _Directory({this.beforeRead, this.tids});
  final Future<void> Function()? beforeRead;
  final List<String>? tids;
  int calls = 0;
  @override
  final capabilities = FavoriteThreadDirectorySourceCapabilities(
    values: DataCapabilitySet.supported(
      FavoriteThreadDirectoryCapability.values,
    ),
    paginationPrecision: PaginationPrecision.exact,
  );
  @override
  Future<
    DataReadResult<
      FavoriteThreadDirectoryData,
      FavoriteThreadDirectoryReadCapabilities
    >
  >
  load(
    FavoriteThreadDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    calls++;
    await beforeRead?.call();
    if (tids != null) {
      return DataReadSuccess(
        data: FavoriteThreadDirectoryData(
          items: [
            for (final tid in tids!)
              FavoriteThreadReference(tid: tid, title: 'Novel', replyCount: 1),
          ],
          pagination: FavoriteThreadPagination(
            currentPage: 1,
            pageSize: 20,
            totalItems: tids!.length,
            totalPages: 1,
            hasPrevious: false,
            hasNext: false,
          ),
        ),
        capabilities: capabilities.toReadCapabilities(),
        metadata: const DataReadMetadata.network(),
      );
    }
    return const DataReadFailure(
      kind: DataReadFailureKind.network,
      diagnosticMessage: 'directory_not_expected_for_single_parse',
    );
  }
}

class _DatabasePurge implements WorkPurgeService {
  _DatabasePurge(this.db);
  final Database db;
  final List<String> workIds = [];
  @override
  Future<WorkPurgeResult> purge({
    required String workId,
    required ThreadContentKind kind,
  }) async {
    workIds.add(workId);
    await db.delete(
      AppDatabase.worksTable,
      where: 'work_id = ?',
      whereArgs: [workId],
    );
    return WorkPurgeResult(
      workId: workId,
      kind: kind,
      purgedDownload: false,
      purgedCache: false,
    );
  }
}

class _RecoveryFailsOnce extends FavoriteParseJobRepository {
  _RecoveryFailsOnce(super.database);
  var first = true;
  @override
  Future<void> recover(String accountId) async {
    if (first) {
      first = false;
      throw StateError('temporary_database_failure');
    }
    await super.recover(accountId);
  }
}

class _ObservedExecutor implements FavoriteThreadParseExecutor {
  _ObservedExecutor(this.inner, this.submitted);
  final FavoriteThreadParseExecutor inner;
  final Completer<void> submitted;
  @override
  Future<void> parseThread(
    FavoriteParseTarget target, {
    required Future<bool> Function() isCurrent,
  }) {
    final future = inner.parseThread(target, isCurrent: isCurrent);
    if (!submitted.isCompleted) submitted.complete();
    return future;
  }

  @override
  void noteMembershipChange(
    Set<String> tids, {
    required bool favorited,
    String? remoteFavoriteId,
    bool onlyIfUnknown = false,
  }) => inner.noteMembershipChange(
    tids,
    favorited: favorited,
    remoteFavoriteId: remoteFavoriteId,
    onlyIfUnknown: onlyIfUnknown,
  );
  @override
  bool isUnfavorited(String tid) => inner.isUnfavorited(tid);
  @override
  Future<void> waitForPendingOperations() => inner.waitForPendingOperations();
}

class _DelayedEligibility extends FavoriteParseJobRepository {
  _DelayedEligibility(super.database, this.claimed, this.release);
  final Completer<void> claimed, release;
  bool first = true;
  @override
  Future<bool> isCurrent(FavoriteParseJob job) async {
    final valid = await super.isCurrent(job);
    if (first) {
      first = false;
      claimed.complete();
      await release.future;
    }
    return valid;
  }
}

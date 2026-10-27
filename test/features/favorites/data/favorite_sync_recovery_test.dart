import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/favorites/data/repositories/local_favorite_repository.dart';
import 'package:y300/features/favorites/data/services/default_favorite_sync_request_governor.dart';
import 'package:y300/features/favorites/data/services/favorite_content_ingest_registry.dart';
import 'package:y300/features/favorites/data/services/favorite_detail_context_loader.dart';
import 'package:y300/features/favorites/data/services/favorite_link_service_impl.dart';
import 'package:y300/features/favorites/data/services/favorite_shelf_bootstrapper.dart';
import 'package:y300/features/favorites/data/services/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/services/library_post_ingest_task_runner.dart';
import 'package:y300/features/favorites/data/use_cases/unfavorite_use_cases_impl.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/work_purge_service.dart';
import 'package:y300/features/novel/data/repositories/sqflite_novel_source_metadata_repository.dart';
import 'package:y300/features/novel/data/services/novel_favorite_ingest_service.dart';
import 'package:y300/features/novel/data/services/novel_source_metadata_ingest_service.dart';
import 'package:y300/features/novel/domain/services/novel_source_metadata_parser.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';
import 'package:y300/features/thread/domain/models/thread_favorite_models.dart';
import 'package:y300/features/thread/domain/services/thread_favorite_action_service.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

import '../../../support/favorite_command_test_support.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late SqfliteLocalFavoriteRepository local;
  late LibraryShelfRefreshBus bus;
  late Directory databaseDirectory;
  late String databasePath;

  setUp(() async {
    databaseDirectory = await Directory.systemTemp.createTemp(
      'favorite-recovery-',
    );
    databasePath = p.join(databaseDirectory.path, 'favorites.db');
    db = await AppDatabase.open(databaseName: databasePath);
    local = SqfliteLocalFavoriteRepository(Future.value(db));
    bus = LibraryShelfRefreshBus();
  });

  tearDown(() async {
    bus.dispose();
    await db.close();
    await deleteDatabase(databasePath);
    await databaseDirectory.delete();
  });

  Future<void> restartRepository() async {
    await db.close();
    db = await AppDatabase.open(databaseName: databasePath);
    local = SqfliteLocalFavoriteRepository(Future.value(db));
  }

  NetworkFavoriteSyncService buildService(
    _ThreadSource source, {
    _Directory? directory,
    void Function()? onGovernorCreated,
    LocalFavoriteRepository? repository,
  }) {
    const forum = ForumFavoriteContentIngestHandler();
    return NetworkFavoriteSyncService(
      remoteRepository: directory ?? _Directory(),
      localRepository: repository ?? local,
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
      governorFactory: () {
        onGovernorCreated?.call();
        return DefaultFavoriteSyncRequestGovernor(cooldown: Duration.zero);
      },
    );
  }

  ThreadFavoriteActionService legacyActionFor(
    FavoriteSyncService service, {
    FakeFavoriteThreadCommand? command,
  }) {
    return DefaultThreadFavoriteActionService(
      command: command ?? FakeFavoriteThreadCommand(),
      enqueueFavoriteParse: ({required receipt, title}) async {
        final result = await service.syncRecentlyAddedThread(tid: receipt.tid);
        if (result.failedDetailTids.contains(receipt.tid)) {
          throw StateError('legacy_target_sync_failed');
        }
      },
      notifyFavoriteModule: ({required reason, required tid}) {
        bus.notify(
          modules: {LibraryModuleKey.favorite},
          reason: reason,
          source: LibraryMutationSource.threadFavoriteAction,
          tid: tid,
        );
      },
    );
  }

  Future<void> seed({
    ThreadContentKind kind = ThreadContentKind.unknown,
    bool resolved = false,
    bool baseline = false,
  }) async {
    await local.upsertRemoteThreads(const [
      FavoriteThreadCacheUpsert(tid: '200', title: 'Novel', replyCount: 1),
    ]);
    if (resolved) {
      await local.updateThreadDetailMeta(
        tid: '200',
        fid: '1',
        typeid: '',
        tagName: null,
        contentKind: kind,
        workId: 'thread:200',
      );
    }
    if (baseline) {
      await local.finishSync(mode: FavoriteSyncMode.fullDiff, remoteCount: 1);
    }
  }

  Future<void> expectNovel() async {
    final record = await local.getActiveThreadByTid('200');
    expect(record?.contentKind, ThreadContentKind.novel);
    expect(record?.detailState, FavoriteDetailState.resolved);
    expect(record?.workId, 'novel:55:200');
    expect(await local.loadCategoryItems(favoriteDefaultCategoryId), isEmpty);
    expect(
      await local.loadCategoryItems(favoriteNovelCategoryId),
      hasLength(1),
    );
    expect(await db.query(AppDatabase.novelSourceStateTable), hasLength(1));
  }

  test('restart reenters initial sync after interruption before any list row was saved', () async {
    final originalSource = _ThreadSource((_) async => _success(_detail()));
    final original = buildService(
      originalSource,
      directory: _Directory()..failFirstRead = true,
    );
    await expectLater(original.sync(), throwsStateError);
    expect(originalSource.calls, 0);
    expect(await local.countActiveThreads(), 0);
    expect((await local.getSyncSnapshot())?.status, 'failed');
    await restartRepository();
    final source = _ThreadSource((_) async => _success(_detail()));
    final directory = _Directory();
    final bootstrap = DefaultFavoriteShelfBootstrapper(
      repository: local,
      syncService: buildService(source, directory: directory),
    );

    await bootstrap.startIfNeeded();

    expect(directory.calls, 1);
    expect(source.calls, 1);
    await expectNovel();
  });

  for (final recentAdd in [false, true]) {
    test(
      'restart reads the complete directory after interruption between list commits (recentAdd=$recentAdd)',
      () async {
        final originalSource = _ThreadSource((_) async => _success(_detail()));
        final interruptedRepository = _InterruptedFavoriteRepository(
          Future.value(db),
          interruptListWriteAt: 2,
        );
        final original = buildService(
          originalSource,
          directory: _Directory(tids: const ['200', '201'], pageSize: 1),
          repository: interruptedRepository,
        );
        await expectLater(original.sync(), throwsStateError);
        expect(originalSource.calls, 0);
        expect(await local.getActiveTids(), {'200'});
        expect((await local.getSyncSnapshot())?.status, 'failed');
        await restartRepository();
        final source = _ThreadSource(
          (_) async => _success(_detail()),
          readByTid: (tid) async => _success(_detail(tid: tid)),
        );
        final directory = _Directory(tids: const ['200', '201'], pageSize: 1);
        final service = buildService(source, directory: directory);
        if (recentAdd) {
          final command = FakeFavoriteThreadCommand();
          final unfavorite = DefaultUnfavoriteThreadUseCase(
            favoriteThreadCommand: command,
            favoriteLinkService: DefaultFavoriteLinkService(repository: local),
            localFavoriteRepository: local,
            workPurgeService: _UnexpectedWorkPurge(),
            shelfRefreshBus: bus,
          );
          expect((await unfavorite.call('200')).succeededTids, ['200']);
          final result = await legacyActionFor(
            service,
            command: command,
          ).favoriteThread(tid: '200');
          expect(
            (result as DataCommandApplied<ThreadFavoriteActionResult>)
                .receipt
                .parseQueued,
            isTrue,
          );
          expect(command.requests.map((e) => e.targetState), [
            FavoriteTargetState.unfavorited,
            FavoriteTargetState.favorited,
          ]);
        } else {
          await DefaultFavoriteShelfBootstrapper(
            repository: local,
            syncService: service,
          ).startIfNeeded();
        }

        expect(directory.calls, 2);
        expect(source.requestedTids, ['200', '201']);
        expect(await local.getActiveTids(), {'200', '201'});
        expect(
          await local.loadCategoryItems(favoriteNovelCategoryId),
          hasLength(2),
        );
        final snapshot = await local.getSyncSnapshot();
        expect(snapshot?.status, 'ok');
        expect(snapshot?.remoteCount, snapshot?.localActiveCount);
        expect(snapshot?.lastFullSyncedAt, isNotNull);
      },
    );
  }

  test(
    'restart reconciles an old successful marker with an incomplete directory',
    () async {
      await seed(kind: ThreadContentKind.forum, resolved: true);
      await local.finishSync(
        mode: FavoriteSyncMode.incremental,
        remoteCount: 2,
      );
      expect(await local.countMissingDetailRecords(), 0);
      expect((await local.getSyncSnapshot())?.status, 'ok');
      await restartRepository();
      final source = _ThreadSource((_) async => _success(_detail(tid: '201')));
      final directory = _Directory(tids: const ['200', '201'], pageSize: 1);

      await DefaultFavoriteShelfBootstrapper(
        repository: local,
        syncService: buildService(source, directory: directory),
      ).startIfNeeded();

      expect(directory.calls, 2);
      expect(source.requestedTids, ['201']);
      expect(
        (await local.getActiveThreadByTid('201'))?.contentKind,
        ThreadContentKind.novel,
      );
      expect((await local.getSyncSnapshot())?.needsResume, isFalse);
    },
  );

  test('restart reconciles committed pages with an older success marker', () async {
    await seed(kind: ThreadContentKind.forum, resolved: true, baseline: true);
    // This is the durable state if the app stops after saving a new list page,
    // before it can save later pages or replace the previous sync marker.
    await local.upsertRemoteThreads(const [
      FavoriteThreadCacheUpsert(tid: '201', title: 'Novel', replyCount: 1),
    ]);
    expect((await local.getSyncSnapshot())?.status, 'ok');
    expect((await local.getSyncSnapshot())?.localActiveCount, 1);
    expect(await local.getActiveTids(), {'200', '201'});
    await restartRepository();
    final source = _ThreadSource(
      (_) async => _success(_detail()),
      readByTid: (tid) async => _success(_detail(tid: tid)),
    );
    final directory = _Directory(
      tids: const ['201', '200', '202'],
      pageSize: 1,
    );

    await DefaultFavoriteShelfBootstrapper(
      repository: local,
      syncService: buildService(source, directory: directory),
    ).startIfNeeded();

    expect(directory.calls, 3);
    expect(source.requestedTids, ['201', '202']);
    expect(await local.getActiveTids(), {'200', '201', '202'});
    expect(
      await local.loadCategoryItems(favoriteNovelCategoryId),
      hasLength(2),
    );
    final snapshot = await local.getSyncSnapshot();
    expect(snapshot?.status, 'ok');
    expect(snapshot?.remoteCount, 3);
    expect(snapshot?.localActiveCount, 3);
    expect(snapshot?.lastFullSyncedAt, isNotNull);
  });

  for (final refavorite in [false, true]) {
    test(
      'restart recovers between novel import and favorite classification (refavorite=$refavorite)',
      () async {
        final originalSource = _ThreadSource((_) async => _success(_detail()));
        final original = buildService(
          originalSource,
          repository: _InterruptedFavoriteRepository(
            Future.value(db),
            interruptDetailCommit: true,
          ),
        );
        final interrupted = await original.sync();
        expect(interrupted.failedDetailTids, ['200']);
        expect(originalSource.calls, 1);
        expect(await db.query(AppDatabase.worksTable), hasLength(1));
        expect(
          (await local.getActiveThreadByTid('200'))?.contentKind,
          ThreadContentKind.unknown,
        );
        await restartRepository();
        final source = _ThreadSource((_) async => _success(_detail()));
        final service = buildService(source);
        final command = FakeFavoriteThreadCommand();

        if (refavorite) {
          final unfavorite = DefaultUnfavoriteThreadUseCase(
            favoriteThreadCommand: command,
            favoriteLinkService: DefaultFavoriteLinkService(repository: local),
            localFavoriteRepository: local,
            workPurgeService: _UnexpectedWorkPurge(),
            shelfRefreshBus: bus,
          );
          expect((await unfavorite.call('200')).succeededTids, ['200']);
          final result = await legacyActionFor(
            service,
            command: command,
          ).favoriteThread(tid: '200');
          expect(
            (result as DataCommandApplied<ThreadFavoriteActionResult>)
                .receipt
                .parseQueued,
            isTrue,
          );
          expect(command.requests.map((e) => e.targetState), [
            FavoriteTargetState.unfavorited,
            FavoriteTargetState.favorited,
          ]);
        } else {
          await DefaultFavoriteShelfBootstrapper(
            repository: local,
            syncService: service,
          ).startIfNeeded();
          expect(command.requests, isEmpty);
        }

        expect(source.calls, 1);
        await expectNovel();
        expect(await db.query(AppDatabase.worksTable), hasLength(1));
      },
    );
  }

  test(
    're-favorite rereads a resolved forum record during first full sync',
    () async {
      await seed(kind: ThreadContentKind.forum, resolved: true);
      final command = FakeFavoriteThreadCommand();
      final unfavorite = DefaultUnfavoriteThreadUseCase(
        favoriteThreadCommand: command,
        favoriteLinkService: DefaultFavoriteLinkService(repository: local),
        localFavoriteRepository: local,
        workPurgeService: _UnexpectedWorkPurge(),
        shelfRefreshBus: bus,
      );
      expect((await unfavorite.call('200')).succeededTids, ['200']);
      expect(await local.getSyncSnapshot(), isNull);

      final source = _ThreadSource((_) async => _success(_detail()));
      final result = await legacyActionFor(
        buildService(source),
        command: command,
      ).favoriteThread(tid: '200');

      expect(
        (result as DataCommandApplied<ThreadFavoriteActionResult>)
            .receipt
            .parseQueued,
        isTrue,
      );
      expect(source.calls, 1);
      expect(command.requests.map((e) => e.targetState), [
        FavoriteTargetState.unfavorited,
        FavoriteTargetState.favorited,
      ]);
      await expectNovel();
    },
  );

  test(
    'already-favorited target is reread without a baseline or a removed marker',
    () async {
      await seed(kind: ThreadContentKind.forum, resolved: true);
      final command = FakeFavoriteThreadCommand(
        handler: (request) async => appliedThreadFavorite(
          tid: request.tid,
          targetState: request.targetState,
          disposition: FavoriteMutationDisposition.alreadyApplied,
        ),
      );
      final source = _ThreadSource((_) async => _success(_detail()));

      final result = await legacyActionFor(
        buildService(source),
        command: command,
      ).favoriteThread(tid: '200');

      final receipt =
          (result as DataCommandApplied<ThreadFavoriteActionResult>).receipt;
      expect(receipt.alreadyFavorited, isTrue);
      expect(receipt.parseQueued, isTrue);
      expect(source.calls, 1);
      await expectNovel();
    },
  );

  test(
    'historical detail failures do not hide a successful target refresh',
    () async {
      final result = await legacyActionFor(_HistoricalFailureSync())
          .favoriteThread(tid: '200');

      expect(
        (result as DataCommandApplied<ThreadFavoriteActionResult>)
            .receipt
            .parseQueued,
        isTrue,
      );
      expect(bus.signal.value?.reason, 'thread_favorite_added');
    },
  );

  test(
    'first full recent-add seeds a target missing from the remote list',
    () async {
      final source = _ThreadSource((_) async => _success(_detail()));
      final result = await buildService(
        source,
        directory: _Directory(empty: true),
      ).syncRecentlyAddedThread(tid: '200');

      expect(result.failedDetailTids, isEmpty);
      expect(result.detailLoadedCount, 1);
      expect(source.calls, 1);
      await expectNovel();
    },
  );

  test(
    'ordinary bootstrap repairs an old unknown resolved classification',
    () async {
      await seed(resolved: true, baseline: true);
      expect(await local.countMissingDetailRecords(), 1);
      final source = _ThreadSource((_) async => _success(_detail()));
      final bootstrap = DefaultFavoriteShelfBootstrapper(
        repository: local,
        syncService: buildService(source),
      );

      await bootstrap.startIfNeeded();

      expect(source.calls, 1);
      expect(await local.countMissingDetailRecords(), 0);
      await expectNovel();
    },
  );

  test(
    'missing forum identity remains retryable instead of resolved',
    () async {
      final source = _ThreadSource(
        (call) async => _success(_detail(fid: call == 1 ? '' : '55')),
      );
      final service = buildService(source);

      final failed = await service.sync();
      expect(failed.failedDetailTids, ['200']);
      expect(
        (await local.getActiveThreadByTid('200'))?.detailState,
        FavoriteDetailState.pending,
      );
      expect((await local.getSyncSnapshot())?.status, 'partial');

      await service.sync();
      expect(source.calls, 2);
      await expectNovel();
    },
  );

  test('completed bootstrap resumes a later failed recent-add', () async {
    await local.finishSync(mode: FavoriteSyncMode.fullDiff, remoteCount: 0);
    final source = _ThreadSource((call) async {
      if (call == 1) {
        return const DataReadFailure(
          kind: DataReadFailureKind.network,
          diagnosticMessage: 'temporary_read_failure',
        );
      }
      return _success(_detail());
    });
    final service = buildService(source);
    final bootstrap = DefaultFavoriteShelfBootstrapper(
      repository: local,
      syncService: service,
    );
    await bootstrap.startIfNeeded();
    final command = FakeFavoriteThreadCommand();

    final result = await legacyActionFor(
      service,
      command: command,
    ).favoriteThread(tid: '200');
    expect(
      (result as DataCommandApplied<ThreadFavoriteActionResult>)
          .receipt
          .parseQueued,
      isFalse,
    );
    expect(bus.signal.value?.reason, 'thread_favorite_added_sync_failed');
    expect((await local.getSyncSnapshot())?.status, 'partial');

    await bootstrap.startIfNeeded();

    expect(source.calls, 2);
    expect(command.requests, hasLength(1));
    await expectNovel();
  });

  test('a target metadata failure preserves remote success and reports local failure', () async {
    final source = _ThreadSource((_) async => _success(_detail(authorId: '0')));
    final service = buildService(source);

    final result = await legacyActionFor(service).favoriteThread(tid: '200');

    expect(
      (result as DataCommandApplied<ThreadFavoriteActionResult>)
          .receipt
          .parseQueued,
      isFalse,
    );
    expect((await local.getSyncSnapshot())?.status, 'partial');
    expect(await local.countMissingDetailRecords(), 1);
    expect(service.progress.value.isActive, isFalse);
  });

  for (final hasBaseline in [false, true]) {
    test(
      'failed explicit retry of resolved metadata stays pending (baseline=$hasBaseline)',
      () async {
        await seed(
          kind: ThreadContentKind.forum,
          resolved: true,
          baseline: hasBaseline,
        );
        final source = _ThreadSource((call) async {
          if (call == 1) {
            return const DataReadFailure(
              kind: DataReadFailureKind.network,
              diagnosticMessage: 'temporary_read_failure',
            );
          }
          return _success(_detail());
        });
        final service = buildService(source);
        final bootstrap = DefaultFavoriteShelfBootstrapper(
          repository: local,
          syncService: service,
        );
        if (hasBaseline) {
          await bootstrap.startIfNeeded();
        }
        final command = FakeFavoriteThreadCommand();

        final result = await legacyActionFor(
          service,
          command: command,
        ).favoriteThread(tid: '200');

        expect(
          (result as DataCommandApplied<ThreadFavoriteActionResult>)
              .receipt
              .parseQueued,
          isFalse,
        );
        final failedRecord = await local.getActiveThreadByTid('200');
        expect(failedRecord?.detailState, FavoriteDetailState.pending);
        expect(failedRecord?.workId, 'thread:200');
        expect(failedRecord?.detailLoadedAt, isNotNull);
        expect(await local.countMissingDetailRecords(), 1);
        await bootstrap.startIfNeeded();

        expect(source.calls, 2);
        expect(command.requests, hasLength(1));
        await expectNovel();
      },
    );
  }

  for (final restoreByNewId in [false, true]) {
    test(
      'remote re-favorite invalidates the cached detail (newId=$restoreByNewId)',
      () async {
        await seed(
          kind: ThreadContentKind.forum,
          resolved: true,
          baseline: true,
        );
        const first = FavoriteThreadCacheUpsert(
          tid: '200',
          title: 'Novel',
          replyCount: 1,
          remoteFavoriteId: 'old-favorite',
        );
        await local.upsertRemoteThreads([first]);
        expect(await local.countMissingDetailRecords(), 0);
        if (!restoreByNewId) {
          await local.markRemovedByTids({'200'});
        }
        await local.upsertRemoteThreads([
          FavoriteThreadCacheUpsert(
            tid: '200',
            title: 'Novel',
            replyCount: 1,
            remoteFavoriteId: restoreByNewId ? 'new-favorite' : 'old-favorite',
          ),
        ]);
        expect(await local.countMissingDetailRecords(), 1);
        expect((await local.getActiveThreadByTid('200'))?.workId, 'thread:200');
        final source = _ThreadSource((_) async => _success(_detail()));

        await buildService(source).sync();

        expect(source.calls, 1);
        await expectNovel();
      },
    );
  }

  for (final recentFirst in [false, true]) {
    test(
      'sync and recent-add serialize with continuous progress (recentFirst=$recentFirst)',
      () async {
        await seed(baseline: true);
        final firstStarted = Completer<void>();
        final secondStarted = Completer<void>();
        final firstGate = Completer<void>();
        final secondGate = Completer<void>();
        final source = _ThreadSource((_) async => _success(_detail()));
        final directory = _Directory()
          ..beforeRead = (call) async {
            if (call == 1) {
              firstStarted.complete();
              await firstGate.future;
            } else {
              secondStarted.complete();
              await secondGate.future;
            }
          };
        var governorCount = 0;
        final service = buildService(
          source,
          directory: directory,
          onGovernorCreated: () => governorCount++,
        );
        final phases = <FavoriteSyncProgressPhase>[];
        service.progress.addListener(
          () => phases.add(service.progress.value.phase),
        );
        Future<FavoriteSyncResult> recent() =>
            service.syncRecentlyAddedThread(tid: '200');

        final first = recentFirst ? recent() : service.sync();
        await firstStarted.future;
        final second = recentFirst ? service.sync() : recent();
        expect(directory.calls, 1);
        expect(source.calls, 0);
        firstGate.complete();
        await first;
        await secondStarted.future;
        expect(service.progress.value.isActive, isTrue);
        expect(phases, isNot(contains(FavoriteSyncProgressPhase.completed)));
        secondGate.complete();
        await second;

        expect(
          service.progress.value.phase,
          FavoriteSyncProgressPhase.completed,
        );
        expect(governorCount, 1);
        await expectNovel();
      },
    );
  }

  test(
    'concurrent recent-add calls for the same target share a single read',
    () async {
      final started = Completer<void>();
      final gate = Completer<void>();
      final source = _ThreadSource((_) async {
        started.complete();
        await gate.future;
        return _success(_detail());
      });
      final directory = _Directory();
      final service = buildService(source, directory: directory);
      final first = service.syncRecentlyAddedThread(tid: '200');
      await started.future;
      final second = service.syncRecentlyAddedThread(tid: ' 200 ');
      gate.complete();
      await Future.wait([first, second]);

      expect(source.calls, 1);
      expect(directory.calls, 1);
      await expectNovel();
    },
  );

  test('a failed queued sync does not prevent the next recent-add', () async {
    final source = _ThreadSource((_) async => _success(_detail()));
    final directory = _Directory()..failFirstRead = true;
    final service = buildService(source, directory: directory);
    final first = expectLater(service.sync(), throwsStateError);
    final next = service.syncRecentlyAddedThread(tid: '200');

    await first;
    expect((await next).failedDetailTids, isEmpty);
    expect(service.progress.value.phase, FavoriteSyncProgressPhase.completed);
    await expectNovel();
  });
}

ThreadDetailData _detail({
  String tid = '200',
  String fid = '55',
  String authorId = '123',
}) => ThreadDetailData(
  tid: tid,
  fid: fid,
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
      authorId: authorId,
      message: '<p>Novel first post</p>',
      number: 1,
      isFirst: true,
      dateline: '',
    ),
  ],
);

DataReadSuccess<ThreadDetailData, ThreadDetailReadCapabilities> _success(
  ThreadDetailData detail,
) => DataReadSuccess(
  data: detail,
  capabilities: _ThreadSource.sourceCapabilities.toReadCapabilities(),
  metadata: const DataReadMetadata.network(),
);

class _ThreadSource implements ThreadRepository {
  _ThreadSource(this.read, {this.readByTid});
  final Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  Function(String)?
  readByTid;
  final List<String> requestedTids = [];
  final Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  Function(int)
  read;
  int calls = 0;
  static final sourceCapabilities = ThreadDetailSourceCapabilities(
    values: DataCapabilitySet.from(
      supported: const [
        ThreadDetailCapability.threadIdentity,
        ThreadDetailCapability.forumIdentity,
        ThreadDetailCapability.orderedPosts,
        ThreadDetailCapability.renderableBody,
      ],
    ),
    paginationPrecision: PaginationPrecision.directional,
  );
  @override
  ThreadDetailSourceCapabilities get capabilities => sourceCapabilities;
  @override
  Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  getThreadDetail({
    required String tid,
    int page = 1,
    ThreadDetailQuery query = const ThreadDetailQuery(),
  }) {
    calls++;
    requestedTids.add(tid);
    return readByTid?.call(tid) ?? read(calls);
  }
}

class _Directory implements FavoriteThreadDirectoryRepository {
  _Directory({
    this.empty = false,
    this.tids = const ['200'],
    this.pageSize = 20,
  });
  final bool empty;
  final List<String> tids;
  final int pageSize;
  bool failFirstRead = false;
  Future<void> Function(int)? beforeRead;
  int calls = 0;
  @override
  final capabilities = FavoriteThreadDirectorySourceCapabilities(
    values: DataCapabilitySet.from(
      supported: FavoriteThreadDirectoryCapability.values,
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
    await beforeRead?.call(calls);
    if (calls == 1 && failFirstRead) {
      return const DataReadFailure(
        kind: DataReadFailureKind.network,
        diagnosticMessage: 'temporary_directory_failure',
      );
    }
    final allTids = empty ? const <String>[] : tids;
    final totalPages = allTids.isEmpty ? 1 : (allTids.length / pageSize).ceil();
    return DataReadSuccess(
      data: FavoriteThreadDirectoryData(
        items: allTids
            .skip((query.page - 1) * pageSize)
            .take(pageSize)
            .map(
              (tid) => FavoriteThreadReference(
                tid: tid,
                title: 'Novel',
                replyCount: 1,
              ),
            )
            .toList(),
        pagination: FavoriteThreadPagination(
          currentPage: query.page,
          pageSize: pageSize,
          totalItems: allTids.length,
          totalPages: totalPages,
          hasPrevious: query.page > 1,
          hasNext: query.page < totalPages,
        ),
      ),
      capabilities: capabilities.toReadCapabilities(),
      metadata: const DataReadMetadata.network(),
    );
  }
}

class _UnexpectedWorkPurge implements WorkPurgeService {
  @override
  Future<WorkPurgeResult> purge({
    required String workId,
    required ThreadContentKind kind,
  }) => throw StateError('An ordinary forum favorite must not purge a novel.');
}

/// Interrupts a committed workflow stage without changing any source content.
class _InterruptedFavoriteRepository extends SqfliteLocalFavoriteRepository {
  _InterruptedFavoriteRepository(
    super.database, {
    this.interruptListWriteAt,
    this.interruptDetailCommit = false,
  });

  final int? interruptListWriteAt;
  final bool interruptDetailCommit;
  int _listWrites = 0;

  @override
  Future<int> upsertRemoteThreads(List<FavoriteThreadCacheUpsert> items) {
    if (++_listWrites == interruptListWriteAt) {
      throw StateError('interrupted_between_list_commits');
    }
    return super.upsertRemoteThreads(items);
  }

  @override
  Future<void> updateThreadDetailMeta({
    required String tid,
    required String fid,
    required String typeid,
    required String? tagName,
    required ThreadContentKind contentKind,
    required String? workId,
  }) {
    if (interruptDetailCommit) {
      throw StateError('interrupted_before_favorite_classification');
    }
    return super.updateThreadDetailMeta(
      tid: tid,
      fid: fid,
      typeid: typeid,
      tagName: tagName,
      contentKind: contentKind,
      workId: workId,
    );
  }
}

class _HistoricalFailureSync implements FavoriteSyncService {
  @override
  Future<FavoriteSyncResult> syncRecentlyAddedThread({
    required String tid,
  }) async => const FavoriteSyncResult(
    mode: FavoriteSyncMode.fullDiff,
    remoteCount: 2,
    fetchedPages: 1,
    upsertedCount: 2,
    removedRecords: [],
    detailLoadedCount: 1,
    failedDetailTids: ['another-thread'],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

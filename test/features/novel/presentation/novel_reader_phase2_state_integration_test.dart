import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/data/repositories/local_library_state_repository.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/data/repositories/local_novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/models/novel_reading_progress.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_reading_state_repository.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_position.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_document_build_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_progress_committer.dart';

import '../test_support/novel_repository_seed.dart';

const _novel = 'novel:49:100';
const _a = '$_novel:5001';
const _b = '$_novel:5003';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late _Fixture fixture;
  setUp(() async {
    fixture = await _Fixture.create();
  });
  tearDown(() async => fixture.dispose());

  test(
    'bootstrap restores the selected chapter instead of only the most recent chapter',
    () async {
      await fixture.repository.commitProgress(progress: _position(_a, .2));
      await fixture.repository.commitProgress(progress: _position(_b, .4));
      final reader = await fixture.open(_a);
      var state = fixture.state(_a);
      expect(state.readingProgress!.episodeId, _b);
      expect(state.readingState!.progressByEpisode, hasLength(2));
      expect(state.progressSnapshot.episodeId, _a);
      expect(state.progressSnapshot.progressPercent, .2);
      expect(state.currentOffset, 200);
      expect(await reader.openEpisodeFromCatalog(_b), true);
      state = fixture.state(_a);
      expect(state.currentEpisode.episodeId, _b);
      expect(state.progressSnapshot.progressPercent, .4);
      expect(state.currentOffset, 400);
      expect(
        (await fixture.repository.loadWorkState(
          novelId: _novel,
        )).progressByEpisode,
        hasLength(2),
      );
    },
  );

  test(
    'completed catalog chapter opens at the beginning and leaves its recorded position intact',
    () async {
      await fixture.repository.commitProgress(
        progress: _position(_a, .7),
        markCompleted: true,
      );
      final reader = await fixture.open(_b);
      expect(await reader.openEpisodeFromCatalog(_a), true);
      final state = fixture.state(_b);
      expect(state.currentEpisode.episodeId, _a);
      expect(state.currentOffset, 0);
      expect(state.progressSnapshot.progressPercent, 0);
      expect(
        (await fixture.repository.getChapterProgress(
          novelId: _novel,
          episodeId: _a,
        ))!.progressPercent,
        .7,
      );
      expect(state.readingState!.episodeStates[_a]!.isRead, true);
    },
  );

  test(
    'transition flushes the old chapter before retiring its debounce lease',
    () async {
      final reader = await fixture.open(_a);
      await reader.onVerticalContentReady(_a, bodySnapshot: _snapshot(_a, 0));
      await reader.onScrollOffsetChanged(420, bodySnapshot: _snapshot(_a, .42));
      // The committer's controlled one-minute debounce has not fired here.
      expect(
        (await fixture.repository.getChapterProgress(
          novelId: _novel,
          episodeId: _a,
        ))!.progressPercent,
        0,
      );
      expect(await reader.openEpisodeFromCatalog(_b), true);
      expect(
        (await fixture.repository.getChapterProgress(
          novelId: _novel,
          episodeId: _a,
        ))!.progressPercent,
        .42,
      );
      expect(
        await fixture.repository.getChapterProgress(
          novelId: _novel,
          episodeId: _b,
        ),
        isNull,
      );
      expect(fixture.state(_a).currentEpisode.episodeId, _b);
    },
  );

  test(
    'manual unread rejects an in-flight old callback and accepts only a new real navigation',
    () async {
      await fixture.repository.commitProgress(progress: _position(_a, .4));
      final reader = await fixture.open(_a);
      await reader.onScrollOffsetChanged(430, bodySnapshot: _snapshot(_a, .43));
      final entered = Completer<void>();
      final release = Completer<void>();
      fixture.repository.beforeCommit = () async {
        entered.complete();
        await release.future;
      };
      final oldFlush = reader.saveCurrentProgressNow(_snapshot(_a, .43));
      await entered.future;
      await reader.setChapterRead(_a, false);
      release.complete();
      await oldFlush;
      fixture.repository.beforeCommit = null;
      expect(
        await fixture.repository.getChapterProgress(
          novelId: _novel,
          episodeId: _a,
        ),
        isNull,
      );
      await reader.saveCurrentProgressNow(fixture.state(_a).progressSnapshot);
      expect(
        await fixture.repository.getChapterProgress(
          novelId: _novel,
          episodeId: _a,
        ),
        isNull,
      );
      await reader.onScrollOffsetChanged(500, bodySnapshot: _snapshot(_a, .5));
      await reader.saveCurrentProgressNow(fixture.state(_a).progressSnapshot);
      expect(
        (await fixture.repository.getChapterProgress(
          novelId: _novel,
          episodeId: _a,
        ))!.progressPercent,
        .5,
      );
    },
  );

  test(
    'disposing a covered controller cannot cancel the shared committer of the current reader',
    () async {
      final covered = await fixture.open(_a);
      covered.updateReadingVisibility(frontmost: false, resumed: true);
      final current = await fixture.open(_b);
      await current.onVerticalContentReady(_b, bodySnapshot: _snapshot(_b, 0));
      await current.onScrollOffsetChanged(600, bodySnapshot: _snapshot(_b, .6));
      final entered = Completer<void>();
      final release = Completer<void>();
      fixture.repository.beforeCommit = () async {
        entered.complete();
        await release.future;
      };
      final flush = current.saveCurrentProgressNow(
        fixture.state(_b).progressSnapshot,
      );
      await entered.future;
      fixture.closeReader(_a);
      await fixture.container.pump();
      release.complete();
      await flush;
      fixture.repository.beforeCommit = null;
      expect(
        (await fixture.repository.getChapterProgress(
          novelId: _novel,
          episodeId: _b,
        ))!.progressPercent,
        .6,
      );
    },
  );

  test(
    'passive paging restore and exit retain unsupported anchor and percentage basis',
    () async {
      fixture.preferences.value = fixture.preferences.value.copyWith(
        flowMode: NovelReaderFlowMode.pagedLtr,
      );
      await fixture.repository.commitProgress(
        progress: NovelReadingProgress(
          novelId: _novel,
          episodeId: _a,
          scrollOffset: 37,
          updatedAt: DateTime(2026),
          flowMode: NovelReaderFlowMode.pagedLtr,
          pageIndex: 7,
          pageCount: 12,
          anchorNodeId: 'future-node',
          anchorTextOffset: 1 << 35,
          anchorFormatVersion: 77,
          anchorTextIdentity: ' opaque identity ',
          paginationKey: 'future-layout',
          progressPercent: .625,
          isProgressPercentValid: true,
          percentBasis: 'futureBasisV77',
        ),
      );
      final before = (await fixture.db.query(
        AppDatabase.novelReadingProgressTable,
      )).single;
      final reader = await fixture.open(_a);
      expect(fixture.state(_a).progressSnapshot.percentBasis, 'futureBasisV77');
      reader.onPagedPositionChanged(
        const NovelReaderPaginationPosition(
          episodeId: _a,
          paginationKey: 'new-layout',
          pageIndex: 2,
          pageCount: 4,
          anchor: NovelReaderTextAnchor(episodeId: _a),
          isReadOnlyCompatibilityRestore: true,
        ),
      );
      await reader.saveCurrentProgressNow(fixture.state(_a).progressSnapshot);
      expect(
        (await fixture.db.query(AppDatabase.novelReadingProgressTable)).single,
        before,
      );
      fixture.closeReader(_a);
      await fixture.container.pump();
      expect(
        (await fixture.db.query(AppDatabase.novelReadingProgressTable)).single,
        before,
      );
    },
  );

  test(
    'disposing a controller cancels its delayed manual mutation without clearing progress',
    () async {
      await fixture.repository.commitProgress(progress: _position(_a, .4));
      final reader = await fixture.open(_a);
      final entered = Completer<void>();
      final release = Completer<void>();
      fixture.repository.beforeReadStateMutation = () async {
        entered.complete();
        await release.future;
      };
      final mutation = reader.setChapterRead(_a, false);
      await entered.future;
      fixture.closeReader(_a);
      await fixture.container.pump();
      release.complete();
      await mutation;
      expect(
        (await fixture.repository.getChapterProgress(
          novelId: _novel,
          episodeId: _a,
        ))!.progressPercent,
        .4,
      );
    },
  );

  test(
    'late manual reset cannot delete a new same-chapter reading session',
    () async {
      await fixture.repository.commitProgress(progress: _position(_a, .4));
      final reader = await fixture.open(_a);
      final entered = Completer<void>();
      final release = Completer<void>();
      fixture.repository.beforeReadStateMutation = () async {
        entered.complete();
        await release.future;
      };
      final oldReset = reader.setChapterRead(_a, false);
      await entered.future;
      expect(await reader.openEpisodeFromBeginning(_a), true);
      await reader.onVerticalContentReady(_a, bodySnapshot: _snapshot(_a, 0));
      await reader.onScrollOffsetChanged(300, bodySnapshot: _snapshot(_a, .3));
      await reader.saveCurrentProgressNow(fixture.state(_a).progressSnapshot);
      release.complete();
      await oldReset;
      expect(
        (await fixture.repository.getChapterProgress(
          novelId: _novel,
          episodeId: _a,
        ))!.progressPercent,
        .3,
      );
      expect(fixture.state(_a).currentOffset, 300);
    },
  );

  test(
    'a failed transition flush keeps the current chapter without throwing',
    () async {
      final reader = await fixture.open(_a);
      await reader.onVerticalContentReady(_a, bodySnapshot: _snapshot(_a, 0));
      await reader.onScrollOffsetChanged(420, bodySnapshot: _snapshot(_a, .42));
      fixture.repository.beforeCommit = () async {
        throw StateError('controlled persistence failure');
      };
      expect(await reader.openEpisodeFromCatalog(_b), false);
      expect(fixture.state(_a).currentEpisode.episodeId, _a);
      expect(fixture.state(_a).currentOffset, 420);
      expect(fixture.state(_a).transition, isNull);
      expect(
        await fixture.repository.getChapterProgress(
          novelId: _novel,
          episodeId: _b,
        ),
        isNull,
      );
      fixture.repository.beforeCommit = null;
      expect(await reader.openEpisodeFromCatalog(_b), true);
      expect(
        (await fixture.repository.getChapterProgress(
          novelId: _novel,
          episodeId: _a,
        ))!.progressPercent,
        .42,
      );
    },
  );

  test(
    'layout changes preserve queued user position without advancing or completing the chapter',
    () async {
      await fixture.dispose();
      fixture = await _Fixture.create(
        debounceDuration: const Duration(milliseconds: 40),
      );
      await fixture.repository.commitProgress(progress: _position(_a, .4));
      final reader = await fixture.open(_a);
      final entered = Completer<void>();
      final release = Completer<void>();
      final committed = Completer<bool>();
      fixture.repository.beforeCommit = () async {
        entered.complete();
        await release.future;
      };
      fixture.repository.afterCommit = committed.complete;
      await reader.onScrollOffsetChanged(420, bodySnapshot: _snapshot(_a, .42));
      for (final geometry in ['geometry-a', 'geometry-b']) {
        reader.observeReadingSurface(
          bodyReady: true,
          restoreSettled: true,
          finalBoundaryKnown: false,
          atBodyEnd: false,
          wholeBodyVisible: false,
          idle: true,
          geometryIdentity: geometry,
          bodySnapshot: _snapshot(_a, geometry == 'geometry-a' ? .6 : .8),
        );
      }
      // Wait for the original debounce, rather than flushing and issuing a new
      // lease that could conceal accidental retirement of the queued position.
      await entered.future.timeout(const Duration(seconds: 2));
      expect(fixture.state(_a).progressSnapshot.progressPercent, .42);
      expect(
        (await fixture.repository.getChapterProgress(
          novelId: _novel,
          episodeId: _a,
        ))!.progressPercent,
        .4,
      );
      release.complete();
      expect(await committed.future.timeout(const Duration(seconds: 2)), true);
      final state = await fixture.repository.loadWorkState(novelId: _novel);
      expect(state.progressByEpisode[_a]!.progressPercent, .42);
      expect(state.episodeStates[_a]?.isRead == true, false);
      fixture.repository.beforeCommit = null;
      fixture.repository.afterCommit = null;
    },
  );

  test(
    'source return adopts the same chapter position and remains read-only',
    () async {
      await fixture.repository.commitProgress(progress: _position(_a, .2));
      final reader = await fixture.open(_a);
      final oldRevision = fixture.state(_a).readingSurfaceRevision;
      final handoff = reader.beginSourceReadingHandoff()!;
      reader.updateReadingVisibility(frontmost: false, resumed: true);
      await fixture.repository.commitProgress(progress: _position(_a, .7));
      await fixture.repository.commitProgress(progress: _position(_b, .3));
      await reader.acceptSourceReadingReturn(handoff);
      final state = fixture.state(_a);
      expect(state.currentEpisode.episodeId, _a);
      expect(state.currentOffset, 700);
      expect(state.progressSnapshot.progressPercent, .7);
      expect(state.readingSurfaceRevision, oldRevision + 1);
      expect(state.readingProgress!.episodeId, _b);
      expect(state.readingState!.progressByEpisode[_b]!.progressPercent, .3);
      reader.updateReadingVisibility(frontmost: true, resumed: true);
      await reader.onVerticalContentReady(_a, bodySnapshot: _snapshot(_a, .68));
      await reader.saveCurrentProgressNow(_snapshot(_a, .68));
      expect(
        (await fixture.repository.getChapterProgress(
          novelId: _novel,
          episodeId: _a,
        ))!.progressPercent,
        .7,
      );
      expect(
        (await fixture.repository.loadWorkState(
          novelId: _novel,
        )).recentEpisodeId,
        _b,
      );
      await reader.onScrollOffsetChanged(750, bodySnapshot: _snapshot(_a, .75));
      await reader.saveCurrentProgressNow(fixture.state(_a).progressSnapshot);
      expect(
        (await fixture.repository.getChapterProgress(
          novelId: _novel,
          episodeId: _a,
        ))!.progressPercent,
        .75,
      );
    },
  );

  test(
    'retired reader flush cannot overwrite a newer source position',
    () async {
      await fixture.repository.commitProgress(progress: _position(_a, .2));
      final reader = await fixture.open(_a);
      await reader.onScrollOffsetChanged(400, bodySnapshot: _snapshot(_a, .4));
      final entered = Completer<void>();
      final release = Completer<void>();
      fixture.repository.beforeCommit = () async {
        entered.complete();
        await release.future;
      };
      final oldFlush = reader.saveCurrentProgressNow(_snapshot(_a, .4));
      await entered.future;
      final handoff = reader.beginSourceReadingHandoff()!;
      reader.updateReadingVisibility(frontmost: false, resumed: true);
      fixture.repository.beforeCommit = null;
      await fixture.repository.commitProgress(progress: _position(_a, .8));
      release.complete();
      await oldFlush;
      await reader.acceptSourceReadingReturn(handoff);
      expect(
        (await fixture.repository.getChapterProgress(
          novelId: _novel,
          episodeId: _a,
        ))!.progressPercent,
        .8,
      );
      expect(fixture.state(_a).progressSnapshot.progressPercent, .8);
      reader.updateReadingVisibility(frontmost: true, resumed: true);
      await reader.saveCurrentProgressNow(_snapshot(_a, .4));
      expect(
        (await fixture.repository.getChapterProgress(
          novelId: _novel,
          episodeId: _a,
        ))!.progressPercent,
        .8,
      );
    },
  );

  test(
    'source reset returns to a read-only head without recreating history',
    () async {
      await fixture.repository.commitProgress(progress: _position(_a, .4));
      final reader = await fixture.open(_a);
      final handoff = reader.beginSourceReadingHandoff()!;
      await fixture.repository.resetChapter(novelId: _novel, episodeId: _a);
      await reader.acceptSourceReadingReturn(handoff);
      expect(fixture.state(_a).currentOffset, 0);
      expect(fixture.state(_a).readingState!.progressByEpisode, isEmpty);
      await reader.onVerticalContentReady(_a, bodySnapshot: _snapshot(_a, 0));
      await reader.saveCurrentProgressNow(_snapshot(_a, 0));
      expect(
        await fixture.repository.getChapterProgress(
          novelId: _novel,
          episodeId: _a,
        ),
        isNull,
      );
      await reader.onScrollOffsetChanged(100, bodySnapshot: _snapshot(_a, .1));
      await reader.saveCurrentProgressNow(fixture.state(_a).progressSnapshot);
      expect(
        (await fixture.repository.getChapterProgress(
          novelId: _novel,
          episodeId: _a,
        ))!.progressPercent,
        .1,
      );
    },
  );

  test(
    'source return after a chapter switch cannot revive the old chapter',
    () async {
      await fixture.repository.commitProgress(progress: _position(_a, .4));
      final reader = await fixture.open(_a);
      final handoff = reader.beginSourceReadingHandoff()!;
      expect(await reader.openEpisodeFromCatalog(_b), true);
      await fixture.repository.commitProgress(progress: _position(_a, .9));
      await reader.acceptSourceReadingReturn(handoff);
      expect(fixture.state(_a).currentEpisode.episodeId, _b);
      expect(fixture.state(_a).progressSnapshot.progressPercent, 0);
    },
  );

  test(
    'failed source refresh keeps passive exit read-only but allows new reading',
    () async {
      await fixture.repository.commitProgress(progress: _position(_a, .2));
      final reader = await fixture.open(_a);
      final handoff = reader.beginSourceReadingHandoff()!;
      await fixture.repository.commitProgress(progress: _position(_a, .8));
      fixture.repository.beforeLoadState = () async {
        throw StateError('controlled reading state failure');
      };
      await expectLater(
        reader.acceptSourceReadingReturn(handoff),
        throwsStateError,
      );
      fixture.repository.beforeLoadState = null;
      await reader.saveCurrentProgressNow(_snapshot(_a, .2));
      expect(
        (await fixture.repository.getChapterProgress(
          novelId: _novel,
          episodeId: _a,
        ))!.progressPercent,
        .8,
      );
      await reader.onScrollOffsetChanged(450, bodySnapshot: _snapshot(_a, .45));
      await reader.saveCurrentProgressNow(fixture.state(_a).progressSnapshot);
      expect(
        (await fixture.repository.getChapterProgress(
          novelId: _novel,
          episodeId: _a,
        ))!.progressPercent,
        .45,
      );
    },
  );

  test(
    'late source state load cannot replace a newer reader session',
    () async {
      await fixture.repository.commitProgress(progress: _position(_a, .2));
      final reader = await fixture.open(_a);
      final handoff = reader.beginSourceReadingHandoff()!;
      final entered = Completer<void>();
      final release = Completer<void>();
      fixture.repository.beforeLoadState = () async {
        entered.complete();
        await release.future;
      };
      final oldReturn = reader.acceptSourceReadingReturn(handoff);
      await entered.future;
      fixture.repository.beforeLoadState = null;
      expect(await reader.openEpisodeFromCatalog(_b), true);
      release.complete();
      await oldReturn;
      expect(fixture.state(_a).currentEpisode.episodeId, _b);
      expect(fixture.state(_a).progressSnapshot.progressPercent, 0);
    },
  );
}

NovelReadingProgress _position(String episode, double fraction) =>
    NovelReadingProgress(
      novelId: _novel,
      episodeId: episode,
      scrollOffset: fraction * 1000,
      updatedAt: DateTime.fromMillisecondsSinceEpoch((fraction * 1000).round()),
      progressPercent: fraction,
      isProgressPercentValid: true,
      percentBasis: NovelProgressPercentBasis.bodyGeometryV1,
    );

NovelReaderProgressSnapshot _snapshot(String episode, double fraction) =>
    NovelReaderProgressSnapshot(
      novelId: _novel,
      episodeId: episode,
      flowMode: NovelReaderFlowMode.vertical,
      scrollOffset: fraction * 1000,
      pageIndex: 0,
      progressPercent: fraction,
      isProgressPercentValid: true,
      percentBasis: NovelProgressPercentBasis.bodyGeometryV1,
    );

class _Fixture {
  _Fixture(
    this.db,
    this.repository,
    this.preferences,
    this.container,
    this.committer,
  );
  final Database db;
  final _GatedLocalRepository repository;
  final _Preferences preferences;
  final ProviderContainer container;
  final DefaultNovelReaderProgressCommitter committer;
  final Map<String, ProviderSubscription<AsyncValue<NovelReaderViewState>>>
  _subscriptions = {};

  static Future<_Fixture> create({
    Duration debounceDuration = const Duration(minutes: 1),
  }) async {
    final db = await AppDatabase.open(databaseName: inMemoryDatabasePath);
    await seedNovelRepository(
      db,
      seed: const NovelSourceSeed(fid: '49', tid: '100'),
    );
    final repository = _GatedLocalRepository(Future.value(db));
    final preferences = _Preferences();
    final committer = DefaultNovelReaderProgressCommitter(
      repository: repository,
      debounceDuration: debounceDuration,
    );
    final container = ProviderContainer(
      overrides: [
        novelRepositoryProvider.overrideWithValue(repository),
        libraryStateRepositoryProvider.overrideWithValue(
          LocalLibraryStateRepository(Future.value(db)),
        ),
        novelReaderPreferencesRepositoryProvider.overrideWithValue(preferences),
        novelReaderDocumentBuildServiceProvider.overrideWithValue(
          const AdaptiveNovelReaderDocumentBuildService(
            parser: DiscuzNovelReaderDocumentParser(),
          ),
        ),
        novelReaderProgressCommitterProvider.overrideWithValue(committer),
      ],
    );
    return _Fixture(db, repository, preferences, container, committer);
  }

  NovelReaderArgs _args(String episode) =>
      NovelReaderArgs(novelId: _novel, episodeId: episode);
  Future<NovelReaderController> open(String episode) async {
    final provider = novelReaderControllerProvider(_args(episode));
    _subscriptions[episode] = container.listen(provider, (_, _) {});
    await container.read(provider.future);
    final controller = container.read(provider.notifier);
    controller.updateReadingVisibility(frontmost: true, resumed: true);
    return controller;
  }

  NovelReaderViewState state(String episode) => container
      .read(novelReaderControllerProvider(_args(episode)))
      .requireValue;
  void closeReader(String episode) {
    _subscriptions.remove(episode)?.close();
    container.invalidate(novelReaderControllerProvider(_args(episode)));
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions.values) {
      subscription.close();
    }
    container.dispose();
    committer.cancel();
    await Future<void>.delayed(Duration.zero);
    await db.close();
  }
}

class _Preferences implements NovelReaderPreferencesRepository {
  NovelReaderPreferences value = NovelReaderPreferences.defaults().copyWith(
    flowMode: NovelReaderFlowMode.vertical,
  );
  @override
  Future<NovelReaderPreferences> load() async => value;
  @override
  Future<void> save(NovelReaderPreferences preferences) async {
    value = preferences;
  }
}

class _GatedLocalRepository extends LocalNovelRepository {
  _GatedLocalRepository(super.dbFuture);
  Future<void> Function()? beforeCommit;
  void Function(bool)? afterCommit;
  Future<void> Function()? beforeReadStateMutation;
  Future<void> Function()? beforeLoadState;
  @override
  Future<NovelReadingStateSnapshot> loadWorkState({
    required String novelId,
  }) async {
    await beforeLoadState?.call();
    return super.loadWorkState(novelId: novelId);
  }

  @override
  Future<bool> setChapterRead({
    required String novelId,
    required String episodeId,
    required bool isRead,
    bool Function()? canCommit,
  }) async {
    await beforeReadStateMutation?.call();
    return super.setChapterRead(
      novelId: novelId,
      episodeId: episodeId,
      isRead: isRead,
      canCommit: canCommit,
    );
  }

  @override
  Future<bool> commitProgress({
    required NovelReadingProgress progress,
    bool markCompleted = false,
    bool Function()? canCommit,
  }) async {
    await beforeCommit?.call();
    final applied = await super.commitProgress(
      progress: progress,
      markCompleted: markCompleted,
      canCommit: canCommit,
    );
    afterCommit?.call(applied);
    return applied;
  }
}

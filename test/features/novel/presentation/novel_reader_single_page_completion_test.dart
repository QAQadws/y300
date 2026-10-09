import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/data/repositories/local_library_state_repository.dart';
import 'package:y300/features/novel/data/preferences/novel_chapter_interactions_dock_preferences_provider.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/data/repositories/local_novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_interactions_dock_preferences.dart';
import 'package:y300/features/novel/domain/models/novel_episode_open_policy.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/models/novel_reading_progress.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_chapter_interactions_dock_preferences_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_reading_state_repository.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_controller.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_progress_committer.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_html_paged_surface.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/novel_repository_seed.dart';

const _work = 'novel:49:100';
const _chapter = '$_work:5001';
const _next = '$_work:5003';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'the first fully readable single page completes after stability',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.create))!;
      try {
        await tester.pumpWidget(fixture.app());
        await _pumpSinglePageReady(tester);
        expect(
          (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
          isNot(true),
        );
        await tester.pump(const Duration(milliseconds: 249));
        expect(
          (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
          isNot(true),
        );
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump();
        final state = await fixture.load(tester);
        expect(state.episodeStates[_chapter]?.isRead, isTrue);
        expect(
          state.progressByEpisode[_chapter]!.isProgressPercentValid,
          isTrue,
        );
        expect(state.recentEpisodeId, _chapter);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'passive single-page restoration keeps unfinished history intact',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.create))!;
      try {
        await tester.runAsync(fixture.seedUnfinishedPosition);
        final before = (await tester.runAsync(
          () => fixture.db.query(AppDatabase.novelReadingProgressTable),
        ))!;
        await tester.pumpWidget(fixture.app());
        await _pumpSinglePageReady(tester);
        await tester.pump(const Duration(seconds: 1));
        final state = await fixture.load(tester);
        expect(state.episodeStates[_chapter]?.isRead, isNot(true));
        expect(state.progressByEpisode[_chapter]!.progressPercent, .42);
        final after = (await tester.runAsync(
          () => fixture.db.query(AppDatabase.novelReadingProgressTable),
        ))!;
        expect(after, before);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets('leaving before stability cannot complete a single page', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(_Fixture.create))!;
    final navigation = GlobalKey<NavigatorState>();
    try {
      await tester.pumpWidget(fixture.app(navigation: navigation));
      await _pumpSinglePageReady(tester);
      await tester.pump(const Duration(milliseconds: 100));
      unawaited(
        navigation.currentState!.push<void>(
          MaterialPageRoute(builder: (_) => const Scaffold()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
        isNot(true),
      );
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.close(tester);
    }
  });

  testWidgets(
    'turning to the next chapter preserves completed single-page state',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.create))!;
      try {
        await tester.pumpWidget(fixture.app());
        await _pumpSinglePageReady(tester);
        await tester.pump(const Duration(milliseconds: 300));
        await fixture.load(tester);
        await tester.drag(
          find.byKey(const Key('novel-reader-paged-page-view')),
          const Offset(-200, 0),
        );
        await _pumpSinglePageReady(tester, episode: _next, advanceTime: true);
        final state = await fixture.load(tester);
        expect(state.episodeStates[_chapter]?.isRead, isTrue);
        expect(state.progressByEpisode.containsKey(_chapter), isTrue);
        expect(_readerState(tester).currentEpisode.episodeId, _next);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'a real forward chapter swipe confirms a passively restored single page',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.create))!;
      try {
        await tester.runAsync(fixture.seedUnfinishedPosition);
        await tester.pumpWidget(fixture.app());
        await _pumpSinglePageReady(tester);
        await tester.pump(const Duration(seconds: 1));
        var state = await fixture.load(tester);
        expect(state.episodeStates[_chapter]?.isRead, isNot(true));
        expect(state.progressByEpisode[_chapter]!.progressPercent, .42);

        await tester.drag(
          find.byKey(const Key('novel-reader-paged-page-view')),
          const Offset(-200, 0),
        );
        await _pumpSinglePageReady(tester, episode: _next, advanceTime: true);
        state = await fixture.load(tester);
        expect(state.episodeStates[_chapter]?.isRead, isTrue);
        expect(_readerState(tester).currentEpisode.episodeId, _next);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'explicitly restarting a one-page chapter confirms its full body',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.create))!;
      try {
        await tester.runAsync(fixture.seedUnfinishedPosition);
        await tester.pumpWidget(
          fixture.app(openPolicy: NovelEpisodeOpenPolicy.startAtBeginning),
        );
        await _pumpSinglePageReady(tester);
        await tester.pump(const Duration(milliseconds: 300));
        final state = await fixture.load(tester);
        expect(state.episodeStates[_chapter]?.isRead, isTrue);
        expect(state.progressByEpisode[_chapter]!.progressPercent, 0);
        expect(state.recentEpisodeId, _chapter);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'a failed completion refresh reports an error and permits chapter-turn retry',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.create))!;
      try {
        await tester.pumpWidget(fixture.app());
        await _pumpSinglePageReady(tester);
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
          isTrue,
        );
        // Target the additional edge reconciliation read rather than the
        // initial completion write's asynchronous read-model publication.
        await _pumpUntil(
          tester,
          () =>
              _readerState(
                tester,
              ).readingState?.episodeStates[_chapter]?.isRead ==
              true,
        );
        final failureMessage = AppLocalizations.of(
          tester.element(find.byType(NovelReaderPage)),
        ).novelSaveReadingProgressFailed;
        fixture.repository.failNextStateRead = true;

        await tester.drag(
          find.byKey(const Key('novel-reader-paged-page-view')),
          const Offset(-200, 0),
        );
        await _pumpUntil(
          tester,
          () => fixture.repository.injectedStateReadFailures == 1,
        );
        await tester.pump(const Duration(milliseconds: 260));
        expect(_readerState(tester).currentEpisode.episodeId, _chapter);
        expect(find.text(failureMessage), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(
          (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
          isTrue,
        );

        await tester.drag(
          find.byKey(const Key('novel-reader-paged-page-view')),
          const Offset(-200, 0),
        );
        await _pumpSinglePageReady(tester, episode: _next, advanceTime: true);
        expect(_readerState(tester).currentEpisode.episodeId, _next);
        expect(
          (await fixture.load(tester)).episodeStates[_chapter]?.isRead,
          isTrue,
        );
        expect(fixture.repository.injectedStateReadFailures, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
  );
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var frame = 0; frame < 250; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump();
    if (ready()) return;
  }
  fail('The asynchronous reading-state boundary did not become ready');
}

Future<void> _pumpSinglePageReady(
  WidgetTester tester, {
  String episode = _chapter,
  bool advanceTime = false,
}) async {
  for (var frame = 0; frame < 250; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(
      advanceTime ? const Duration(milliseconds: 16) : Duration.zero,
    );
    final surface = find.byType(NovelReaderHtmlPagedSurface);
    final pageView = find.byKey(const Key('novel-reader-paged-page-view'));
    if (surface.evaluate().isNotEmpty &&
        pageView.evaluate().isNotEmpty &&
        _readerState(tester).currentEpisode.episodeId == episode &&
        tester.widget<NovelReaderHtmlPagedSurface>(surface).episode.episodeId ==
            episode &&
        tester
                .widget<NovelReaderHtmlPagedSurface>(surface)
                .paginationCache!
                .length >
            0) {
      expect(
        tester.widget<PageView>(pageView).childrenDelegate.estimatedChildCount,
        1,
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      return;
    }
  }
  fail('A final readable single-page chapter did not become ready');
}

NovelReaderViewState _readerState(WidgetTester tester) {
  final reader = tester.widget<NovelReaderPage>(find.byType(NovelReaderPage));
  return ProviderScope.containerOf(
        tester.element(find.byType(NovelReaderPage)),
        listen: false,
      )
      .read(
        novelReaderControllerProvider(
          NovelReaderArgs(
            novelId: reader.novelId,
            episodeId: reader.initialEpisodeId,
            openPolicy: reader.openPolicy,
          ),
        ),
      )
      .requireValue;
}

final class _Fixture {
  _Fixture(this.db, this.repository, this.committer);
  final Database db;
  final _ReadFailureRepository repository;
  final DefaultNovelReaderProgressCommitter committer;

  static Future<_Fixture> create() async {
    final db = await AppDatabase.open(databaseName: inMemoryDatabasePath);
    await seedNovelRepository(
      db,
      seed: const NovelSourceSeed(fid: '49', tid: '100'),
      coverImageUrl: null,
    );
    final repository = _ReadFailureRepository(Future.value(db));
    return _Fixture(
      db,
      repository,
      DefaultNovelReaderProgressCommitter(repository: repository),
    );
  }

  Widget app({
    GlobalKey<NavigatorState>? navigation,
    NovelEpisodeOpenPolicy openPolicy = NovelEpisodeOpenPolicy.resumeLastRead,
  }) => ProviderScope(
    overrides: [
      novelRepositoryProvider.overrideWithValue(repository),
      libraryStateRepositoryProvider.overrideWithValue(
        LocalLibraryStateRepository(Future.value(db)),
      ),
      novelReaderProgressCommitterProvider.overrideWithValue(committer),
      novelReaderPreferencesRepositoryProvider.overrideWithValue(
        _Preferences(),
      ),
      novelChapterInteractionsDockPreferencesRepositoryProvider
          .overrideWithValue(_DisabledDock()),
      forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
      imageCacheServiceProvider.overrideWithValue(_UnusedImageCache()),
    ],
    child: LocalizedTestApp(
      navigatorKey: navigation,
      home: NovelReaderPage(
        novelId: _work,
        initialEpisodeId: _chapter,
        openPolicy: openPolicy,
      ),
    ),
  );

  Future<void> seedUnfinishedPosition() async {
    await repository.commitProgress(
      progress: NovelReadingProgress(
        novelId: _work,
        episodeId: _chapter,
        scrollOffset: 123,
        progressPercent: .42,
        isProgressPercentValid: true,
        percentBasis: NovelProgressPercentBasis.bodyGeometryV1,
        updatedAt: DateTime.utc(2026, 10, 9),
      ),
    );
  }

  Future<NovelReadingStateSnapshot> load(WidgetTester tester) async {
    NovelReadingStateSnapshot? result;
    Object? failure;
    unawaited(
      repository
          .loadWorkState(novelId: _work)
          .then<void>(
            (value) {
              result = value;
            },
            onError: (Object error, StackTrace _) {
              failure = error;
            },
          ),
    );
    // An application transaction can be waiting for a continuation in the
    // widget's fake-async zone. Keep pumping it while SQLite's isolate replies;
    // awaiting this query from runAsync would park that continuation.
    for (
      var frame = 0;
      frame < 500 && result == null && failure == null;
      frame++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump();
    }
    if (failure != null) throw failure!;
    expect(
      result,
      isNotNull,
      reason: 'SQLite reading-state query did not finish',
    );
    return result!;
  }

  Future<void> close(WidgetTester tester) async {
    repository.failNextStateRead = false;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    committer.cancel();
    await load(tester);
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
      await db.close();
    });
  }
}

final class _ReadFailureRepository extends LocalNovelRepository {
  _ReadFailureRepository(super.dbFuture);
  bool failNextStateRead = false;
  int injectedStateReadFailures = 0;

  @override
  Future<NovelReadingStateSnapshot> loadWorkState({required String novelId}) {
    if (failNextStateRead) {
      failNextStateRead = false;
      injectedStateReadFailures++;
      return Future.error(StateError('Controlled completion refresh failure'));
    }
    return super.loadWorkState(novelId: novelId);
  }
}

final class _Preferences implements NovelReaderPreferencesRepository {
  var preferences = NovelReaderPreferences.defaults().copyWith(
    flowMode: NovelReaderFlowMode.pagedLtr,
  );
  @override
  Future<NovelReaderPreferences> load() async => preferences;
  @override
  Future<void> save(NovelReaderPreferences value) async => preferences = value;
}

final class _DisabledDock
    implements NovelChapterInteractionsDockPreferencesRepository {
  @override
  Future<NovelChapterInteractionsDockPreferences> load() async =>
      const NovelChapterInteractionsDockPreferences(enabled: false);
  @override
  Future<void> save(NovelChapterInteractionsDockPreferences value) async {}
}

final class _UnusedImageCache implements ImageCacheService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected image-cache call: ${invocation.memberName}');
}

import 'dart:async';

import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/favorites/data/services/favorite_sync_request_governor.dart';
import 'package:y300/features/history/data/providers/history_providers.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/services/history_visit_recorder.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/domain/models/novel_episode_open_policy.dart';
import 'package:y300/features/novel/domain/models/novel_interaction_models.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/novel/domain/repositories/novel_source_state_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_interaction_preferences_repository.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_source_route_resolver.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_sync_service.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_update_service.dart';
import 'package:y300/features/novel/presentation/novel_detail_page.dart';
import 'package:y300/features/novel/presentation/novel_reader_page.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'NovelDetailPage renders unified detail header and chapter list',
    (tester) async {
      final historyRecorder = _RecordingHistoryVisitRecorder();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            historyVisitRecorderProvider.overrideWithValue(historyRecorder),
            novelRepositoryProvider.overrideWithValue(_FakeNovelRepository()),
            libraryStateRepositoryProvider.overrideWithValue(
              _FakeLibraryStateRepository(),
            ),
            novelSourceStateRepositoryProvider.overrideWithValue(
              const _EmptyNovelSourceStateRepository(),
            ),
            novelInteractionPreferencesRepositoryProvider.overrideWithValue(
              _MemoryNovelInteractionPreferencesRepository(),
            ),
            imageCacheServiceProvider.overrideWithValue(
              _NoopImageCacheService(),
            ),
          ],
          child: const LocalizedTestApp(
            home: NovelDetailPage(novelId: 'novel:1'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Test Novel'), findsAtLeastNWidgets(1));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('unified-detail-chapter-novel:1:e1')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const ValueKey<String>('unified-detail-chapter-novel:1:e1')),
        findsOneWidget,
      );
      expect(find.textContaining('Pid:5001'), findsOneWidget);
      expect(
        find.byKey(const Key('unified-detail-appbar-download')),
        findsNothing,
      );
      expect(find.byTooltip('下载该章节'), findsNothing);
      await tester.tap(find.byKey(const Key('unified-detail-appbar-filter')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('unified-detail-filter-downloaded')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('unified-detail-filter-unread')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('unified-detail-filter-bookmarked')),
        findsOneWidget,
      );
      Navigator.of(
        tester.element(
          find.byKey(const Key('unified-detail-chapter-filter-sheet')),
        ),
      ).pop();
      await tester.pumpAndSettle();

      await tester.longPress(
        find.byKey(const ValueKey<String>('unified-detail-chapter-novel:1:e1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('取消全部已读'), findsNothing);
      expect(find.text('添加书签'), findsOneWidget);
      Navigator.of(tester.element(find.text('添加书签'))).pop();
      await tester.pumpAndSettle();
      expect(historyRecorder.drafts, hasLength(1));
      expect(
        historyRecorder.drafts.single.target,
        const HistoryTargetKey(type: HistoryTargetType.novel, id: 'novel:1'),
      );
      expect(historyRecorder.drafts.single.title, 'Test Novel');
      expect(historyRecorder.drafts.single.sourceTid, '100');
    },
  );

  testWidgets('NovelDetailPage only renders publisher metadata', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyVisitRecorderProvider.overrideWithValue(
            const _NoopHistoryVisitRecorder(),
          ),
          novelRepositoryProvider.overrideWithValue(_FakeNovelRepository()),
          libraryStateRepositoryProvider.overrideWithValue(
            _FakeLibraryStateRepository(),
          ),
          novelSourceStateRepositoryProvider.overrideWithValue(
            const _EmptyNovelSourceStateRepository(),
          ),
          novelInteractionPreferencesRepositoryProvider.overrideWithValue(
            _MemoryNovelInteractionPreferencesRepository(),
          ),
          imageCacheServiceProvider.overrideWithValue(_NoopImageCacheService()),
        ],
        child: const LocalizedTestApp(
          home: NovelDetailPage(novelId: 'novel:1'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('unified-detail-plain-header')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('unified-detail-author-row')), findsNothing);
    expect(find.byKey(const Key('unified-detail-group-row')), findsNothing);
    expect(
      find.byKey(const Key('unified-detail-publisher-row')),
      findsOneWidget,
    );
    expect(find.text('Author A'), findsOneWidget);
    expect(find.textContaining('UID:'), findsNothing);
    expect(
      find.byKey(const Key('unified-detail-header-gradient')),
      findsNothing,
    );
  });

  testWidgets('NovelDetailPage exposes novel metadata and cover actions', (
    tester,
  ) async {
    await _pumpNovelDetail(
      tester,
      preferences: _MemoryNovelInteractionPreferencesRepository(),
      routeResolver: _FakeNovelChapterSourceRouteResolver.success(),
    );

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('unified-detail-edit-metadata')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('unified-detail-set-cover')), findsOneWidget);

    await tester.tap(find.byKey(const Key('unified-detail-edit-metadata')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('unified-detail-custom-author-input')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('unified-detail-custom-group-input')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('unified-detail-custom-search-title-input')),
      findsNothing,
    );
  });

  testWidgets('metadata remains visible while first chapters hydrate', (
    tester,
  ) async {
    final sourceRepository = _HydrationNovelSourceStateRepository();
    final syncService = _ControlledNovelChapterSyncService();
    final historyRecorder = _RecordingHistoryVisitRecorder();
    addTearDown(syncService.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyVisitRecorderProvider.overrideWithValue(historyRecorder),
          novelRepositoryProvider.overrideWithValue(_FakeNovelRepository()),
          libraryStateRepositoryProvider.overrideWithValue(
            _FakeLibraryStateRepository(),
          ),
          novelSourceStateRepositoryProvider.overrideWithValue(
            sourceRepository,
          ),
          novelChapterSyncServiceProvider.overrideWithValue(syncService),
          novelInteractionPreferencesRepositoryProvider.overrideWithValue(
            _MemoryNovelInteractionPreferencesRepository(),
          ),
          imageCacheServiceProvider.overrideWithValue(_NoopImageCacheService()),
        ],
        child: const LocalizedTestApp(
          home: NovelDetailPage(novelId: 'novel:1'),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Test Novel'), findsAtLeastNWidgets(1));
    expect(
      find.byKey(const Key('novel-chapter-hydration-panel')),
      findsOneWidget,
    );
    expect(find.textContaining('正在加载第 1/2 页'), findsOneWidget);
    expect(syncService.request?.publisherId, '406769');
    expect(syncService.request?.mode, NovelChapterSyncMode.initialFull);
    expect(historyRecorder.drafts, hasLength(1));

    syncService.complete();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('novel-chapter-hydration-panel')),
      findsNothing,
    );
    expect(historyRecorder.drafts, hasLength(1));
  });

  testWidgets('chapter open mode selection is persisted globally', (
    tester,
  ) async {
    final preferences = _MemoryNovelInteractionPreferencesRepository();
    await _pumpNovelDetail(
      tester,
      preferences: preferences,
      routeResolver: _FakeNovelChapterSourceRouteResolver.success(),
    );

    final control = find.byKey(const Key('novel-chapter-open-mode-control'));
    await tester.scrollUntilVisible(
      control,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final segmentedButton = tester
        .widget<SegmentedButton<NovelChapterOpenMode>>(control);
    expect(
      segmentedButton.style?.minimumSize?.resolve(<WidgetState>{}),
      const Size(0, 36),
    );
    final shape = segmentedButton.style?.shape?.resolve(<WidgetState>{});
    expect(shape, isA<RoundedRectangleBorder>());
    expect(
      (shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(8),
    );
    expect(
      find.descendant(of: control, matching: find.byIcon(Icons.book_outlined)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: control,
        matching: find.byIcon(Icons.chat_bubble_outline),
      ),
      findsOneWidget,
    );
    await tester.tap(find.descendant(of: control, matching: find.text('原帖')));
    await tester.pumpAndSettle();

    expect(preferences.mode, NovelChapterOpenMode.sourcePost);
  });

  testWidgets('source-post mode opens located ordinary page and target PID', (
    tester,
  ) async {
    final preferences = _MemoryNovelInteractionPreferencesRepository(
      NovelChapterOpenMode.sourcePost,
    );
    final resolver = _FakeNovelChapterSourceRouteResolver.success(page: 7);
    final libraryState = _FakeLibraryStateRepository();
    await _pumpNovelDetail(
      tester,
      preferences: preferences,
      routeResolver: resolver,
      libraryStateRepository: libraryState,
      threadRepository: _FakeThreadRepository(),
    );

    await _scrollNovelChapterIntoTapArea(tester);
    await tester.tap(find.text('Chapter 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final threadPage = tester.widget<ThreadDetailPage>(
      find.byType(ThreadDetailPage),
    );
    expect(threadPage.tid, '100');
    expect(threadPage.initialPage, 7);
    expect(threadPage.targetPid, '5001');
    expect(resolver.lastReference?.tid, '100');
    expect(resolver.lastReference?.pid, '5001');
    expect(libraryState.readMutationCount, 0);
  });

  testWidgets('continue honors source-post mode for the last-read chapter', (
    tester,
  ) async {
    final resolver = _FakeNovelChapterSourceRouteResolver.success(page: 6);
    await _pumpNovelDetail(
      tester,
      preferences: _MemoryNovelInteractionPreferencesRepository(
        NovelChapterOpenMode.sourcePost,
      ),
      routeResolver: resolver,
      repository: _FakeNovelRepository(
        progress: NovelReadingProgress(
          novelId: 'novel:1',
          episodeId: 'novel:1:e1',
          scrollOffset: 88,
          updatedAt: DateTime(2026, 7, 15),
        ),
      ),
      threadRepository: _FakeThreadRepository(),
    );

    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    final threadPage = tester.widget<ThreadDetailPage>(
      find.byType(ThreadDetailPage),
    );
    expect(threadPage.initialPage, 6);
    expect(threadPage.targetPid, '5001');
    expect(resolver.lastReference?.pid, '5001');
  });

  testWidgets('reader mode keeps opening chapters in NovelReaderPage', (
    tester,
  ) async {
    final resolver = _FakeNovelChapterSourceRouteResolver.success();
    await _pumpNovelDetail(
      tester,
      preferences: _MemoryNovelInteractionPreferencesRepository(),
      routeResolver: resolver,
    );

    await _scrollNovelChapterIntoTapArea(tester);
    await tester.tap(find.text('Chapter 1'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(NovelReaderPage), findsOneWidget);
    expect(
      tester.widget<NovelReaderPage>(find.byType(NovelReaderPage)).openPolicy,
      NovelEpisodeOpenPolicy.startAtBeginning,
    );
    expect(resolver.callCount, 0);
  });

  testWidgets('continue resumes the single last-read progress', (tester) async {
    await _pumpNovelDetail(
      tester,
      preferences: _MemoryNovelInteractionPreferencesRepository(),
      routeResolver: _FakeNovelChapterSourceRouteResolver.success(),
      repository: _FakeNovelRepository(
        progress: NovelReadingProgress(
          novelId: 'novel:1',
          episodeId: 'novel:1:e1',
          scrollOffset: 88,
          updatedAt: DateTime(2026, 7, 21),
        ),
      ),
    );

    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<NovelReaderPage>(find.byType(NovelReaderPage)).openPolicy,
      NovelEpisodeOpenPolicy.resumeLastRead,
    );
  });

  testWidgets('the chapter marked last-read resumes its progress', (
    tester,
  ) async {
    await _pumpNovelDetail(
      tester,
      preferences: _MemoryNovelInteractionPreferencesRepository(),
      routeResolver: _FakeNovelChapterSourceRouteResolver.success(),
      repository: _FakeNovelRepository(
        progress: NovelReadingProgress(
          novelId: 'novel:1',
          episodeId: 'novel:1:e1',
          scrollOffset: 88,
          updatedAt: DateTime(2026, 7, 21),
        ),
      ),
    );

    await _scrollNovelChapterIntoTapArea(tester);
    await tester.tap(find.text('Chapter 1'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<NovelReaderPage>(find.byType(NovelReaderPage)).openPolicy,
      NovelEpisodeOpenPolicy.resumeLastRead,
    );
  });

  testWidgets('source route failure offers opening the thread home', (
    tester,
  ) async {
    final resolver = _FakeNovelChapterSourceRouteResolver.failure();
    await _pumpNovelDetail(
      tester,
      preferences: _MemoryNovelInteractionPreferencesRepository(
        NovelChapterOpenMode.sourcePost,
      ),
      routeResolver: resolver,
      threadRepository: _FakeThreadRepository(),
    );

    await _scrollNovelChapterIntoTapArea(tester);
    await tester.tap(find.text('Chapter 1'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('novel-source-route-failure-dialog')),
      findsOneWidget,
    );
    expect(find.text('原帖楼层定位失败：test_failure'), findsOneWidget);
    expect(
      find.byKey(const Key('novel-source-route-open-thread-home')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('novel-source-route-open-thread-home')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final threadPage = tester.widget<ThreadDetailPage>(
      find.byType(ThreadDetailPage),
    );
    expect(threadPage.tid, '100');
    expect(threadPage.initialPage, isNull);
    expect(threadPage.targetPid, isNull);
  });

  testWidgets('continue opens the first chapter in source-post mode', (
    tester,
  ) async {
    final resolver = _FakeNovelChapterSourceRouteResolver.success();
    await _pumpNovelDetail(
      tester,
      preferences: _MemoryNovelInteractionPreferencesRepository(
        NovelChapterOpenMode.sourcePost,
      ),
      routeResolver: resolver,
      threadRepository: _FakeThreadRepository(),
    );

    await tester.tap(find.text('继续'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ThreadDetailPage), findsOneWidget);
    expect(find.byType(NovelReaderPage), findsNothing);
    expect(resolver.callCount, 1);
  });

  testWidgets('only a header long press requests a full chapter update', (
    tester,
  ) async {
    final updateService = _RecordingNovelChapterUpdateService();
    await _pumpNovelDetail(
      tester,
      preferences: _MemoryNovelInteractionPreferencesRepository(),
      routeResolver: _FakeNovelChapterSourceRouteResolver.success(),
      chapterUpdateService: updateService,
    );

    final headerUpdate = find.byKey(const Key('unified-detail-header-update'));
    await tester.tap(headerUpdate);
    await tester.pumpAndSettle();

    await tester.longPress(headerUpdate);
    await tester.pumpAndSettle();

    final refreshIndicator = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    await refreshIndicator.onRefresh();
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刷新'));
    await tester.pumpAndSettle();

    expect(updateService.novelIds, <String>[
      'novel:1',
      'novel:1',
      'novel:1',
      'novel:1',
    ]);
    expect(updateService.intents, <NovelChapterUpdateIntent>[
      NovelChapterUpdateIntent.normal,
      NovelChapterUpdateIntent.full,
      NovelChapterUpdateIntent.normal,
      NovelChapterUpdateIntent.normal,
    ]);
  });

  testWidgets('refresh gestures share one in-flight detail update', (
    tester,
  ) async {
    final updateService = _BlockingNovelChapterUpdateService();
    await _pumpNovelDetail(
      tester,
      preferences: _MemoryNovelInteractionPreferencesRepository(),
      routeResolver: _FakeNovelChapterSourceRouteResolver.success(),
      chapterUpdateService: updateService,
    );

    await tester.longPress(
      find.byKey(const Key('unified-detail-header-update')),
    );
    await tester.pump();
    final refreshIndicator = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    final duplicate = refreshIndicator.onRefresh();

    expect(updateService.intents, <NovelChapterUpdateIntent>[
      NovelChapterUpdateIntent.full,
    ]);

    updateService.complete();
    await duplicate;
    await tester.pumpAndSettle();
    expect(updateService.intents, hasLength(1));
  });
}

Future<void> _pumpNovelDetail(
  WidgetTester tester, {
  required _MemoryNovelInteractionPreferencesRepository preferences,
  required _FakeNovelChapterSourceRouteResolver routeResolver,
  _FakeNovelRepository? repository,
  _FakeLibraryStateRepository? libraryStateRepository,
  ThreadRepository? threadRepository,
  NovelChapterUpdateService? chapterUpdateService,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        historyVisitRecorderProvider.overrideWithValue(
          const _NoopHistoryVisitRecorder(),
        ),
        novelRepositoryProvider.overrideWithValue(
          repository ?? _FakeNovelRepository(),
        ),
        libraryStateRepositoryProvider.overrideWithValue(
          libraryStateRepository ?? _FakeLibraryStateRepository(),
        ),
        novelSourceStateRepositoryProvider.overrideWithValue(
          const _EmptyNovelSourceStateRepository(),
        ),
        novelInteractionPreferencesRepositoryProvider.overrideWithValue(
          preferences,
        ),
        novelChapterSourceRouteResolverProvider.overrideWithValue(
          routeResolver,
        ),
        imageCacheServiceProvider.overrideWithValue(_NoopImageCacheService()),
        if (chapterUpdateService != null)
          novelChapterUpdateServiceProvider.overrideWithValue(
            chapterUpdateService,
          ),
        if (threadRepository != null)
          threadRepositoryProvider.overrideWithValue(threadRepository),
      ],
      child: const LocalizedTestApp(home: NovelDetailPage(novelId: 'novel:1')),
    ),
  );
  await tester.pumpAndSettle();
}

class _RecordingHistoryVisitRecorder implements HistoryVisitRecorder {
  final List<HistoryVisitDraft> drafts = <HistoryVisitDraft>[];

  @override
  Future<void> record(HistoryVisitDraft draft) async {
    drafts.add(draft);
  }
}

class _NoopHistoryVisitRecorder implements HistoryVisitRecorder {
  const _NoopHistoryVisitRecorder();

  @override
  Future<void> record(HistoryVisitDraft draft) async {}
}

Future<void> _scrollNovelChapterIntoTapArea(WidgetTester tester) async {
  final chapter = find.byKey(
    const ValueKey<String>('unified-detail-chapter-novel:1:e1'),
  );
  await tester.scrollUntilVisible(
    chapter,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
  await tester.pumpAndSettle();
}

class _MemoryNovelInteractionPreferencesRepository
    implements NovelInteractionPreferencesRepository {
  _MemoryNovelInteractionPreferencesRepository([
    this.mode = NovelChapterOpenMode.reader,
  ]);

  NovelChapterOpenMode mode;

  @override
  Future<NovelChapterOpenMode> loadChapterOpenMode() async => mode;

  @override
  Future<void> saveChapterOpenMode(NovelChapterOpenMode mode) async {
    this.mode = mode;
  }
}

class _FakeNovelChapterSourceRouteResolver
    implements NovelChapterSourceRouteResolver {
  _FakeNovelChapterSourceRouteResolver._({this.route, this.error});

  factory _FakeNovelChapterSourceRouteResolver.success({int page = 7}) {
    return _FakeNovelChapterSourceRouteResolver._(
      route: NovelChapterSourceRoute(
        tid: '100',
        pid: '5001',
        page: page,
        url: 'https://bbs.yamibo.com/thread-100-$page-1.html#pid5001',
      ),
    );
  }

  factory _FakeNovelChapterSourceRouteResolver.failure() {
    return _FakeNovelChapterSourceRouteResolver._(
      error: const NovelChapterSourceRouteException(
        NovelChapterSourceRouteFailureCode.locatorFailed,
        detail: 'test_failure',
      ),
    );
  }

  final NovelChapterSourceRoute? route;
  final NovelChapterSourceRouteException? error;
  NovelChapterSourceReference? lastReference;
  int callCount = 0;

  @override
  Future<NovelChapterSourceRoute> resolve(
    NovelChapterSourceReference reference,
  ) async {
    callCount++;
    lastReference = reference;
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return route!;
  }
}

class _FakeThreadRepository implements ThreadRepository {
  @override
  ThreadDetailSourceCapabilities get capabilities =>
      ThreadDetailSourceCapabilities.full;

  @override
  Future<DataReadResult<ThreadDetailData, ThreadDetailReadCapabilities>>
  getThreadDetail({
    required String tid,
    int page = 1,
    ThreadDetailQuery query = const ThreadDetailQuery(),
  }) async {
    return DataReadSuccess<ThreadDetailData, ThreadDetailReadCapabilities>(
      data: ThreadDetailData(
        tid: tid,
        fid: '49',
        subject: '来源帖子',
        author: 'Author A',
        replies: 1,
        views: 1,
        currentPage: page,
        perPage: 20,
        posts: <ThreadPost>[
          ThreadPost(
            pid: '5001',
            author: 'Author A',
            authorId: '406769',
            message: '<p>来源正文</p>',
            number: 1,
            isFirst: false,
            dateline: '2026-01-01',
          ),
        ],
      ),
      capabilities: capabilities.toReadCapabilities(),
      metadata: const DataReadMetadata.network(),
    );
  }
}

class _EmptyNovelSourceStateRepository implements NovelSourceStateRepository {
  const _EmptyNovelSourceStateRepository();

  @override
  Future<NovelSourceState?> getSourceState({required String novelId}) async {
    return _sourceState(
      novelId: novelId,
      hydrationState: NovelChapterHydrationState.ready,
    );
  }

  @override
  Future<void> saveMetadata(NovelSourceMetadata metadata) async {}

  @override
  Future<void> saveCheckpoint(NovelChapterSyncCheckpoint checkpoint) async {}

  @override
  Future<void> setHydrationState({
    required String novelId,
    required NovelChapterHydrationState state,
    String? lastError,
    DateTime? chaptersHydratedAt,
  }) async {}
}

class _HydrationNovelSourceStateRepository
    implements NovelSourceStateRepository {
  NovelSourceState state = _sourceState(
    novelId: 'novel:1',
    hydrationState: NovelChapterHydrationState.metadataOnly,
  );

  @override
  Future<NovelSourceState?> getSourceState({required String novelId}) async {
    return state;
  }

  @override
  Future<void> saveCheckpoint(NovelChapterSyncCheckpoint checkpoint) async {}

  @override
  Future<void> saveMetadata(NovelSourceMetadata metadata) async {}

  @override
  Future<void> setHydrationState({
    required String novelId,
    required NovelChapterHydrationState state,
    String? lastError,
    DateTime? chaptersHydratedAt,
  }) async {}
}

class _ControlledNovelChapterSyncService implements NovelChapterSyncService {
  final StreamController<NovelChapterSyncProgress> _progress =
      StreamController<NovelChapterSyncProgress>.broadcast();
  final Completer<void> _completion = Completer<void>();
  NovelChapterSyncRequest? request;
  bool _active = false;

  @override
  bool hasActiveRun(String novelId) => _active;

  @override
  Future<NovelChapterSyncResult> synchronize(
    NovelChapterSyncRequest request,
  ) async {
    this.request = request;
    _active = true;
    _progress.add(
      NovelChapterSyncProgress(
        runId: 'widget-run',
        novelId: request.novelId,
        mode: request.mode,
        phase: NovelChapterSyncPhase.fetchingPage,
        currentPage: 1,
        totalPages: 2,
        acceptedCount: 1,
      ),
    );
    await _completion.future;
    _active = false;
    final checkpoint = NovelChapterSyncCheckpoint(
      novelId: request.novelId,
      publisherId: request.publisherId,
      lastCompletedAuthorPage: 2,
      lastSeenPid: '5001',
      completedAt: DateTime(2026, 7, 13),
    );
    _progress.add(
      NovelChapterSyncProgress(
        runId: 'widget-run',
        novelId: request.novelId,
        mode: request.mode,
        phase: NovelChapterSyncPhase.completed,
        currentPage: 2,
        totalPages: 2,
        acceptedCount: 1,
      ),
    );
    return NovelChapterSyncResult(
      mode: request.mode,
      fetchedPages: 2,
      insertedCount: 1,
      updatedCount: 0,
      totalCount: 1,
      checkpoint: checkpoint,
    );
  }

  @override
  Stream<NovelChapterSyncProgress> watchProgress(String novelId) {
    return _progress.stream;
  }

  void complete() => _completion.complete();

  Future<void> dispose() => _progress.close();
}

class _RecordingNovelChapterUpdateService implements NovelChapterUpdateService {
  final List<String> novelIds = <String>[];
  final List<NovelChapterUpdateIntent> intents = <NovelChapterUpdateIntent>[];

  @override
  Future<NovelChapterSyncResult> update(
    String novelId, {
    NovelChapterUpdateIntent intent = NovelChapterUpdateIntent.normal,
  }) async {
    novelIds.add(novelId);
    intents.add(intent);
    return NovelChapterSyncResult(
      mode: intent == NovelChapterUpdateIntent.full
          ? NovelChapterSyncMode.fullRefresh
          : NovelChapterSyncMode.incremental,
      fetchedPages: 1,
      insertedCount: 0,
      updatedCount: 1,
      totalCount: 1,
      checkpoint: NovelChapterSyncCheckpoint(
        novelId: novelId,
        publisherId: '406769',
        lastCompletedAuthorPage: 1,
        lastSeenPid: '5001',
        completedAt: DateTime(2026, 7, 14),
      ),
    );
  }
}

class _BlockingNovelChapterUpdateService implements NovelChapterUpdateService {
  final Completer<NovelChapterSyncResult> _completion =
      Completer<NovelChapterSyncResult>();
  final List<NovelChapterUpdateIntent> intents = <NovelChapterUpdateIntent>[];

  @override
  Future<NovelChapterSyncResult> update(
    String novelId, {
    NovelChapterUpdateIntent intent = NovelChapterUpdateIntent.normal,
  }) {
    intents.add(intent);
    return _completion.future;
  }

  void complete() {
    _completion.complete(
      NovelChapterSyncResult(
        mode: NovelChapterSyncMode.fullRefresh,
        fetchedPages: 1,
        insertedCount: 0,
        updatedCount: 1,
        totalCount: 1,
        checkpoint: NovelChapterSyncCheckpoint(
          novelId: 'novel:1',
          publisherId: '406769',
          lastCompletedAuthorPage: 1,
          lastSeenPid: '5001',
          completedAt: DateTime(2026, 7, 14),
        ),
      ),
    );
  }
}

NovelSourceState _sourceState({
  required String novelId,
  required NovelChapterHydrationState hydrationState,
}) {
  return NovelSourceState(
    novelId: novelId,
    publisherId: '406769',
    publisherName: 'Author A',
    firstPostPid: '5000',
    sourceIntro: '来源简介',
    catalogEntries: const <NovelSourceCatalogEntry>[],
    metadataSourceVersion: 4,
    hydrationState: hydrationState,
    metadataIngestedAt: DateTime(2026, 7, 13),
    chaptersHydratedAt: hydrationState == NovelChapterHydrationState.ready
        ? DateTime(2026, 7, 13)
        : null,
    lastCompletedAuthorPage: hydrationState == NovelChapterHydrationState.ready
        ? 1
        : 0,
    lastSeenPid: null,
    lastSyncAt: hydrationState == NovelChapterHydrationState.ready
        ? DateTime(2026, 7, 13)
        : null,
    lastError: null,
  );
}

class _NoopImageCacheService implements ImageCacheService {
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: 'memory://${request.cacheKey}',
      fromCache: true,
    );
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: request.sourcePath,
      fromCache: true,
    );
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async => 0;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }

  @override
  Future<void> clearUnprotected() async {}
}

class _FakeNovelRepository implements NovelRepository {
  _FakeNovelRepository({this.progress});

  final NovelReadingProgress? progress;

  @override
  Future<String> createCategory({required String name}) async => 'created';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<List<NovelShelfCategory>> getCategories() async {
    return [
      NovelShelfCategory(
        categoryId: 'default',
        name: 'Default',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<NovelChapterContent?> getChapterContent({
    required String episodeId,
  }) async => null;

  @override
  Future<NovelItem?> getDetail({required String novelId}) async {
    return NovelItem(
      novelId: novelId,
      sourceTid: '100',
      sourceFid: '49',
      title: 'Test Novel',
      author: 'Author A',
      coverImageUrl: null,
      updatedAt: DateTime(2026, 1, 1),
      episodeCount: 1,
      categoryId: 'default',
    );
  }

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({
    required String novelId,
    bool descending = false,
  }) async {
    return const [
      NovelEpisodeItem(
        episodeId: 'novel:1:e1',
        novelId: 'novel:1',
        sourceTid: '100',
        sourcePid: '5001',
        sourcePage: 1,
        episodeTitle: 'Chapter 1',
        orderIndex: 0,
        datelineText: '2026-01-01',
      ),
    ];
  }

  @override
  Future<NovelReadingProgress?> getReadingProgress({
    required String novelId,
  }) async => progress;

  @override
  Future<List<NovelItem>> getShelfItems({
    String categoryId = 'default',
  }) async => const [];

  @override
  Future<void> moveNovelToCategory({
    required String novelId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  Future<NovelEpisodeRefreshResult> refreshEpisodes({
    required String novelId,
    NovelEpisodeRefreshMode mode = NovelEpisodeRefreshMode.full,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    return const NovelEpisodeRefreshResult(
      insertedCount: 0,
      updatedCount: 0,
      totalCount: 1,
    );
  }

  @override
  Future<void> removeFromShelf({required String novelId}) async {}

  @override
  Future<void> purgeWork({required String novelId}) async {}

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {}

  @override
  Future<void> saveReadingProgress({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
    NovelReaderFlowMode flowMode = NovelReaderFlowMode.vertical,
    int pageIndex = 0,
    int? pageCount,
    String? anchorNodeId,
    int anchorTextOffset = 0,
    String? paginationKey,
    double progressPercent = 0,
  }) async {}

  Future<void> upsertNovelBySeed({
    required NovelRefreshSeed seed,
    FavoriteSyncExecutionContext? executionContext,
  }) async {}

  @override
  Future<void> addReaderBookmark({
    required NovelReaderBookmark bookmark,
  }) async {}

  @override
  Future<List<NovelReaderBookmark>> listReaderBookmarks({
    required String novelId,
  }) async {
    return const <NovelReaderBookmark>[];
  }

  @override
  Future<void> removeReaderBookmark({required String bookmarkId}) async {}

  @override
  Future<void> toggleEpisodeBookmark({
    required String novelId,
    required String episodeId,
    required bool isBookmarked,
  }) async {}
}

class _FakeLibraryStateRepository implements LibraryStateRepository {
  int readMutationCount = 0;

  @override
  Future<void> bindTagToWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  }) async {}

  @override
  Future<int> countDownloadedEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return 0;
  }

  @override
  Future<int> countReadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return 0;
  }

  @override
  Future<int> countUnreadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return 0;
  }

  @override
  Future<void> purgeWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {}

  @override
  Future<void> setWorksReadState({
    required LibraryModuleKey moduleKey,
    required Set<String> workIds,
    required bool isRead,
    DateTime? readAt,
  }) async {}

  @override
  Future<String> createTag({required String name}) async => 'tag-1';

  @override
  Future<void> deleteTag({required String tagId}) async {}

  @override
  Future<LibraryModuleDisplaySettings> getDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode defaultDisplayMode,
  }) async {
    return LibraryModuleDisplaySettings(
      moduleKey: moduleKey,
      displayMode: defaultDisplayMode,
      gridColumns: 3,
      updatedAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<LibraryEpisodeState?> getEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
  }) async {
    return null;
  }

  @override
  Future<List<LibraryTag>> getTags() async => const [];

  @override
  Future<LibraryWorkState?> getWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return null;
  }

  @override
  Future<List<LibraryTag>> getWorkTags({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return const [];
  }

  @override
  Future<bool> hasAnyTag({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return false;
  }

  @override
  Future<void> renameTag({
    required String tagId,
    required String newName,
  }) async {}

  @override
  Future<void> unbindTagFromWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  }) async {}

  @override
  Future<void> upsertDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode displayMode,
    required int gridColumns,
  }) async {}

  @override
  Future<void> upsertEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
    required String workId,
    bool? isRead,
    bool? isDownloaded,
    bool? isBookmarked,
    DateTime? readAt,
    DateTime? downloadedAt,
  }) async {
    if (isRead != null) {
      readMutationCount++;
    }
  }

  @override
  Future<void> upsertWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
    String? lastReadEpisodeId,
    DateTime? lastReadAt,
    DateTime? checkUpdatedAt,
    DateTime? fetchedUpdatedAt,
    String? introText,
  }) async {}
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/auth/data/repositories/auth_repository.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/comic/data/providers/comic_search_refresh_queue_providers.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/favorites/data/providers/favorite_providers.dart';
import 'package:y300/features/favorites/data/services/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/repositories/local_favorite_repository.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/favorites/domain/services/favorite_shelf_bootstrapper.dart';
import 'package:y300/features/favorites/presentation/favorite_shelf_page.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/data/providers/library_task_notification_providers.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_service.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_host_controller.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_host_providers.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';
import 'package:y300/l10n/app_localizations_zh.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('FavoriteShelfPage builds unified shelf in list mode', (
    tester,
  ) async {
    final bootstrapper = _RecordingFavoriteShelfBootstrapper();
    final authRepository = _FakeAuthRepository(isLoggedIn: true);
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    addTearDown(queueSnapshot.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localFavoriteRepositoryProvider.overrideWith(
            (ref) => _FakeLocalFavoriteRepository(),
          ),
          favoriteSyncServiceProvider.overrideWith(
            (ref) => _FakeFavoriteSyncService(),
          ),
          favoriteShelfBootstrapperProvider.overrideWith((ref) => bootstrapper),
          authRepositoryProvider.overrideWithValue(authRepository),
          libraryStateRepositoryProvider.overrideWithValue(
            _FakeLibraryStateRepository(),
          ),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
            queueSnapshot,
          ),
        ],
        child: const LocalizedTestApp(home: FavoriteShelfPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('收藏'), findsOneWidget);
    expect(find.byKey(const Key('unified-shelf-list-view')), findsOneWidget);
    expect(find.text('收藏帖'), findsOneWidget);
    expect(bootstrapper.startCallCount, 1);

    await tester.tap(find.byKey(const Key('unified-shelf-search-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unified-shelf-search-input')), findsOneWidget);
    expect(find.byKey(const Key('unified-shelf-filter-button')), findsNothing);
    expect(find.byKey(const Key('unified-shelf-more-button')), findsNothing);
  });

  testWidgets(
    'FavoriteShelfPage shows first-sync progress while cache is building',
    (tester) async {
      final sync = _FakeFavoriteSyncService(autoComplete: false);
      final authRepository = _FakeAuthRepository(isLoggedIn: true);
      final bootstrapper = _RecordingFavoriteShelfBootstrapper(
        onStart: () async {
          await sync.sync();
        },
      );
      final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
        ComicSearchRefreshQueueSnapshot.empty,
      );
      addTearDown(queueSnapshot.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localFavoriteRepositoryProvider.overrideWith(
              (ref) => _FakeLocalFavoriteRepository(hasSnapshot: false),
            ),
            favoriteSyncServiceProvider.overrideWith((ref) => sync),
            favoriteShelfBootstrapperProvider.overrideWith(
              (ref) => bootstrapper,
            ),
            authRepositoryProvider.overrideWithValue(authRepository),
            libraryStateRepositoryProvider.overrideWithValue(
              _FakeLibraryStateRepository(),
            ),
            comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
              queueSnapshot,
            ),
          ],
          child: const LocalizedTestApp(home: FavoriteShelfPage()),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('unified-shelf-task-progress-bar')),
        findsOneWidget,
      );
      expect(
        find.text(
          AppLocalizationsZh().libraryTaskFavoriteSyncLoadingDetailsSubject(
            '收藏帖',
          ),
        ),
        findsOneWidget,
      );
      expect(bootstrapper.startCallCount, 1);
      sync.completePendingSync();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'FavoriteShelfPage hides first-sync banner when notification permission is granted',
    (tester) async {
      final sync = _FakeFavoriteSyncService(autoComplete: false);
      final authRepository = _FakeAuthRepository(isLoggedIn: true);
      final bootstrapper = _RecordingFavoriteShelfBootstrapper(
        onStart: () async {
          await sync.sync();
        },
      );
      final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
        ComicSearchRefreshQueueSnapshot.empty,
      );
      final notificationService = _FakeLibraryTaskNotificationService(
        initialPermission: LibraryTaskNotificationPermissionState.granted,
      );
      addTearDown(queueSnapshot.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localFavoriteRepositoryProvider.overrideWith(
              (ref) => _FakeLocalFavoriteRepository(hasSnapshot: false),
            ),
            favoriteSyncServiceProvider.overrideWith((ref) => sync),
            favoriteShelfBootstrapperProvider.overrideWith(
              (ref) => bootstrapper,
            ),
            authRepositoryProvider.overrideWithValue(authRepository),
            libraryStateRepositoryProvider.overrideWithValue(
              _FakeLibraryStateRepository(),
            ),
            comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
              queueSnapshot,
            ),
            libraryTaskNotificationServiceProvider.overrideWithValue(
              notificationService,
            ),
          ],
          child: const LocalizedTestApp(home: FavoriteShelfPage()),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('unified-shelf-task-progress-bar')),
        findsNothing,
      );
      expect(bootstrapper.startCallCount, 1);
      sync.completePendingSync();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('FavoriteShelfPage long press activates 2 selection actions', (
    tester,
  ) async {
    final bootstrapper = _RecordingFavoriteShelfBootstrapper();
    final authRepository = _FakeAuthRepository(isLoggedIn: true);
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    final selectionHost = ShelfSelectionHostController();
    addTearDown(queueSnapshot.dispose);
    addTearDown(selectionHost.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localFavoriteRepositoryProvider.overrideWith(
            (ref) => _FakeLocalFavoriteRepository(),
          ),
          favoriteSyncServiceProvider.overrideWith(
            (ref) => _FakeFavoriteSyncService(),
          ),
          favoriteShelfBootstrapperProvider.overrideWith((ref) => bootstrapper),
          authRepositoryProvider.overrideWithValue(authRepository),
          libraryStateRepositoryProvider.overrideWithValue(
            _FakeLibraryStateRepository(),
          ),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
            queueSnapshot,
          ),
          shelfSelectionHostControllerProvider.overrideWithValue(selectionHost),
        ],
        child: const LocalizedTestApp(home: FavoriteShelfPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(
      find.byKey(
        const ValueKey<String>('unified-shelf-list-item-favorite:100'),
      ),
    );
    await tester.pumpAndSettle();

    expect(selectionHost.state?.selectionActions.length, 2);
    expect(bootstrapper.startCallCount, 1);
  });

  testWidgets('FavoriteShelfPage select all follows first visible category', (
    tester,
  ) async {
    final bootstrapper = _RecordingFavoriteShelfBootstrapper();
    final authRepository = _FakeAuthRepository(isLoggedIn: true);
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    final selectionHost = ShelfSelectionHostController();
    addTearDown(queueSnapshot.dispose);
    addTearDown(selectionHost.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localFavoriteRepositoryProvider.overrideWith(
            (ref) => _FakeLocalFavoriteRepository(
              categories: _multiCategoryFavoriteCategories(),
              itemsByCategory: _multiCategoryFavoriteItems(),
            ),
          ),
          favoriteSyncServiceProvider.overrideWith(
            (ref) => _FakeFavoriteSyncService(),
          ),
          favoriteShelfBootstrapperProvider.overrideWith((ref) => bootstrapper),
          authRepositoryProvider.overrideWithValue(authRepository),
          libraryStateRepositoryProvider.overrideWithValue(
            _FakeLibraryStateRepository(),
          ),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
            queueSnapshot,
          ),
          shelfSelectionHostControllerProvider.overrideWithValue(selectionHost),
        ],
        child: const LocalizedTestApp(home: FavoriteShelfPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(
      find.byKey(
        const ValueKey<String>('unified-shelf-list-item-favorite:201'),
      ),
    );
    await tester.pumpAndSettle();

    expect(selectionHost.state?.activeCategoryId, favoriteComicCategoryId);

    await tester.tap(find.byKey(const Key('selection-app-bar-select-all')));
    await tester.pumpAndSettle();

    expect(selectionHost.state?.selectedCount, 2);
    expect(find.text('已选 2 项'), findsOneWidget);
    for (final tid in ['201', '202']) {
      final itemFinder = find.byKey(
        ValueKey<String>('unified-shelf-list-item-favorite:$tid'),
      );
      final tileFinder = find.descendant(
        of: itemFinder,
        matching: find.byKey(
          ValueKey<String>('unified-shelf-list-tile-favorite:$tid'),
        ),
      );
      expect(tester.widget<ListTile>(tileFinder).selected, isTrue);
      expect(
        _borderColorForListItem(tester, itemFinder),
        isNot(Colors.transparent),
      );
    }
  });

  testWidgets('FavoriteShelfPage invert follows current visible category', (
    tester,
  ) async {
    final bootstrapper = _RecordingFavoriteShelfBootstrapper();
    final authRepository = _FakeAuthRepository(isLoggedIn: true);
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    final selectionHost = ShelfSelectionHostController();
    addTearDown(queueSnapshot.dispose);
    addTearDown(selectionHost.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localFavoriteRepositoryProvider.overrideWith(
            (ref) => _FakeLocalFavoriteRepository(
              categories: _multiCategoryFavoriteCategories(),
              itemsByCategory: _multiCategoryFavoriteItems(),
            ),
          ),
          favoriteSyncServiceProvider.overrideWith(
            (ref) => _FakeFavoriteSyncService(),
          ),
          favoriteShelfBootstrapperProvider.overrideWith((ref) => bootstrapper),
          authRepositoryProvider.overrideWithValue(authRepository),
          libraryStateRepositoryProvider.overrideWithValue(
            _FakeLibraryStateRepository(),
          ),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
            queueSnapshot,
          ),
          shelfSelectionHostControllerProvider.overrideWithValue(selectionHost),
        ],
        child: const LocalizedTestApp(home: FavoriteShelfPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(
      find.byKey(
        const ValueKey<String>('unified-shelf-list-item-favorite:201'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('selection-app-bar-invert')));
    await tester.pumpAndSettle();

    expect(selectionHost.state?.activeCategoryId, favoriteComicCategoryId);
    expect(selectionHost.state?.selectedCount, 1);
    expect(find.text('已选 1 项'), findsOneWidget);

    final firstItemFinder = find.byKey(
      const ValueKey<String>('unified-shelf-list-item-favorite:201'),
    );
    final firstTileFinder = find.descendant(
      of: firstItemFinder,
      matching: find.byKey(
        const ValueKey<String>('unified-shelf-list-tile-favorite:201'),
      ),
    );
    expect(tester.widget<ListTile>(firstTileFinder).selected, isFalse);
    expect(
      _borderColorForListItem(tester, firstItemFinder),
      Colors.transparent,
    );

    final secondItemFinder = find.byKey(
      const ValueKey<String>('unified-shelf-list-item-favorite:202'),
    );
    final secondTileFinder = find.descendant(
      of: secondItemFinder,
      matching: find.byKey(
        const ValueKey<String>('unified-shelf-list-tile-favorite:202'),
      ),
    );
    expect(tester.widget<ListTile>(secondTileFinder).selected, isTrue);
    expect(
      _borderColorForListItem(tester, secondItemFinder),
      isNot(Colors.transparent),
    );
  });

  testWidgets(
    'FavoriteShelfPage retries bootstrap after login when page already exists',
    (tester) async {
      final bootstrapper = _RecordingFavoriteShelfBootstrapper();
      final authRepository = _FakeAuthRepository(isLoggedIn: false);
      final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
        ComicSearchRefreshQueueSnapshot.empty,
      );
      addTearDown(queueSnapshot.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localFavoriteRepositoryProvider.overrideWith(
              (ref) => _FakeLocalFavoriteRepository(hasSnapshot: false),
            ),
            favoriteSyncServiceProvider.overrideWith(
              (ref) => _FakeFavoriteSyncService(),
            ),
            favoriteShelfBootstrapperProvider.overrideWith(
              (ref) => bootstrapper,
            ),
            authRepositoryProvider.overrideWithValue(authRepository),
            libraryStateRepositoryProvider.overrideWithValue(
              _FakeLibraryStateRepository(),
            ),
            comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
              queueSnapshot,
            ),
          ],
          child: const LocalizedTestApp(home: FavoriteShelfPage()),
        ),
      );

      await tester.pumpAndSettle();
      expect(bootstrapper.startCallCount, 0);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(FavoriteShelfPage)),
      );
      authRepository.setLoggedIn();
      await container.read(authSessionControllerProvider.notifier).refresh();
      await tester.pumpAndSettle();

      expect(bootstrapper.startCallCount, 1);
    },
  );

  testWidgets(
    'FavoriteShelfPage waits until active before retrying bootstrap after login',
    (tester) async {
      final bootstrapper = _RecordingFavoriteShelfBootstrapper();
      final authRepository = _FakeAuthRepository(isLoggedIn: false);
      final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
        ComicSearchRefreshQueueSnapshot.empty,
      );
      var isActive = false;
      late StateSetter hostSetState;
      addTearDown(queueSnapshot.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localFavoriteRepositoryProvider.overrideWith(
              (ref) => _FakeLocalFavoriteRepository(hasSnapshot: false),
            ),
            favoriteSyncServiceProvider.overrideWith(
              (ref) => _FakeFavoriteSyncService(),
            ),
            favoriteShelfBootstrapperProvider.overrideWith(
              (ref) => bootstrapper,
            ),
            authRepositoryProvider.overrideWithValue(authRepository),
            libraryStateRepositoryProvider.overrideWithValue(
              _FakeLibraryStateRepository(),
            ),
            comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
              queueSnapshot,
            ),
          ],
          child: LocalizedTestApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                hostSetState = setState;
                return FavoriteShelfPage(isActive: isActive);
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(bootstrapper.startCallCount, 0);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(FavoriteShelfPage)),
      );
      authRepository.setLoggedIn();
      await container.read(authSessionControllerProvider.notifier).refresh();
      await tester.pumpAndSettle();
      expect(bootstrapper.startCallCount, 0);

      hostSetState(() {
        isActive = true;
      });
      await tester.pumpAndSettle();

      expect(bootstrapper.startCallCount, 1);
    },
  );
}

class _RecordingFavoriteShelfBootstrapper implements FavoriteShelfBootstrapper {
  _RecordingFavoriteShelfBootstrapper({Future<void> Function()? onStart})
    : _onStart = onStart;

  final Future<void> Function()? _onStart;
  int startCallCount = 0;

  @override
  Future<void> startIfNeeded() async {
    startCallCount++;
    await _onStart?.call();
  }
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({required bool isLoggedIn}) : _isLoggedIn = isLoggedIn;

  bool _isLoggedIn;

  void setLoggedIn() {
    _isLoggedIn = true;
  }

  @override
  Future<ApiResult<SessionInfo>> login({
    required String username,
    required String password,
    String questionId = '0',
    String answer = '',
  }) async {
    _isLoggedIn = true;
    return ApiSuccess(_session);
  }

  @override
  Future<void> logout() async {
    _isLoggedIn = false;
  }

  @override
  Future<ApiResult<SessionInfo>> refreshSession() async {
    return ApiSuccess(
      _isLoggedIn
          ? _session
          : SessionInfo(
              uid: '0',
              username: '',
              formhash: '',
              isLoggedIn: false,
            ),
    );
  }

  @override
  Future<ApiResult<bool>> verifyAuthByForumIndex() async {
    return ApiSuccess(_isLoggedIn);
  }

  SessionInfo get _session {
    return SessionInfo(
      uid: '100',
      username: 'tester',
      formhash: 'fh',
      isLoggedIn: true,
    );
  }
}

class _FakeFavoriteSyncService implements FavoriteSyncService {
  _FakeFavoriteSyncService({this.autoComplete = true});

  final bool autoComplete;
  final _progress = ValueNotifier<FavoriteSyncProgress>(
    FavoriteSyncProgress.idle,
  );
  Completer<FavoriteSyncResult>? _pendingCompleter;

  @override
  ValueListenable<FavoriteSyncProgress> get progress => _progress;

  @override
  Future<void> runBackgroundMaintenance() async {}

  @override
  Future<FavoriteSyncResult> sync() async {
    _progress.value = const FavoriteSyncProgress(
      phase: FavoriteSyncProgressPhase.loadingDetails,
      subject: '收藏帖',
      current: 1,
      total: 10,
    );
    if (!autoComplete) {
      _pendingCompleter = Completer<FavoriteSyncResult>();
      return _pendingCompleter!.future;
    }
    _progress.value = FavoriteSyncProgress.idle;
    return const FavoriteSyncResult(
      mode: FavoriteSyncMode.incremental,
      remoteCount: 1,
      fetchedPages: 1,
      upsertedCount: 0,
      removedRecords: <FavoriteThreadCacheRecord>[],
      detailLoadedCount: 0,
      failedDetailTids: <String>[],
    );
  }

  @override
  Future<FavoriteSyncResult> syncRecentlyAddedThread({required String tid}) {
    return sync();
  }

  void completePendingSync() {
    final completer = _pendingCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    _progress.value = FavoriteSyncProgress.idle;
    completer.complete(
      const FavoriteSyncResult(
        mode: FavoriteSyncMode.incremental,
        remoteCount: 1,
        fetchedPages: 1,
        upsertedCount: 0,
        removedRecords: <FavoriteThreadCacheRecord>[],
        detailLoadedCount: 0,
        failedDetailTids: <String>[],
      ),
    );
  }
}

class _FakeLibraryTaskNotificationService
    implements LibraryTaskNotificationService {
  _FakeLibraryTaskNotificationService({
    required LibraryTaskNotificationPermissionState? initialPermission,
  }) : _permissionState =
           ValueNotifier<LibraryTaskNotificationPermissionState?>(
             initialPermission,
           );

  final ValueNotifier<LibraryTaskNotificationPermissionState?> _permissionState;

  @override
  ValueListenable<LibraryTaskNotificationPermissionState?>
  get permissionState => _permissionState;

  @override
  Future<void> clear(LibraryTaskNotificationKey key) async {}

  @override
  Future<LibraryTaskNotificationPermissionState> ensurePermission() async {
    return _permissionState.value ??
        LibraryTaskNotificationPermissionState.denied;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> showOrUpdate(LibraryTaskNotification notification) async {}
}

class _FakeLocalFavoriteRepository implements LocalFavoriteRepository {
  _FakeLocalFavoriteRepository({
    this.hasSnapshot = true,
    List<LibraryCategory>? categories,
    Map<String, List<LibraryWorkItem>>? itemsByCategory,
  }) : _categories =
           categories ??
           <LibraryCategory>[
             LibraryCategory(
               categoryId: favoriteDefaultCategoryId,
               name: '默认',
               sortOrder: 0,
               createdAt: DateTime(2026, 1, 1),
             ),
           ],
       _itemsByCategory =
           itemsByCategory ??
           <String, List<LibraryWorkItem>>{
             favoriteDefaultCategoryId: <LibraryWorkItem>[
               LibraryWorkItem(
                 workId: FavoriteShelfWorkId.fromTid('100'),
                 categoryId: favoriteDefaultCategoryId,
                 title: '收藏帖',
                 secondaryName: '作者A',
                 unreadCount: 0,
                 totalChapterCount: 1,
                 readChapterCount: 0,
                 addedAt: DateTime(2026, 1, 1),
               ),
             ],
           };

  final bool hasSnapshot;
  final List<LibraryCategory> _categories;
  final Map<String, List<LibraryWorkItem>> _itemsByCategory;

  @override
  Future<int> countActiveThreads() async => _itemsByCategory.values.fold<int>(
    0,
    (total, items) => total + items.length,
  );

  @override
  Future<int> countMissingDetailRecords() async => 0;

  @override
  Future<String> createCategory({required String name}) async => 'custom';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<void> finishSync({
    required FavoriteSyncMode mode,
    required int remoteCount,
    String? status,
    String? message,
  }) async {}

  @override
  Future<Set<String>> getActiveTids() async {
    return _itemsByCategory.values
        .expand((items) => items)
        .map((item) => FavoriteShelfWorkId.parseTid(item.workId))
        .whereType<String>()
        .toSet();
  }

  @override
  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsForSnapshot() async =>
      const <FavoriteThreadCacheRecord>[];

  @override
  Future<bool> hasCompletedComicAutoRefreshBackfill() async => true;

  @override
  Future<void> markComicAutoRefreshBackfillCompleted({
    required int checkedCount,
    String? message,
  }) async {}

  @override
  Future<FavoriteThreadCacheRecord?> getActiveThreadByTid(String tid) async =>
      null;

  @override
  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsByWorkId(
    String workId,
  ) async => const <FavoriteThreadCacheRecord>[];

  @override
  Future<bool> hasActiveThreadForWorkId(String workId) async => false;

  @override
  Future<int> markRemovedByWorkId(String workId) async => 0;

  @override
  Future<int> markRemovedByTids(Set<String> tids) async => 0;

  @override
  Future<List<FavoriteThreadCacheRecord>> getMissingDetailRecords({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async => const <FavoriteThreadCacheRecord>[];

  @override
  Future<List<FavoriteThreadCacheRecord>>
  getComicAutoRefreshBackfillCandidates({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async => const <FavoriteThreadCacheRecord>[];

  @override
  Future<FavoriteRouteTarget?> getRouteTargetByShelfWorkId(
    String workId,
  ) async {
    final tid = FavoriteShelfWorkId.parseTid(workId) ?? '100';
    return FavoriteRouteTarget(
      tid: tid,
      title: '收藏帖$tid',
      contentKind: ThreadContentKind.forum,
      workId: 'thread:$tid',
    );
  }

  @override
  Future<FavoriteSyncSnapshot?> getSyncSnapshot() async {
    if (!hasSnapshot) {
      return null;
    }
    return FavoriteSyncSnapshot(
      syncKey: favoriteSyncKey,
      remoteCount: _itemsByCategory.values.fold<int>(
        0,
        (total, items) => total + items.length,
      ),
      localActiveCount: _itemsByCategory.values.fold<int>(
        0,
        (total, items) => total + items.length,
      ),
      lastSyncedAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems(String categoryId) async =>
      _itemsByCategory[categoryId] ?? const <LibraryWorkItem>[];

  @override
  Future<List<LibraryCategory>> loadVisibleCategories() async => _categories;

  @override
  Future<void> markSyncFailure(String message) async {}

  @override
  Future<List<FavoriteThreadCacheRecord>> markRemovedTids(
    Set<String> activeRemoteTids,
  ) async => const <FavoriteThreadCacheRecord>[];

  @override
  Future<void> moveThreadToCategory({
    required String tid,
    required String toCategoryId,
  }) async {}

  @override
  Future<String?> pickRandomWorkId({required String categoryId}) async {
    final items = _itemsByCategory[categoryId] ?? const <LibraryWorkItem>[];
    if (items.isEmpty) {
      return null;
    }
    return items.first.workId;
  }

  @override
  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    return <String, List<LibraryWorkItem>>{
      for (final category in categories)
        category.categoryId:
            _itemsByCategory[category.categoryId] ?? const <LibraryWorkItem>[],
    };
  }

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {}

  @override
  Future<void> updateThreadDetailMeta({
    required String tid,
    required String fid,
    required String typeid,
    required String? tagName,
    required ThreadContentKind contentKind,
    required String? workId,
  }) async {}

  @override
  Future<void> markThreadDetailInvalid({required String tid}) async {}

  @override
  Future<int> upsertRemoteThreads(
    List<FavoriteThreadCacheUpsert> items,
  ) async => items.length;
}

List<LibraryCategory> _multiCategoryFavoriteCategories() {
  return <LibraryCategory>[
    LibraryCategory(
      categoryId: favoriteComicCategoryId,
      name: '漫画',
      sortOrder: 0,
      createdAt: DateTime(2026, 1, 1),
    ),
    LibraryCategory(
      categoryId: favoriteNovelCategoryId,
      name: '小说',
      sortOrder: 1,
      createdAt: DateTime(2026, 1, 2),
    ),
    LibraryCategory(
      categoryId: favoriteDefaultCategoryId,
      name: '默认',
      sortOrder: 2,
      createdAt: DateTime(2026, 1, 3),
    ),
  ];
}

Map<String, List<LibraryWorkItem>> _multiCategoryFavoriteItems() {
  return <String, List<LibraryWorkItem>>{
    favoriteComicCategoryId: <LibraryWorkItem>[
      _favoriteItem(
        tid: '201',
        categoryId: favoriteComicCategoryId,
        title: '漫画收藏 A',
      ),
      _favoriteItem(
        tid: '202',
        categoryId: favoriteComicCategoryId,
        title: '漫画收藏 B',
      ),
    ],
    favoriteNovelCategoryId: <LibraryWorkItem>[
      _favoriteItem(
        tid: '301',
        categoryId: favoriteNovelCategoryId,
        title: '小说收藏 A',
      ),
    ],
    favoriteDefaultCategoryId: List<LibraryWorkItem>.generate(
      15,
      (index) => _favoriteItem(
        tid: '${401 + index}',
        categoryId: favoriteDefaultCategoryId,
        title: '默认收藏 ${index + 1}',
      ),
    ),
  };
}

LibraryWorkItem _favoriteItem({
  required String tid,
  required String categoryId,
  required String title,
}) {
  return LibraryWorkItem(
    workId: FavoriteShelfWorkId.fromTid(tid),
    categoryId: categoryId,
    title: title,
    secondaryName: '作者$tid',
    unreadCount: 0,
    totalChapterCount: 1,
    readChapterCount: 0,
    addedAt: DateTime(2026, 1, 1),
  );
}

Color _borderColorForListItem(WidgetTester tester, Finder itemFinder) {
  final container = tester.widget<AnimatedContainer>(itemFinder);
  final decoration = container.decoration as BoxDecoration;
  final border = decoration.border as Border;
  return border.top.color;
}

class _FakeLibraryStateRepository implements LibraryStateRepository {
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
  }) async => 0;

  @override
  Future<int> countReadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => 0;

  @override
  Future<int> countUnreadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => 0;

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
  }) async => null;

  @override
  Future<List<LibraryTag>> getTags() async => const <LibraryTag>[];

  @override
  Future<LibraryWorkState?> getWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => null;

  @override
  Future<List<LibraryTag>> getWorkTags({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => const <LibraryTag>[];

  @override
  Future<bool> hasAnyTag({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async => false;

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
  }) async {}

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

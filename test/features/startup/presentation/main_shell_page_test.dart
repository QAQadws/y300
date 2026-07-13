import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/auth/data/repositories/auth_repository.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/data/providers/comic_search_refresh_queue_providers.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/favorites/data/services/favorite_first_sync_request_governor.dart';
import 'package:y300/features/favorites/data/providers/favorite_providers.dart';
import 'package:y300/features/favorites/data/services/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/repositories/local_favorite_repository.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/forum/data/repositories/forum_mode_settings_repository.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/forum/presentation/forum_shell_mode_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/data/providers/library_task_notification_providers.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_selection_action_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_service.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_host_controller.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_host_providers.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/startup/presentation/main_shell_page.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

void main() {
  testWidgets('MainShellPage can switch between forum/comic/novel/more tabs', (tester) async {
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    final webViewDriver = _FakeForumWebViewDriver();
    addTearDown(queueSnapshot.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_FakeComicRepository()),
          novelRepositoryProvider.overrideWithValue(_FakeNovelRepository()),
          libraryStateRepositoryProvider.overrideWithValue(_FakeLibraryStateRepository()),
          localFavoriteRepositoryProvider.overrideWith((ref) => _FakeLocalFavoriteRepository()),
          favoriteSyncServiceProvider.overrideWith((ref) => _FakeFavoriteSyncService()),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(queueSnapshot),
          mainShellBackgroundTaskStarterProvider.overrideWithValue(() async {}),
          mainShellNotificationInitializerProvider
              .overrideWithValue(() async {}),
          mainShellYamiboSessionWarmupProvider.overrideWithValue(() async {}),
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(),
          ),
          forumWebViewDriverFactoryProvider.overrideWithValue(() => webViewDriver),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
        ],
        child: const MaterialApp(home: MainShellPage()),
      ),
    );

    await tester.pump();

    expect(find.byKey(const Key('forum-webview-page')), findsOneWidget);

    await tester.tap(find.text('收藏').last);
    await tester.pumpAndSettle();
    expect(find.text('收藏'), findsWidgets);
    expect(find.byKey(const Key('unified-shelf-list-view')), findsOneWidget);

    await tester.tap(find.text('漫画').last);
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);

    await tester.tap(find.text('小说').last);
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byKey(const Key('unified-shelf-category-indicator')), findsOneWidget);

    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    expect(find.text('更多'), findsWidgets);
    expect(find.byKey(const Key('more-login-entry')), findsOneWidget);
  });

  testWidgets('Novel tab icon changes after tap', (tester) async {
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    final webViewDriver = _FakeForumWebViewDriver();
    addTearDown(queueSnapshot.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_FakeComicRepository()),
          novelRepositoryProvider.overrideWithValue(_FakeNovelRepository()),
          libraryStateRepositoryProvider.overrideWithValue(_FakeLibraryStateRepository()),
          localFavoriteRepositoryProvider.overrideWith((ref) => _FakeLocalFavoriteRepository()),
          favoriteSyncServiceProvider.overrideWith((ref) => _FakeFavoriteSyncService()),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(queueSnapshot),
          mainShellBackgroundTaskStarterProvider.overrideWithValue(() async {}),
          mainShellNotificationInitializerProvider
              .overrideWithValue(() async {}),
          mainShellYamiboSessionWarmupProvider.overrideWithValue(() async {}),
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(),
          ),
          forumWebViewDriverFactoryProvider.overrideWithValue(() => webViewDriver),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
        ],
        child: const MaterialApp(home: MainShellPage()),
      ),
    );

    await tester.pump();

    expect(find.byIcon(Icons.local_library_outlined), findsOneWidget);
    expect(find.byIcon(Icons.local_library), findsNothing);

    await tester.tap(find.text('小说'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.local_library_outlined), findsNothing);
    expect(find.byIcon(Icons.local_library), findsOneWidget);
  });

  testWidgets('MainShellPage navigation bar reads the themed background color', (
    tester,
  ) async {
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    final webViewDriver = _FakeForumWebViewDriver();
    addTearDown(queueSnapshot.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_FakeComicRepository()),
          novelRepositoryProvider.overrideWithValue(_FakeNovelRepository()),
          libraryStateRepositoryProvider.overrideWithValue(
            _FakeLibraryStateRepository(),
          ),
          localFavoriteRepositoryProvider.overrideWith(
            (ref) => _FakeLocalFavoriteRepository(),
          ),
          favoriteSyncServiceProvider.overrideWith(
            (ref) => _FakeFavoriteSyncService(),
          ),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
            queueSnapshot,
          ),
          mainShellBackgroundTaskStarterProvider.overrideWithValue(() async {}),
          mainShellNotificationInitializerProvider.overrideWithValue(
            () async {},
          ),
          mainShellYamiboSessionWarmupProvider.overrideWithValue(() async {}),
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(),
          ),
          forumWebViewDriverFactoryProvider.overrideWithValue(
            () => webViewDriver,
          ),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const MainShellPage(),
        ),
      ),
    );

    await tester.pump();

    final navigationBarContext = tester.element(find.byType(NavigationBar));
    expect(
      NavigationBarTheme.of(navigationBarContext).backgroundColor,
      const Color(0xFFFDE6B9),
    );
  });

  testWidgets('MainShellPage notification permission wiring does not block shell build', (tester) async {
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    final notificationService = _FakeLibraryTaskNotificationService(
      initialPermission: LibraryTaskNotificationPermissionState.denied,
    );
    final webViewDriver = _FakeForumWebViewDriver();
    addTearDown(queueSnapshot.dispose);
    addTearDown(notificationService.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_FakeComicRepository()),
          novelRepositoryProvider.overrideWithValue(_FakeNovelRepository()),
          libraryStateRepositoryProvider.overrideWithValue(_FakeLibraryStateRepository()),
          localFavoriteRepositoryProvider.overrideWith((ref) => _FakeLocalFavoriteRepository()),
          favoriteSyncServiceProvider.overrideWith((ref) => _FakeFavoriteSyncService()),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(queueSnapshot),
          mainShellBackgroundTaskStarterProvider.overrideWithValue(() async {}),
          libraryTaskNotificationServiceProvider.overrideWithValue(
            notificationService,
          ),
          mainShellYamiboSessionWarmupProvider.overrideWithValue(() async {}),
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(),
          ),
          forumWebViewDriverFactoryProvider.overrideWithValue(() => webViewDriver),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
        ],
        child: const MaterialApp(home: MainShellPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forum-webview-page')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MainShellPage warms up Yamibo profile session on startup', (
    tester,
  ) async {
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    final webViewDriver = _FakeForumWebViewDriver();
    var warmupCalls = 0;
    addTearDown(queueSnapshot.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_FakeComicRepository()),
          novelRepositoryProvider.overrideWithValue(_FakeNovelRepository()),
          libraryStateRepositoryProvider.overrideWithValue(
            _FakeLibraryStateRepository(),
          ),
          localFavoriteRepositoryProvider.overrideWith(
            (ref) => _FakeLocalFavoriteRepository(),
          ),
          favoriteSyncServiceProvider.overrideWith(
            (ref) => _FakeFavoriteSyncService(),
          ),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
            queueSnapshot,
          ),
          mainShellBackgroundTaskStarterProvider.overrideWithValue(() async {}),
          mainShellNotificationInitializerProvider.overrideWithValue(
            () async {},
          ),
          mainShellReplyDraftAttachmentMaintenanceStarterProvider
              .overrideWithValue(() async {}),
          mainShellYamiboSessionWarmupProvider.overrideWithValue(() async {
            warmupCalls += 1;
          }),
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(),
          ),
          forumWebViewDriverFactoryProvider.overrideWithValue(
            () => webViewDriver,
          ),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
        ],
        child: const MaterialApp(home: MainShellPage()),
      ),
    );

    await tester.pump();

    expect(warmupCalls, 1);
  });

  testWidgets('MainShellPage ignores Yamibo profile warmup failure', (
    tester,
  ) async {
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    final webViewDriver = _FakeForumWebViewDriver();
    addTearDown(queueSnapshot.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_FakeComicRepository()),
          novelRepositoryProvider.overrideWithValue(_FakeNovelRepository()),
          libraryStateRepositoryProvider.overrideWithValue(
            _FakeLibraryStateRepository(),
          ),
          localFavoriteRepositoryProvider.overrideWith(
            (ref) => _FakeLocalFavoriteRepository(),
          ),
          favoriteSyncServiceProvider.overrideWith(
            (ref) => _FakeFavoriteSyncService(),
          ),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
            queueSnapshot,
          ),
          mainShellBackgroundTaskStarterProvider.overrideWithValue(() async {}),
          mainShellNotificationInitializerProvider.overrideWithValue(
            () async {},
          ),
          mainShellReplyDraftAttachmentMaintenanceStarterProvider
              .overrideWithValue(() async {}),
          mainShellYamiboSessionWarmupProvider.overrideWithValue(() async {
            throw StateError('warmup failed');
          }),
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(),
          ),
          forumWebViewDriverFactoryProvider.overrideWithValue(
            () => webViewDriver,
          ),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
        ],
        child: const MaterialApp(home: MainShellPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forum-webview-page')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MainShellPage switches bottom bar when selection becomes active', (
    tester,
  ) async {
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    final selectionHost = ShelfSelectionHostController();
    final webViewDriver = _FakeForumWebViewDriver();
    addTearDown(queueSnapshot.dispose);
    addTearDown(selectionHost.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_FakeComicRepository()),
          novelRepositoryProvider.overrideWithValue(_FakeNovelRepository()),
          libraryStateRepositoryProvider.overrideWithValue(_FakeLibraryStateRepository()),
          localFavoriteRepositoryProvider.overrideWith((ref) => _FakeLocalFavoriteRepository()),
          favoriteSyncServiceProvider.overrideWith((ref) => _FakeFavoriteSyncService()),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(queueSnapshot),
          mainShellBackgroundTaskStarterProvider.overrideWithValue(() async {}),
          mainShellNotificationInitializerProvider.overrideWithValue(() async {}),
          mainShellYamiboSessionWarmupProvider.overrideWithValue(() async {}),
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
          shelfSelectionHostControllerProvider.overrideWithValue(selectionHost),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(),
          ),
          forumWebViewDriverFactoryProvider.overrideWithValue(() => webViewDriver),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
        ],
        child: const MaterialApp(home: MainShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const Key('selection-action-bar')), findsNothing);

    selectionHost.activate(
      ownerToken: Object(),
      moduleKey: LibraryModuleKey.comic,
      moduleTitle: '漫画',
      activeCategoryId: 'default',
      selectedCount: 1,
      selectedWorkIds: const <String>{'comic-1'},
      selectionActions: const <SelectionAction>[
        SelectionAction(
          id: SelectionActionIds.download,
          icon: Icons.download_outlined,
          label: '下载',
        ),
      ],
      delegate: _selectionDelegate(),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const Key('selection-action-bar')), findsOneWidget);

    selectionHost.deactivate(selectionHost.state!.ownerToken);
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const Key('selection-action-bar')), findsNothing);
  });

  testWidgets('MainShellPage selection action bar delegates button taps', (tester) async {
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    final selectionHost = ShelfSelectionHostController();
    final calls = <String>[];
    final webViewDriver = _FakeForumWebViewDriver();
    addTearDown(queueSnapshot.dispose);
    addTearDown(selectionHost.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_FakeComicRepository()),
          novelRepositoryProvider.overrideWithValue(_FakeNovelRepository()),
          libraryStateRepositoryProvider.overrideWithValue(_FakeLibraryStateRepository()),
          localFavoriteRepositoryProvider.overrideWith((ref) => _FakeLocalFavoriteRepository()),
          favoriteSyncServiceProvider.overrideWith((ref) => _FakeFavoriteSyncService()),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(queueSnapshot),
          mainShellBackgroundTaskStarterProvider.overrideWithValue(() async {}),
          mainShellNotificationInitializerProvider.overrideWithValue(() async {}),
          mainShellYamiboSessionWarmupProvider.overrideWithValue(() async {}),
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
          shelfSelectionHostControllerProvider.overrideWithValue(selectionHost),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(),
          ),
          forumWebViewDriverFactoryProvider.overrideWithValue(() => webViewDriver),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
        ],
        child: const MaterialApp(home: MainShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    selectionHost.activate(
      ownerToken: Object(),
      moduleKey: LibraryModuleKey.comic,
      moduleTitle: '漫画',
      activeCategoryId: 'default',
      selectedCount: 1,
      selectedWorkIds: const <String>{'comic-1'},
      selectionActions: const <SelectionAction>[
        SelectionAction(
          id: SelectionActionIds.download,
          icon: Icons.download_outlined,
          label: '下载',
        ),
      ],
      delegate: _selectionDelegate(
        onRun: (request) async {
          calls.add(request.actionId);
          return const SelectionActionResult(message: 'done');
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('selection-action-download')));
    await tester.pumpAndSettle();

    expect(calls, <String>[SelectionActionIds.download]);
    expect(selectionHost.isActive, isTrue);
  });

  testWidgets('MainShellPage unfavorite action requires confirmation', (tester) async {
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    final selectionHost = ShelfSelectionHostController();
    var runCount = 0;
    final webViewDriver = _FakeForumWebViewDriver();
    addTearDown(queueSnapshot.dispose);
    addTearDown(selectionHost.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_FakeComicRepository()),
          novelRepositoryProvider.overrideWithValue(_FakeNovelRepository()),
          libraryStateRepositoryProvider.overrideWithValue(_FakeLibraryStateRepository()),
          localFavoriteRepositoryProvider.overrideWith((ref) => _FakeLocalFavoriteRepository()),
          favoriteSyncServiceProvider.overrideWith((ref) => _FakeFavoriteSyncService()),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(queueSnapshot),
          mainShellBackgroundTaskStarterProvider.overrideWithValue(() async {}),
          mainShellNotificationInitializerProvider.overrideWithValue(() async {}),
          mainShellYamiboSessionWarmupProvider.overrideWithValue(() async {}),
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
          shelfSelectionHostControllerProvider.overrideWithValue(selectionHost),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(),
          ),
          forumWebViewDriverFactoryProvider.overrideWithValue(() => webViewDriver),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
        ],
        child: const MaterialApp(home: MainShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    selectionHost.activate(
      ownerToken: Object(),
      moduleKey: LibraryModuleKey.favorite,
      moduleTitle: '收藏',
      activeCategoryId: 'default',
      selectedCount: 2,
      selectedWorkIds: const <String>{'favorite:100', 'favorite:101'},
      selectionActions: const <SelectionAction>[
        SelectionAction(
          id: SelectionActionIds.unfavorite,
          icon: Icons.delete_outline,
          label: '取消收藏',
          destructive: true,
          needsConfirm: true,
        ),
      ],
      delegate: _selectionDelegate(
        onRun: (request) async {
          runCount += 1;
          return const SelectionActionResult(
            message: 'done',
            changed: true,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('selection-action-unfavorite')),
    );
    await tester.pumpAndSettle();

    expect(find.text('确认取消收藏'), findsOneWidget);
    expect(find.textContaining('会被清除'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(runCount, 0);
    expect(selectionHost.isActive, isTrue);

    await tester.tap(
      find.byKey(const ValueKey<String>('selection-action-unfavorite')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(runCount, 1);
    expect(selectionHost.isActive, isFalse);
  });
}

ShelfSelectionHostDelegate _selectionDelegate({
  Future<SelectionActionResult> Function(
    SelectionActionExecutionRequest request,
  )? onRun,
}) {
  return ShelfSelectionHostDelegate(
    exitSelection: () async {},
    selectAllVisible: () async {},
    invertVisible: () async {},
    loadAvailableCategories: () async => const <LibraryCategory>[],
    createCategory: (name) async => 'created',
    runSelectionAction: onRun ??
        (request) async {
          return const SelectionActionResult(message: 'noop');
        },
    refreshAfterAction: () async {},
  );
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
  int initializeCalls = 0;
  int ensurePermissionCalls = 0;

  @override
  ValueListenable<LibraryTaskNotificationPermissionState?> get permissionState =>
      _permissionState;

  @override
  Future<void> clear(LibraryTaskNotificationKey key) async {}

  @override
  Future<LibraryTaskNotificationPermissionState> ensurePermission() async {
    ensurePermissionCalls++;
    return _permissionState.value ??
        LibraryTaskNotificationPermissionState.denied;
  }

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<void> showOrUpdate(LibraryTaskNotification notification) async {}

  void dispose() {
    _permissionState.dispose();
  }
}

class _FakeForumModeSettingsRepository implements ForumModeSettingsRepository {
  _FakeForumModeSettingsRepository();

  ForumShellMode mode = ForumShellMode.webview;

  @override
  Future<ForumShellMode> loadMode() async {
    return mode;
  }

  @override
  Future<void> saveMode(ForumShellMode nextMode) async {
    mode = nextMode;
  }
}

class _FakeForumWebViewDriver implements ForumWebViewDriver {
  @override
  Widget buildWidget({Key? key}) {
    return Container(key: key);
  }

  @override
  Future<ForumWebViewCapabilityProfile> probeCapabilities() async {
    return const ForumWebViewCapabilityProfile(
      engine: ForumWebViewEngine.advanced,
      documentStartMode: ForumWebViewDocumentStartMode.reliable,
      supportsContentBlockers: false,
      supportsTransparentBackground: true,
      supportsPlatformScrollTuning: true,
      supportsCookieHooks: true,
      supportsPageCommitVisible: true,
    );
  }

  @override
  Future<void> initialize({
    required ForumWebViewCallbacks callbacks,
    required ForumWebViewBootstrapConfig bootstrapConfig,
  }) async {}

  @override
  Future<void> load(Uri uri, {Map<String, String> headers = const {}}) async {}

  @override
  Future<void> reload() async {}

  @override
  Future<bool> clearCookies() async {
    return true;
  }

  @override
  Future<String?> getTitle() async {
    return null;
  }

  @override
  Future<bool> canGoBack() async {
    return false;
  }

  @override
  Future<void> goBack() async {}

  @override
  Future<void> runJavaScript(String script) async {}

  @override
  Future<Object?> runJavaScriptReturningResult(String script) async {
    return null;
  }

  @override
  Future<void> seedCookies({
    required String domain,
    required Map<String, String> cookies,
    String path = '/',
  }) async {}
}

class _FakeCookieStore extends CookieStore {
  @override
  Future<Map<String, String>> readCookieMap(Uri uri) async {
    return <String, String>{};
  }

  @override
  Future<String?> readCookieHeader(Uri uri) async {
    return null;
  }
}

class _FakeComicRepository implements ComicRepository {
  @override
  Future<void> addToShelf({
    required String comicId,
    required String tid,
    required String fid,
    String? sourceTypeId,
    String? sourceTagName,
    required String title,
    required ParsedComicPost parsedPost,
  }) async {}

  @override
  Future<void> removeFromShelf({required String comicId}) async {}

  @override
  Future<void> purgeWork({required String comicId}) async {}

  @override
  Future<String> createCategory({required String name}) async => 'mock-category';

  @override
  Future<void> clearEpisodeImageCache({required String episodeId}) async {}

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async => null;

  @override
  Future<List<ComicEpisodeItem>> getComicEpisodes({required String comicId, bool descending = true}) async {
    return const <ComicEpisodeItem>[];
  }

  @override
  Future<List<ComicEpisodeImageItem>> getEpisodeImages({required String episodeId}) async {
    return const <ComicEpisodeImageItem>[];
  }

  @override
  Future<List<ComicShelfCategory>> getCategories() async {
    return <ComicShelfCategory>[
      ComicShelfCategory(
        categoryId: 'default',
        name: '默认',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<ComicShelfDisplaySettings> getDisplaySettings() async {
    return const ComicShelfDisplaySettings(gridColumnCount: 3);
  }

  @override
  Future<List<ComicShelfItem>> getShelfItems({String categoryId = 'default'}) async {
    return const <ComicShelfItem>[];
  }

  @override
  Future<bool> isInShelf({required String comicId}) async {
    return false;
  }

  @override
  Future<ComicReadingProgress?> getLastReadProgress({required String comicId}) async => null;

  @override
  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  }) async {
    return const ComicEpisodeRefreshResult(insertedCount: 0, updatedCount: 0, totalCount: 0);
  }

  @override
  Future<void> moveComicToCategory({
    required String comicId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<void> renameCategory({required String categoryId, required String newName}) async {}

  @override
  Future<void> updateCustomCover({required String comicId, required String? customCoverImageUrl}) async {}

  @override
  Future<void> updateCustomCoverFromLocalFile({required String comicId, required String localCoverPath, String? sourceEpisodeId, int? sourceImageIndex, String? sourceImageUrl, double? focusX, double? focusY}) async {}

  @override
  Future<void> updateCustomCoverFocus({required String comicId, required double? focusX, required double? focusY}) async {}

  @override
  Future<void> updateCustomMetadata({required String comicId, String? customTitle, String? customAuthor, String? customTranslationGroup, String? customSearchTitle}) async {}

  @override
  Future<void> clearCustomMetadata({required String comicId, bool title = false, bool author = false, bool translationGroup = false, bool searchTitle = false}) async {}

  @override
  Future<void> updateGridColumnCount({required int columnCount}) async {}

  @override
  Future<void> saveEpisodeImages({required String episodeId, required List<String> imageUrls}) async {}

  @override
  Future<void> updateEpisodeImageCacheStatus({
    required String episodeId,
    required String imageUrl,
    required String cacheStatus,
    String? cacheLocalPath,
  }) async {}

  @override
  Future<void> updateLastReadProgress({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
  }) async {}

  @override
  Future<void> updateCatalogUrl({required String comicId, required String catalogUrl}) async {}

  @override
  Future<Set<String>> getKnownEpisodeTids({required String comicId}) async => <String>{};
}

class _FakeNovelRepository implements NovelRepository {
  @override
  Future<String> createCategory({required String name}) async => 'default';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<List<NovelShelfCategory>> getCategories() async {
    return <NovelShelfCategory>[
      NovelShelfCategory(
        categoryId: 'default',
        name: '默认',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<NovelItem?> getDetail({required String novelId}) async => null;

  @override
  Future<NovelChapterContent?> getChapterContent({required String episodeId}) async => null;

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({required String novelId, bool descending = false}) async {
    return const <NovelEpisodeItem>[];
  }

  @override
  Future<NovelReaderPreferences> getReaderPreferences() async {
    return NovelReaderPreferences.defaults();
  }

  @override
  Future<List<NovelItem>> getShelfItems({String categoryId = 'default'}) async {
    return const <NovelItem>[];
  }

  @override
  Future<void> moveNovelToCategory({
    required String novelId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<NovelReadingProgress?> getReadingProgress({required String novelId}) async => null;

  Future<NovelEpisodeRefreshResult> refreshEpisodes({
    required String novelId,
    NovelEpisodeRefreshMode mode = NovelEpisodeRefreshMode.full,
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    return const NovelEpisodeRefreshResult(insertedCount: 0, updatedCount: 0, totalCount: 0);
  }

  @override
  Future<void> removeFromShelf({required String novelId}) async {}

  @override
  Future<void> purgeWork({required String novelId}) async {}

  @override
  Future<void> renameCategory({required String categoryId, required String newName}) async {}

  @override
  Future<void> saveReadingProgress({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
    NovelReaderFlowMode flowMode = NovelReaderFlowMode.vertical,
    int pageIndex = 0,
    String? anchorNodeId,
    double progressPercent = 0,
  }) async {}

  Future<void> upsertNovelBySeed({
    required NovelRefreshSeed seed,
    FavoriteSyncExecutionContext? executionContext,
  }) async {}

  @override
  Future<void> upsertReaderPreferences(NovelReaderPreferences preferences) async {}

  @override
  Future<void> addReaderBookmark({required NovelReaderBookmark bookmark}) async {}

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

class _FakeFavoriteSyncService implements FavoriteSyncService {
  final _progress = ValueNotifier<FavoriteSyncProgress>(FavoriteSyncProgress.idle);

  @override
  ValueListenable<FavoriteSyncProgress> get progress => _progress;

  @override
  Future<void> runBackgroundMaintenance() async {}

  @override
  Future<FavoriteSyncResult> sync() async {
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
  Future<FavoriteSyncResult> syncRecentlyAddedThread({
    required String tid,
  }) {
    return sync();
  }
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<ApiResult<SessionInfo>> login({
    required String username,
    required String password,
    String questionId = '0',
    String answer = '',
  }) async {
    return const ApiFailure(
      ApiError(type: ApiErrorType.business, message: 'not implemented'),
    );
  }

  @override
  Future<void> logout() async {}

  @override
  Future<ApiResult<SessionInfo>> refreshSession() async {
    return ApiSuccess(
      SessionInfo(
        uid: '0',
        username: '',
        formhash: 'fh_guest',
        isLoggedIn: false,
      ),
    );
  }

  @override
  Future<ApiResult<bool>> verifyAuthByForumIndex() async {
    return const ApiSuccess(false);
  }
}

class _FakeLocalFavoriteRepository implements LocalFavoriteRepository {
  final _category = LibraryCategory(
    categoryId: favoriteDefaultCategoryId,
    name: '默认',
    sortOrder: 0,
    createdAt: DateTime(2026, 1, 1),
  );

  final _item = LibraryWorkItem(
    workId: FavoriteShelfWorkId.fromTid('100'),
    categoryId: favoriteDefaultCategoryId,
    title: '收藏帖',
    secondaryName: '作者A',
    unreadCount: 0,
    totalChapterCount: 1,
    readChapterCount: 0,
    addedAt: DateTime(2026, 1, 1),
  );

  @override
  Future<int> countActiveThreads() async => 1;

  @override
  Future<int> countMissingDetailRecords() async => 0;

  @override
  Future<String> createCategory({required String name}) async => 'fav-custom';

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
  Future<Set<String>> getActiveTids() async => const <String>{'100'};

  @override
  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsForSnapshot() async => const <FavoriteThreadCacheRecord>[];

  @override
  Future<bool> hasCompletedComicAutoRefreshBackfill() async => true;

  @override
  Future<void> markComicAutoRefreshBackfillCompleted({
    required int checkedCount,
    String? message,
  }) async {}

  @override
  Future<FavoriteThreadCacheRecord?> getActiveThreadByTid(String tid) async => null;

  @override
  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsByWorkId(
    String workId,
  ) async =>
      const <FavoriteThreadCacheRecord>[];

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
  }) async {
    return const <FavoriteThreadCacheRecord>[];
  }

  @override
  Future<List<FavoriteThreadCacheRecord>> getComicAutoRefreshBackfillCandidates({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async {
    return const <FavoriteThreadCacheRecord>[];
  }

  @override
  Future<FavoriteRouteTarget?> getRouteTargetByShelfWorkId(String workId) async {
    return const FavoriteRouteTarget(
      tid: '100',
      title: '收藏帖',
      contentKind: ThreadContentKind.forum,
      workId: 'thread:100',
    );
  }

  @override
  Future<FavoriteSyncSnapshot?> getSyncSnapshot() async {
    return FavoriteSyncSnapshot(
      syncKey: favoriteSyncKey,
      remoteCount: 1,
      localActiveCount: 1,
      lastSyncedAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems(String categoryId) async {
    return <LibraryWorkItem>[_item];
  }

  @override
  Future<List<LibraryCategory>> loadVisibleCategories() async {
    return <LibraryCategory>[_category];
  }

  @override
  Future<void> markSyncFailure(String message) async {}

  @override
  Future<List<FavoriteThreadCacheRecord>> markRemovedTids(Set<String> activeRemoteTids) async {
    return const <FavoriteThreadCacheRecord>[];
  }

  @override
  Future<void> moveThreadToCategory({required String tid, required String toCategoryId}) async {}

  @override
  Future<String?> pickRandomWorkId({required String categoryId}) async => _item.workId;

  @override
  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    return <String, List<LibraryWorkItem>>{
      for (final category in categories) category.categoryId: <LibraryWorkItem>[_item],
    };
  }

  @override
  Future<void> renameCategory({required String categoryId, required String newName}) async {}

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
  Future<int> upsertRemotePage({
    required FavoriteThreadsPage page,
    required int pageStartOrder,
  }) async => 0;
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

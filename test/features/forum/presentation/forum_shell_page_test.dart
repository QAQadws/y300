import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/auth/data/auth_repository.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/data/forum_home_repository.dart';
import 'package:y300/features/forum/data/forum_mode_settings_repository.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/forum/presentation/forum_shell_mode_controller.dart';
import 'package:y300/features/forum/presentation/forum_shell_page.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';

void main() {
  test('forumWebViewDriverProvider uses advanced factory by default', () {
    final legacyDriver = _FakeForumWebViewDriver();
    final advancedDriver = _FakeForumWebViewDriver();
    final container = ProviderContainer(
      overrides: [
        forumWebViewLegacyDriverFactoryProvider.overrideWithValue(
          () => legacyDriver,
        ),
        forumWebViewAdvancedDriverFactoryProvider.overrideWithValue(
          () => advancedDriver,
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(forumWebViewDriverProvider), same(advancedDriver));
  });

  test('forumWebViewDriverProvider uses legacy factory when preferred engine is overridden', () {
    final legacyDriver = _FakeForumWebViewDriver();
    final advancedDriver = _FakeForumWebViewDriver();
    final container = ProviderContainer(
      overrides: [
        forumWebViewPreferredEngineProvider.overrideWithValue(
          ForumWebViewEngine.legacy,
        ),
        forumWebViewLegacyDriverFactoryProvider.overrideWithValue(
          () => legacyDriver,
        ),
        forumWebViewAdvancedDriverFactoryProvider.overrideWithValue(
          () => advancedDriver,
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(forumWebViewDriverProvider), same(legacyDriver));
  });

  testWidgets('ForumShellPage shows webview home page by default', (
    tester,
  ) async {
    final driverRegistry = _FakeForumWebViewDriverRegistry();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(mode: ForumShellMode.webview),
          ),
          forumWebViewDriverFactoryProvider.overrideWithValue(
            driverRegistry.create,
          ),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
        ],
        child: const MaterialApp(home: ForumShellPage()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('forum-webview-page')), findsOneWidget);
    expect(find.text('百合会论坛'), findsOneWidget);
  });

  testWidgets('ForumShellPage shows native forum home when mode is native', (
    tester,
  ) async {
    final driverRegistry = _FakeForumWebViewDriverRegistry();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(mode: ForumShellMode.native),
          ),
          forumHomeRepositoryProvider.overrideWithValue(
            _FakeForumHomeRepository(),
          ),
          forumWebViewDriverFactoryProvider.overrideWithValue(
            driverRegistry.create,
          ),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
        ],
        child: const MaterialApp(home: ForumShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('论坛首页'), findsOneWidget);
    expect(find.byKey(const Key('forum-home-list')), findsOneWidget);
  });

  testWidgets('ForumShellPage follows controller mode changes', (tester) async {
    final modeRepository = _FakeForumModeSettingsRepository(
      mode: ForumShellMode.webview,
    );
    final driverRegistry = _FakeForumWebViewDriverRegistry();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
          forumModeSettingsRepositoryProvider.overrideWithValue(modeRepository),
          forumHomeRepositoryProvider.overrideWithValue(
            _FakeForumHomeRepository(),
          ),
          forumWebViewDriverFactoryProvider.overrideWithValue(
            driverRegistry.create,
          ),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
        ],
        child: const MaterialApp(home: ForumShellPage()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('forum-webview-page')), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ForumShellPage)),
    );
    await container
        .read(forumShellModeControllerProvider.notifier)
        .setMode(ForumShellMode.native);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forum-home-list')), findsOneWidget);
    expect(modeRepository.mode, ForumShellMode.native);
  });

  testWidgets('ForumShellPage rebuilds webview after login state changes', (
    tester,
  ) async {
    final driverRegistry = _FakeForumWebViewDriverRegistry();
    final authRepository = _FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(mode: ForumShellMode.webview),
          ),
          forumWebViewDriverFactoryProvider.overrideWithValue(
            driverRegistry.create,
          ),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
        ],
        child: const MaterialApp(home: ForumShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(driverRegistry.instances.length, 1);
    expect(driverRegistry.instances.single.initializeCallCount, 1);
    expect(driverRegistry.instances.single.loadCallCount, 1);

    authRepository.setSession(
      SessionInfo(
        uid: '1',
        username: 'alice',
        formhash: 'hash',
        isLoggedIn: true,
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ForumShellPage)),
    );
    await container.read(authSessionControllerProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(driverRegistry.instances.length, 2);
    expect(
      driverRegistry.instances.last,
      isNot(same(driverRegistry.instances.first)),
    );
    expect(driverRegistry.instances.last.initializeCallCount, 1);
    expect(driverRegistry.instances.last.loadCallCount, 1);
    expect(find.byKey(const Key('forum-webview-page')), findsOneWidget);
  });

  testWidgets('ForumShellPage rebuilds advanced webview after login state changes', (
    tester,
  ) async {
    final driverRegistry = _FakeForumWebViewDriverRegistry();
    final authRepository = _FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(mode: ForumShellMode.webview),
          ),
          forumWebViewPreferredEngineProvider.overrideWithValue(
            ForumWebViewEngine.advanced,
          ),
          forumWebViewAdvancedDriverFactoryProvider.overrideWithValue(
            driverRegistry.create,
          ),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
        ],
        child: const MaterialApp(home: ForumShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(driverRegistry.instances.length, 1);
    expect(driverRegistry.instances.single.initializeCallCount, 1);
    expect(driverRegistry.instances.single.loadCallCount, 1);

    authRepository.setSession(
      SessionInfo(
        uid: '1',
        username: 'alice',
        formhash: 'hash',
        isLoggedIn: true,
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ForumShellPage)),
    );
    await container.read(authSessionControllerProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(driverRegistry.instances.length, 2);
    expect(
      driverRegistry.instances.last,
      isNot(same(driverRegistry.instances.first)),
    );
    expect(driverRegistry.instances.last.initializeCallCount, 1);
    expect(driverRegistry.instances.last.loadCallCount, 1);
    expect(find.byKey(const Key('forum-webview-page')), findsOneWidget);
  });

  testWidgets('ForumShellPage rebuilds webview after logout state changes', (
    tester,
  ) async {
    final driverRegistry = _FakeForumWebViewDriverRegistry();
    final authRepository = _FakeAuthRepository(
      session: SessionInfo(
        uid: '1',
        username: 'alice',
        formhash: 'hash',
        isLoggedIn: true,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(mode: ForumShellMode.webview),
          ),
          forumWebViewDriverFactoryProvider.overrideWithValue(
            driverRegistry.create,
          ),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
        ],
        child: const MaterialApp(home: ForumShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    final initialDriverCount = driverRegistry.instances.length;
    final activeDriverBeforeLogout = driverRegistry.instances.last;

    authRepository.setSignedOut();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ForumShellPage)),
    );
    await container.read(authSessionControllerProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(driverRegistry.instances.length, initialDriverCount + 1);
    expect(
      driverRegistry.instances.last,
      isNot(same(activeDriverBeforeLogout)),
    );
    expect(driverRegistry.instances.last.initializeCallCount, 1);
    expect(driverRegistry.instances.last.loadCallCount, 1);
    expect(find.byKey(const Key('forum-webview-page')), findsOneWidget);
  });

  testWidgets('ForumShellPage rebuilds advanced webview after logout state changes', (
    tester,
  ) async {
    final driverRegistry = _FakeForumWebViewDriverRegistry();
    final authRepository = _FakeAuthRepository(
      session: SessionInfo(
        uid: '1',
        username: 'alice',
        formhash: 'hash',
        isLoggedIn: true,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(mode: ForumShellMode.webview),
          ),
          forumWebViewPreferredEngineProvider.overrideWithValue(
            ForumWebViewEngine.advanced,
          ),
          forumWebViewAdvancedDriverFactoryProvider.overrideWithValue(
            driverRegistry.create,
          ),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
        ],
        child: const MaterialApp(home: ForumShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    final initialDriverCount = driverRegistry.instances.length;
    final activeDriverBeforeLogout = driverRegistry.instances.last;

    authRepository.setSignedOut();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ForumShellPage)),
    );
    await container.read(authSessionControllerProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(driverRegistry.instances.length, initialDriverCount + 1);
    expect(
      driverRegistry.instances.last,
      isNot(same(activeDriverBeforeLogout)),
    );
    expect(driverRegistry.instances.last.initializeCallCount, 1);
    expect(driverRegistry.instances.last.loadCallCount, 1);
    expect(find.byKey(const Key('forum-webview-page')), findsOneWidget);
  });

  testWidgets('ForumShellPage native mode ignores auth changes for webview build', (
    tester,
  ) async {
    final driverRegistry = _FakeForumWebViewDriverRegistry();
    final authRepository = _FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepository),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(mode: ForumShellMode.native),
          ),
          forumHomeRepositoryProvider.overrideWithValue(
            _FakeForumHomeRepository(),
          ),
          forumWebViewDriverFactoryProvider.overrideWithValue(
            driverRegistry.create,
          ),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
        ],
        child: const MaterialApp(home: ForumShellPage()),
      ),
    );
    await tester.pumpAndSettle();

    final initialDriverCount = driverRegistry.instances.length;

    authRepository.setSession(
      SessionInfo(
        uid: '1',
        username: 'alice',
        formhash: 'hash',
        isLoggedIn: true,
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ForumShellPage)),
    );
    await container.read(authSessionControllerProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forum-home-list')), findsOneWidget);
    expect(find.byKey(const Key('forum-webview-page')), findsNothing);
    expect(driverRegistry.instances.length, initialDriverCount);
  });
}

class _FakeForumModeSettingsRepository implements ForumModeSettingsRepository {
  _FakeForumModeSettingsRepository({required this.mode});

  ForumShellMode mode;

  @override
  Future<ForumShellMode> loadMode() async {
    return mode;
  }

  @override
  Future<void> saveMode(ForumShellMode nextMode) async {
    mode = nextMode;
  }
}

class _FakeForumHomeRepository implements ForumHomeRepository {
  @override
  Future<ApiResult<ForumHomePayload>> getForumHomePayload() async {
    return ApiSuccess(
      ForumHomePayload(
        forumIndex: ForumIndexData(
          categories: [
            ForumCategory(fid: '1', name: '综合区', forums: ['2']),
          ],
          forums: [
            ForumItem(
              fid: '2',
              name: '公告区',
              threads: 12,
              posts: 34,
              todayPosts: 2,
              description: '站点公告与维护信息',
              icon: '',
              subForums: const [],
            ),
          ],
        ),
        isLoggedIn: true,
        favoriteForums: const <FavoriteForum>[],
      ),
    );
  }
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({SessionInfo? session}) : _session = session;

  SessionInfo? _session;

  void setSession(SessionInfo session) {
    _session = session;
  }

  void setSignedOut() {
    _session = null;
  }

  @override
  Future<ApiResult<SessionInfo>> refreshSession() async {
    final session = _session;
    if (session == null) {
      return ApiSuccess<SessionInfo>(
        SessionInfo(
          uid: '0',
          username: '',
          formhash: '',
          isLoggedIn: false,
        ),
      );
    }
    return ApiSuccess<SessionInfo>(session);
  }

  @override
  Future<ApiResult<bool>> verifyAuthByForumIndex() async {
    return ApiSuccess<bool>(_session?.isLoggedIn ?? false);
  }

  @override
  Future<ApiResult<SessionInfo>> login({
    required String username,
    required String password,
    String questionId = '0',
    String answer = '',
  }) async {
    final session = SessionInfo(
      uid: '1',
      username: username,
      formhash: 'hash',
      isLoggedIn: true,
    );
    _session = session;
    return ApiSuccess<SessionInfo>(session);
  }

  @override
  Future<void> logout() async {
    _session = null;
  }
}

class _FakeForumWebViewDriver implements ForumWebViewDriver {
  int initializeCallCount = 0;
  int loadCallCount = 0;
  int probeCapabilitiesCallCount = 0;
  ForumWebViewBootstrapConfig? bootstrapConfig;

  @override
  Widget buildWidget({Key? key}) {
    return Container(key: key);
  }

  @override
  Future<ForumWebViewCapabilityProfile> probeCapabilities() async {
    probeCapabilitiesCallCount += 1;
    return const ForumWebViewCapabilityProfile(
      engine: ForumWebViewEngine.advanced,
      documentStartMode: ForumWebViewDocumentStartMode.reliable,
      supportsContentBlockers: false,
      supportsTransparentBackground: true,
      supportsPlatformScrollTuning: true,
      supportsCookieHooks: true,
    );
  }

  @override
  Future<void> initialize({
    required ForumWebViewCallbacks callbacks,
    required ForumWebViewBootstrapConfig bootstrapConfig,
  }) async {
    initializeCallCount += 1;
    this.bootstrapConfig = bootstrapConfig;
  }

  @override
  Future<void> load(Uri uri) async {
    loadCallCount += 1;
  }

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

class _FakeForumWebViewDriverRegistry {
  final List<_FakeForumWebViewDriver> instances = <_FakeForumWebViewDriver>[];

  _FakeForumWebViewDriver create() {
    final driver = _FakeForumWebViewDriver();
    instances.add(driver);
    return driver;
  }
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

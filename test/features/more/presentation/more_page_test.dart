import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/settings/app_appearance_controller.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/webview_cookie_sync_service.dart';
import 'package:y300/features/auth/data/repositories/auth_repository.dart';
import 'package:y300/features/auth/presentation/login_webview_page.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/data/repositories/forum_mode_settings_repository.dart';
import 'package:y300/features/forum/data/repositories/forum_favorite_repository.dart';
import 'package:y300/features/forum/domain/models/forum_favorite_models.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/forum/presentation/forum_shell_mode_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_page.dart';
import 'package:y300/features/more/presentation/more_page.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_renderer_prototype_page.dart';

void main() {
  testWidgets('MorePage builds dark theme chrome', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(isLoggedIn: false),
          ),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(),
          ),
          appAppearanceControllerProvider.overrideWith(
            () => _FakeAppAppearanceController(),
          ),
        ],
        child: LocalizedTestApp(theme: AppTheme.dark(), home: const MorePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byKey(const Key('more-appearance-entry')), findsOneWidget);
    expect(find.byKey(const Key('more-data-storage-entry')), findsOneWidget);
  });

  testWidgets('MorePage renders stage-1 entries', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(isLoggedIn: false),
          ),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(),
          ),
          appAppearanceControllerProvider.overrideWith(
            () => _FakeAppAppearanceController(),
          ),
        ],
        child: const LocalizedTestApp(home: MorePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('更多'), findsWidgets);
    expect(find.byKey(const Key('more-login-entry')), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.byKey(const Key('more-my-profile-entry')), findsOneWidget);
    expect(find.text('我的资料'), findsOneWidget);
    expect(find.byKey(const Key('more-forum-mode-entry')), findsOneWidget);
    expect(find.text('论坛显示模式'), findsOneWidget);
    expect(find.text('当前：WebView 模式'), findsOneWidget);
    expect(find.byKey(const Key('more-appearance-entry')), findsOneWidget);
    expect(find.text('外观与文字'), findsOneWidget);
    expect(find.text('当前：浅色'), findsOneWidget);
    expect(
      find.byKey(const Key('more-navigation-management-entry')),
      findsOneWidget,
    );
    expect(find.text('导航栏管理'), findsOneWidget);
    expect(find.text('已显示 5 项'), findsOneWidget);
    expect(find.byKey(const Key('more-cache-settings-entry')), findsNothing);
    expect(find.byKey(const Key('more-data-storage-entry')), findsOneWidget);
    expect(find.text('数据与存储'), findsOneWidget);
    expect(find.text('管理图片缓存与下载位置'), findsOneWidget);
    expect(find.byKey(const Key('more-download-queue-entry')), findsOneWidget);
    expect(find.text('下载队列'), findsOneWidget);
    expect(find.text('暂无下载任务'), findsOneWidget);
    expect(find.byKey(const Key('about-check-update-entry')), findsNothing);
    expect(
      find.byKey(const Key('more-reader-settings-placeholder')),
      findsNothing,
    );
    await _scrollUntilVisibleIfNeeded(
      tester,
      find.byKey(const Key('more-composer-quill-prototype-entry')),
    );
    expect(
      find.byKey(const Key('more-composer-quill-prototype-entry')),
      findsOneWidget,
    );
    await _scrollUntilVisibleIfNeeded(
      tester,
      find.byKey(const Key('more-html-renderer-prototype-entry')),
    );
    expect(
      find.byKey(const Key('more-html-renderer-prototype-entry')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('more-thread-detail-diagnostic-switch')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('more-thread-detail-diagnostic-copy-entry')),
      findsNothing,
    );
    await _scrollUntilVisibleIfNeeded(
      tester,
      find.byKey(const Key('more-about-entry')),
    );
    expect(find.byKey(const Key('more-about-entry')), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
  });

  testWidgets('MorePage opens the HTML renderer prototype in debug builds', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(isLoggedIn: false),
          ),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(),
          ),
          appAppearanceControllerProvider.overrideWith(
            () => _FakeAppAppearanceController(),
          ),
        ],
        child: const LocalizedTestApp(home: MorePage()),
      ),
    );
    await tester.pumpAndSettle();

    final entry = find.byKey(const Key('more-html-renderer-prototype-entry'));
    await _scrollUntilVisibleIfNeeded(tester, entry);
    await tester.drag(find.byType(ListView), const Offset(0, -80));
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ForumHtmlRendererPrototypePage), findsOneWidget);
    expect(find.text('HTML 正文渲染原型'), findsWidgets);
  });

  testWidgets('MorePage renders logout entry when signed in', (tester) async {
    final repository = _FakeAuthRepository(isLoggedIn: true);
    final webViewDriver = _FakeForumWebViewDriver();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(),
          ),
          appAppearanceControllerProvider.overrideWith(
            () => _FakeAppAppearanceController(),
          ),
          forumWebViewDriverFactoryProvider.overrideWith(
            (ref) =>
                () => webViewDriver,
          ),
          cookieStoreProvider.overrideWithValue(_FakeCookieStore()),
          webViewCookieSyncServiceProvider.overrideWithValue(
            _FakeWebViewCookieSyncService(),
          ),
          forumFavoriteRepositoryProvider.overrideWithValue(
            const _FakeForumFavoriteRepository(),
          ),
        ],
        child: const LocalizedTestApp(
          locale: Locale('en'),
          supportedLocales: [Locale('en')],
          localizationsDelegates:
              LocalizedTestApp.frameworkAndQuillLocalizationsDelegates,
          home: MorePage(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('more-login-entry')), findsNothing);
    expect(find.byKey(const Key('more-logout-entry')), findsOneWidget);
    expect(find.byKey(const Key('more-my-profile-entry')), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
    expect(find.text('当前账号：tester'), findsOneWidget);

    await tester.tap(find.byKey(const Key('more-my-profile-entry')));
    await tester.pumpAndSettle();

    expect(find.byType(ForumWebViewPage), findsOneWidget);
    expect(find.byKey(const Key('forum-webview-page')), findsOneWidget);
    expect(find.text('我的资料'), findsWidgets);
    expect(
      webViewDriver.bootstrapConfig?.initialUri.toString(),
      'https://bbs.yamibo.com/home.php?mod=space&uid=100&do=profile&mycenter=1&mobile=2',
    );
    expect(webViewDriver.loadedUris, <Uri>[
      Uri.parse(
        'https://bbs.yamibo.com/home.php?mod=space&uid=100&do=profile&mycenter=1&mobile=2',
      ),
    ]);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('more-logout-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('more-logout-confirm-button')));
    await tester.pumpAndSettle();

    expect(repository.logoutCount, 1);
    expect(find.byKey(const Key('more-login-entry')), findsOneWidget);
    expect(find.text('已退出登录'), findsOneWidget);
  });

  testWidgets('MorePage switches forum shell mode from bottom sheet', (
    tester,
  ) async {
    final modeRepository = _FakeForumModeSettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(isLoggedIn: false),
          ),
          forumModeSettingsRepositoryProvider.overrideWithValue(modeRepository),
          appAppearanceControllerProvider.overrideWith(
            () => _FakeAppAppearanceController(),
          ),
        ],
        child: const LocalizedTestApp(home: MorePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前：WebView 模式'), findsOneWidget);

    await tester.tap(find.byKey(const Key('more-forum-mode-entry')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('more-forum-mode-option-webview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('more-forum-mode-option-native')),
      findsOneWidget,
    );
    expect(find.text('解析模式'), findsOneWidget);

    await tester.tap(find.byKey(const Key('more-forum-mode-option-native')));
    await tester.pumpAndSettle();

    expect(modeRepository.mode, ForumShellMode.native);
    expect(find.text('当前：解析模式'), findsOneWidget);
  });

  testWidgets('MorePage login entry navigates to the WebView login page', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(isLoggedIn: false);
    final routeObserver = _RouteNameObserver();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(),
          ),
          appAppearanceControllerProvider.overrideWith(
            () => _FakeAppAppearanceController(),
          ),
        ],
        child: LocalizedTestApp(
          home: const MorePage(),
          navigatorObservers: [routeObserver],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('more-login-entry')));
    // 不 pump 目标页：Navigator.push 会同步通知 observer.didPush 记录路由名，
    // 而目标页（含真实 InAppWebView 平台视图）的 build 被推迟到下一帧。此处
    // 只断言“入栈了正确的登录路由”，避免在纯 widget 测试环境构建平台视图。
    // 登录检测/校验逻辑已由 resolver 单测覆盖。

    expect(routeObserver.pushedNames, contains(LoginWebViewPage.routeName));
  });

  testWidgets('MorePage shows snackbar when forum mode save fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(isLoggedIn: false),
          ),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(failOnSave: true),
          ),
          appAppearanceControllerProvider.overrideWith(
            () => _FakeAppAppearanceController(),
          ),
        ],
        child: const LocalizedTestApp(home: MorePage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('more-forum-mode-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('more-forum-mode-option-native')));
    await tester.pumpAndSettle();

    expect(find.textContaining('论坛显示模式切换失败'), findsOneWidget);
    expect(find.text('当前：WebView 模式'), findsOneWidget);
    expect(
      find.byKey(const Key('more-forum-mode-option-native')),
      findsOneWidget,
    );
  });

  testWidgets('MorePage opens appearance drawer and changes theme mode', (
    tester,
  ) async {
    final appearanceController = _FakeAppAppearanceController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(isLoggedIn: false),
          ),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(),
          ),
          appAppearanceControllerProvider.overrideWith(
            () => appearanceController,
          ),
        ],
        child: const LocalizedTestApp(home: MorePage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('more-appearance-entry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('appearance-settings-sheet')), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);
    expect(find.text('外观与文字'), findsWidgets);
    expect(
      find.byKey(const Key('appearance-theme-segmented-button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('appearance-theme-option-light')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('appearance-theme-option-dark')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('appearance-theme-option-system')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('appearance-theme-selected-light')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('appearance-theme-option-dark')));
    await tester.pumpAndSettle();

    expect(appearanceController.themePreference, AppThemePreference.dark);
    expect(
      find.byKey(const Key('appearance-theme-selected-dark')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('appearance-theme-selected-light')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('appearance-settings-close-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('appearance-settings-sheet')), findsNothing);
    expect(find.text('当前：深色'), findsOneWidget);
  });

  testWidgets('Appearance settings drawer changes app language', (
    tester,
  ) async {
    final appearanceController = _FakeAppAppearanceController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(isLoggedIn: false),
          ),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(),
          ),
          appAppearanceControllerProvider.overrideWith(
            () => appearanceController,
          ),
        ],
        child: const LocalizedTestApp(home: MorePage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('more-appearance-entry')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('appearance-language-option-system')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('appearance-language-option-simplifiedChinese')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('appearance-language-option-traditionalChinese')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('appearance-language-selected-system')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('appearance-language-option-traditionalChinese')),
    );
    await tester.pumpAndSettle();

    expect(
      appearanceController.languagePreference,
      AppLanguage.traditionalChinese,
    );
    expect(
      find.byKey(const Key('appearance-language-selected-traditionalChinese')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('appearance-language-selected-system')),
      findsNothing,
    );
  });

  testWidgets('Appearance settings drawer shows snackbar when save fails', (
    tester,
  ) async {
    final appearanceController = _FakeAppAppearanceController(failOnSave: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(isLoggedIn: false),
          ),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(),
          ),
          appAppearanceControllerProvider.overrideWith(
            () => appearanceController,
          ),
        ],
        child: const LocalizedTestApp(home: MorePage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('more-appearance-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('appearance-theme-option-system')));
    await tester.pumpAndSettle();

    expect(find.textContaining('主题设置保存失败'), findsOneWidget);
    expect(appearanceController.themePreference, AppThemePreference.light);
    expect(find.byKey(const Key('appearance-settings-sheet')), findsOneWidget);
    expect(
      find.byKey(const Key('appearance-theme-selected-light')),
      findsOneWidget,
    );
  });
}

Future<void> _scrollUntilVisibleIfNeeded(
  WidgetTester tester,
  Finder finder,
) async {
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder);
    await tester.pump();
    return;
  }
  await tester.scrollUntilVisible(finder, 160);
}

class _RouteNameObserver extends NavigatorObserver {
  final List<String?> pushedNames = <String?>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedNames.add(route.settings.name);
    super.didPush(route, previousRoute);
  }
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({required bool isLoggedIn}) : _isLoggedIn = isLoggedIn;
  bool _isLoggedIn;
  var logoutCount = 0;
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
    logoutCount++;
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
              formhash: 'fh_guest',
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

class _FakeForumModeSettingsRepository implements ForumModeSettingsRepository {
  _FakeForumModeSettingsRepository({this.failOnSave = false});

  ForumShellMode mode = ForumShellMode.webview;
  final bool failOnSave;

  @override
  Future<ForumShellMode> loadMode() async {
    return mode;
  }

  @override
  Future<void> saveMode(ForumShellMode nextMode) async {
    if (failOnSave) {
      throw StateError('save failed');
    }
    mode = nextMode;
  }
}

class _FakeAppAppearanceController extends AppAppearanceController {
  _FakeAppAppearanceController({this.failOnSave = false});

  final bool failOnSave;
  var _settings = AppAppearanceSettings.defaults();

  AppThemePreference get themePreference => _settings.themePreference;
  AppLanguage get languagePreference => _settings.languagePreference;

  @override
  Future<AppAppearanceSettings> build() async {
    return _settings;
  }

  @override
  Future<void> setThemePreference(AppThemePreference preference) async {
    final previous = _settings;
    if (previous.themePreference == preference) {
      return;
    }
    _settings = previous.copyWith(themePreference: preference);
    state = AsyncData(_settings);
    if (!failOnSave) {
      return;
    }
    _settings = previous;
    state = AsyncData(previous);
    throw StateError('save failed');
  }

  @override
  Future<void> setLanguagePreference(AppLanguage language) async {
    final previous = _settings;
    if (previous.languagePreference == language) {
      return;
    }
    _settings = previous.copyWith(languagePreference: language);
    state = AsyncData(_settings);
    if (!failOnSave) {
      return;
    }
    _settings = previous;
    state = AsyncData(previous);
    throw StateError('save failed');
  }
}

class _FakeCookieStore extends CookieStore {
  @override
  Future<Map<String, String>> readCookieMap(Uri uri) async {
    return const <String, String>{};
  }

  @override
  Future<void> saveCookies(Uri uri, Map<String, String> cookies) async {}
}

class _FakeWebViewCookieJar implements WebViewCookieJar {
  @override
  Future<void> clear() async {}

  @override
  Future<Map<String, String>> readCookies(Uri uri) async {
    return const <String, String>{};
  }
}

class _FakeWebViewCookieSyncService extends WebViewCookieSyncService {
  _FakeWebViewCookieSyncService()
    : super(
        cookieJar: _FakeWebViewCookieJar(),
        cookieStore: _FakeCookieStore(),
      );

  @override
  Future<void> clearWebViewCookies() async {}

  @override
  Future<Map<String, String>> syncToStore(Uri uri) async {
    return const <String, String>{};
  }
}

class _FakeForumFavoriteRepository implements ForumFavoriteRepository {
  const _FakeForumFavoriteRepository();

  @override
  Future<ApiResult<ForumFavoriteMutationResult>> favoriteForum({
    required String fid,
  }) async {
    return const ApiSuccess<ForumFavoriteMutationResult>(
      ForumFavoriteMutationResult(message: '收藏成功'),
    );
  }

  @override
  Future<ApiResult<List<FavoriteForum>>> loadFavoriteForums() async {
    return const ApiSuccess<List<FavoriteForum>>(<FavoriteForum>[]);
  }

  @override
  Future<ApiResult<ForumFavoriteMutationResult>> unfavoriteForum({
    required String favid,
  }) async {
    return const ApiSuccess<ForumFavoriteMutationResult>(
      ForumFavoriteMutationResult(message: '取消收藏成功'),
    );
  }
}

class _FakeForumWebViewDriver implements ForumWebViewDriver {
  final List<Uri> loadedUris = <Uri>[];
  ForumWebViewBootstrapConfig? bootstrapConfig;
  ForumWebViewCallbacks? _callbacks;

  @override
  Widget buildWidget({Key? key}) {
    return SizedBox.expand(key: key);
  }

  @override
  Future<bool> canGoBack() async {
    return false;
  }

  @override
  Future<bool> clearCookies() async {
    return true;
  }

  @override
  Future<String?> getTitle() async {
    return '我的资料';
  }

  @override
  Future<void> goBack() async {}

  @override
  Future<void> initialize({
    required ForumWebViewCallbacks callbacks,
    required ForumWebViewBootstrapConfig bootstrapConfig,
  }) async {
    _callbacks = callbacks;
    this.bootstrapConfig = bootstrapConfig;
  }

  @override
  Future<void> load(Uri uri, {Map<String, String> headers = const {}}) async {
    loadedUris.add(uri);
    _callbacks?.onPageStarted(uri.toString());
    _callbacks?.onProgress(100);
    await _callbacks?.onPageFinished(uri.toString());
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
  Future<void> reload() async {}

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

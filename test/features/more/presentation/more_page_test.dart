import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/settings/app_appearance_controller.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/app/theme/app_theme_palette.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/webview_cookie_sync_service.dart';
import 'package:y300/features/auth/data/repositories/auth_repository.dart';
import 'package:y300/features/auth/presentation/login_webview_page.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_unused_image_management_controller.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_unused_image_management_page.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/data/repositories/forum_mode_settings_repository.dart';
import 'package:y300/features/forum/data/repositories/forum_favorite_repository.dart';
import 'package:y300/features/forum/domain/models/forum_favorite_models.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/forum/presentation/forum_shell_mode_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_page.dart';
import 'package:y300/features/more/presentation/appearance_settings_sheet.dart';
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
    expect(find.byKey(const Key('more-unused-images-entry')), findsOneWidget);
    expect(find.text('未使用图片管理'), findsOneWidget);
    expect(find.byKey(const Key('more-forum-mode-entry')), findsOneWidget);
    expect(find.text('论坛显示模式'), findsOneWidget);
    expect(find.text('当前：WebView 模式'), findsOneWidget);
    expect(find.byKey(const Key('more-appearance-entry')), findsOneWidget);
    expect(find.text('外观与文字'), findsOneWidget);
    expect(find.text('当前：暖纸 · 日间'), findsOneWidget);
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
        child: const LocalizedTestApp(home: MorePage()),
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

    await tester.tap(find.byKey(const Key('forum-webview-back-button')));
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

  testWidgets(
    'unused images entry resumes navigation after WebView login succeeds',
    (tester) async {
      final routeObserver = _RouteNameObserver();
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
            composerUnusedImageManagementControllerProvider.overrideWith(
              _FakeUnusedImagesController.new,
            ),
          ],
          child: LocalizedTestApp(
            home: const MorePage(),
            navigatorObservers: [routeObserver],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('more-unused-images-entry')));
      expect(routeObserver.pushedNames.last, LoginWebViewPage.routeName);

      tester.state<NavigatorState>(find.byType(Navigator).first).pop(true);
      await tester.pump();
      await tester.pump();

      expect(
        routeObserver.pushedNames,
        contains(ComposerUnusedImageManagementPage.routeName),
      );
      expect(find.byType(ComposerUnusedImageManagementPage), findsOneWidget);
    },
  );

  testWidgets('unused images entry stays on More after login is cancelled', (
    tester,
  ) async {
    final routeObserver = _RouteNameObserver();
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
          composerUnusedImageManagementControllerProvider.overrideWith(
            _FakeUnusedImagesController.new,
          ),
        ],
        child: LocalizedTestApp(
          home: const MorePage(),
          navigatorObservers: [routeObserver],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('more-unused-images-entry')));
    tester.state<NavigatorState>(find.byType(Navigator).first).pop(false);
    await tester.pumpAndSettle();

    expect(find.byType(MorePage), findsOneWidget);
    expect(find.byType(ComposerUnusedImageManagementPage), findsNothing);
    expect(
      routeObserver.pushedNames
          .where((name) => name == ComposerUnusedImageManagementPage.routeName)
          .length,
      0,
    );
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

  testWidgets('MorePage changes theme family and brightness independently', (
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
    expect(find.text('外观与文字'), findsOneWidget);
    expect(
      find.byKey(const Key('appearance-settings-close-button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('appearance-theme-segmented-button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('appearance-theme-family-warmPaper')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('appearance-theme-family-moonWhite')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('appearance-theme-family-plumPurple')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('appearance-brightness-option-system')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check), findsNothing);
    for (final family in AppThemeFamily.values) {
      final palette = AppThemePalette.resolve(family, Brightness.light);
      final swatch = tester.widget<Container>(
        find.byKey(Key('appearance-theme-family-swatch-${family.name}')),
      );
      final primarySwatch = find.byKey(
        Key('appearance-theme-family-swatch-${family.name}-primary'),
      );
      final pageSwatch = find.byKey(
        Key('appearance-theme-family-swatch-${family.name}-page'),
      );
      expect(tester.widget<ColoredBox>(primarySwatch).color, palette.primary);
      expect(
        tester.widget<ColoredBox>(pageSwatch).color,
        palette.surfaceContainer,
      );
      expect(tester.getSize(primarySwatch).height, greaterThan(0));
      expect(tester.getSize(pageSwatch).height, greaterThan(0));
      expect(
        tester.getSize(primarySwatch).width,
        tester.getSize(pageSwatch).width,
      );
      expect((swatch.decoration! as BoxDecoration).border, isNull);
    }

    await tester.tap(
      find.byKey(const Key('appearance-theme-family-plumPurple')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('appearance-brightness-option-dark')),
    );
    await tester.pumpAndSettle();

    expect(appearanceController.themeFamily, AppThemeFamily.plumPurple);
    expect(
      appearanceController.brightnessPreference,
      AppBrightnessPreference.dark,
    );
    expect(
      find.byKey(const Key('appearance-brightness-icon-dark')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('appearance-settings-sheet')), findsNothing);
    expect(find.text('当前：梅紫 · 夜间'), findsOneWidget);
  });

  testWidgets('Appearance theme swatches follow the active brightness', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appAppearanceControllerProvider.overrideWith(
            _FakeAppAppearanceController.new,
          ),
        ],
        child: LocalizedTestApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: AppearanceSettingsSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final family in AppThemeFamily.values) {
      final palette = AppThemePalette.resolve(family, Brightness.dark);
      expect(
        tester
            .widget<ColoredBox>(
              find.byKey(
                Key('appearance-theme-family-swatch-${family.name}-primary'),
              ),
            )
            .color,
        palette.primary,
      );
      expect(
        tester
            .widget<ColoredBox>(
              find.byKey(
                Key('appearance-theme-family-swatch-${family.name}-page'),
              ),
            )
            .color,
        palette.surfaceContainer,
      );
    }
  });

  testWidgets(
    'Appearance settings keeps each option group on one scrollable row',
    (tester) async {
      tester.view.physicalSize = const Size(280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final appearanceController = _FakeAppAppearanceController();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appAppearanceControllerProvider.overrideWith(
              () => appearanceController,
            ),
          ],
          child: const LocalizedTestApp(
            locale: Locale('zh', 'TW'),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(280, 720),
                textScaler: TextScaler.linear(1.6),
              ),
              child: Scaffold(body: AppearanceSettingsSheet()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final familyStrip = find.byKey(
        const Key('appearance-theme-family-options-scroll'),
      );
      final brightnessStrip = find.byKey(
        const Key('appearance-brightness-options-scroll'),
      );
      final languageStrip = find.byKey(
        const Key('appearance-language-options-scroll'),
      );
      expect(
        tester.widget<SingleChildScrollView>(familyStrip).scrollDirection,
        Axis.horizontal,
      );
      expect(
        tester.widget<SingleChildScrollView>(brightnessStrip).scrollDirection,
        Axis.horizontal,
      );
      expect(
        tester.widget<SingleChildScrollView>(languageStrip).scrollDirection,
        Axis.horizontal,
      );

      final familyScrollable = tester.state<ScrollableState>(
        find.descendant(of: familyStrip, matching: find.byType(Scrollable)),
      );
      final brightnessScrollable = tester.state<ScrollableState>(
        find.descendant(of: brightnessStrip, matching: find.byType(Scrollable)),
      );
      final languageScrollable = tester.state<ScrollableState>(
        find.descendant(of: languageStrip, matching: find.byType(Scrollable)),
      );
      expect(familyScrollable.position.maxScrollExtent, greaterThan(0));
      expect(brightnessScrollable.position.maxScrollExtent, greaterThan(0));
      expect(languageScrollable.position.maxScrollExtent, greaterThan(0));

      _expectSameVerticalCenter(tester, const <Key>[
        Key('appearance-brightness-option-light'),
        Key('appearance-brightness-option-dark'),
        Key('appearance-brightness-option-system'),
      ]);
      _expectSameVerticalCenter(tester, const <Key>[
        Key('appearance-language-option-system'),
        Key('appearance-language-option-simplifiedChinese'),
        Key('appearance-language-option-traditionalChinese'),
      ]);
      _expectSingleLineButtonLabel(
        tester,
        const Key('appearance-brightness-option-system'),
      );
      _expectSingleLineButtonLabel(
        tester,
        const Key('appearance-language-option-traditionalChinese'),
      );

      await tester.drag(languageStrip, const Offset(-160, 0));
      await tester.pumpAndSettle();

      expect(languageScrollable.position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

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
      find.byKey(const Key('appearance-language-icon-system')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check), findsNothing);
    expect(
      find.byKey(const Key('appearance-language-behavior-description')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('appearance-language-content-note')),
      findsNothing,
    );
    expect(find.text('界面语言跟随设备，服务器内容保持原文'), findsNothing);
    expect(find.text('用户名和网页模式内容保持原样'), findsNothing);

    await tester.tap(
      find.byKey(const Key('appearance-language-option-traditionalChinese')),
    );
    await tester.pumpAndSettle();

    expect(
      appearanceController.languagePreference,
      AppLanguage.traditionalChinese,
    );
    expect(
      find.byKey(const Key('appearance-language-icon-traditionalChinese')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.text('界面使用繁体，原生解析内容转换为繁体'), findsNothing);
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
    await tester.tap(
      find.byKey(const Key('appearance-brightness-option-system')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('主题设置保存失败'), findsOneWidget);
    expect(
      appearanceController.brightnessPreference,
      AppBrightnessPreference.light,
    );
    expect(find.byKey(const Key('appearance-settings-sheet')), findsOneWidget);
    expect(
      find.byKey(const Key('appearance-brightness-icon-light')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check), findsNothing);
  });
}

void _expectSameVerticalCenter(WidgetTester tester, List<Key> keys) {
  final centers = keys
      .map((key) => tester.getCenter(find.byKey(key)).dy)
      .toList(growable: false);
  for (final center in centers.skip(1)) {
    expect(center, closeTo(centers.first, 0.01));
  }
}

void _expectSingleLineButtonLabel(WidgetTester tester, Key buttonKey) {
  final label = tester.widget<Text>(
    find.descendant(of: find.byKey(buttonKey), matching: find.byType(Text)),
  );
  expect(label.maxLines, 1);
  expect(label.softWrap, isFalse);
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

class _FakeUnusedImagesController
    extends ComposerUnusedImageManagementController {
  @override
  Future<ComposerUnusedImageManagementState> build() async {
    return ComposerUnusedImageManagementState(images: const []);
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

  AppThemeFamily get themeFamily => _settings.themeFamily;
  AppBrightnessPreference get brightnessPreference =>
      _settings.brightnessPreference;
  AppLanguage get languagePreference => _settings.languagePreference;

  @override
  Future<AppAppearanceSettings> build() async {
    return _settings;
  }

  @override
  Future<void> setThemeFamily(AppThemeFamily family) async {
    final previous = _settings;
    if (previous.themeFamily == family) {
      return;
    }
    _settings = previous.copyWith(themeFamily: family);
    state = AsyncData(_settings);
    if (!failOnSave) {
      return;
    }
    _settings = previous;
    state = AsyncData(previous);
    throw StateError('save failed');
  }

  @override
  Future<void> setBrightnessPreference(
    AppBrightnessPreference preference,
  ) async {
    final previous = _settings;
    if (previous.brightnessPreference == preference) {
      return;
    }
    _settings = previous.copyWith(brightnessPreference: preference);
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

  @override
  Future<void> writeCookies(Uri uri, Map<String, String> cookies) async {}
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

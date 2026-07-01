import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/settings/app_appearance_controller.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/auth/data/repositories/auth_repository.dart';
import 'package:y300/features/auth/presentation/login_webview_page.dart';
import 'package:y300/features/forum/data/repositories/forum_mode_settings_repository.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/forum/presentation/forum_shell_mode_controller.dart';
import 'package:y300/features/library_shared/presentation/controllers/sync_diagnostic_mode_controller.dart';
import 'package:y300/features/more/presentation/more_page.dart';
import 'package:y300/features/profile/data/models/my_message_models.dart';
import 'package:y300/features/profile/data/models/user_profile_models.dart';
import 'package:y300/features/profile/data/repositories/my_message_repository.dart';
import 'package:y300/features/profile/data/repositories/user_profile_repository.dart';
import 'package:y300/features/thread/presentation/thread_detail_diagnostic_controller.dart';

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
        child: MaterialApp(theme: AppTheme.dark(), home: const MorePage()),
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
        child: const MaterialApp(home: MorePage()),
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
    expect(find.byKey(const Key('more-cache-settings-entry')), findsNothing);
    expect(find.byKey(const Key('more-data-storage-entry')), findsOneWidget);
    expect(find.text('数据与存储'), findsOneWidget);
    expect(find.text('管理图片缓存与下载位置'), findsOneWidget);
    expect(
      find.byKey(const Key('more-reader-settings-placeholder')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('more-about-placeholder')), findsOneWidget);
    expect(find.textContaining('连续快速点击 5 次可开启诊断日志模式'), findsOneWidget);
  });

  testWidgets('MorePage renders logout entry when signed in', (tester) async {
    final repository = _FakeAuthRepository(isLoggedIn: true);
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
          userProfileRepositoryProvider.overrideWithValue(
            const _FakeUserProfileRepository(),
          ),
          myMessageRepositoryProvider.overrideWithValue(
            const _FakeMyMessageRepository(),
          ),
        ],
        child: const MaterialApp(home: MorePage()),
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

    expect(find.byKey(const Key('user-profile-page-list')), findsOneWidget);
    expect(find.text('我的资料'), findsWidgets);

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
        child: const MaterialApp(home: MorePage()),
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

    await tester.tap(find.byKey(const Key('more-forum-mode-option-native')));
    await tester.pumpAndSettle();

    expect(modeRepository.mode, ForumShellMode.native);
    expect(find.text('当前：原生模式'), findsOneWidget);
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
        child: MaterialApp(
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

    expect(
      routeObserver.pushedNames,
      contains(LoginWebViewPage.routeName),
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
        child: const MaterialApp(home: MorePage()),
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

  testWidgets('MorePage toggles diagnostic mode after five quick about taps', (
    tester,
  ) async {
    final controller = _FakeSyncDiagnosticModeController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(isLoggedIn: false),
          ),
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(),
          ),
          syncDiagnosticModeControllerProvider.overrideWith(() => controller),
          appAppearanceControllerProvider.overrideWith(
            () => _FakeAppAppearanceController(),
          ),
        ],
        child: const MaterialApp(home: MorePage()),
      ),
    );
    await tester.pumpAndSettle();

    final aboutTile = find.byKey(const Key('more-about-placeholder'));
    for (var i = 0; i < 5; i++) {
      await tester.tap(aboutTile);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    expect(controller.toggleCount, 1);
    expect(find.textContaining('诊断日志模式已开启'), findsOneWidget);
    expect(
      find.byKey(const Key('more-thread-detail-diagnostic-switch')),
      findsOneWidget,
    );
  });

  testWidgets(
    'MorePage shows and controls thread detail diagnostics in diagnostic mode',
    (tester) async {
      final syncController = _FakeSyncDiagnosticModeController(enabled: true);
      final threadController = _FakeThreadDetailDiagnosticController(
        exportedText: 'entry build log',
      );
      final copiedTexts = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            final data = Map<String, dynamic>.from(call.arguments as Map);
            copiedTexts.add(data['text'] as String);
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(
              _FakeAuthRepository(isLoggedIn: false),
            ),
            forumModeSettingsRepositoryProvider.overrideWithValue(
              _FakeForumModeSettingsRepository(),
            ),
            syncDiagnosticModeControllerProvider.overrideWith(
              () => syncController,
            ),
            threadDetailDiagnosticControllerProvider.overrideWith(
              () => threadController,
            ),
            appAppearanceControllerProvider.overrideWith(
              () => _FakeAppAppearanceController(),
            ),
          ],
          child: const MaterialApp(home: MorePage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('more-thread-detail-diagnostic-switch')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('more-thread-detail-diagnostic-switch')),
      );
      await tester.pumpAndSettle();

      expect(threadController.enabled, isTrue);
      await tester.tap(
        find.byKey(const Key('more-thread-detail-diagnostic-copy-entry')),
      );
      await tester.pumpAndSettle();

      expect(copiedTexts.single, 'entry build log');
      expect(find.text('帖子详情诊断日志已复制'), findsOneWidget);
    },
  );

  testWidgets('MorePage opens appearance settings and changes theme mode', (
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
        child: const MaterialApp(home: MorePage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('more-appearance-entry')));
    await tester.pumpAndSettle();

    expect(find.text('外观与文字'), findsWidgets);
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

    await tester.tap(find.byKey(const Key('appearance-theme-option-dark')));
    await tester.pumpAndSettle();

    expect(appearanceController.themePreference, AppThemePreference.dark);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('当前：深色'), findsOneWidget);
  });

  testWidgets('AppearanceSettingsPage shows snackbar when save fails', (
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
        child: const MaterialApp(home: MorePage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('more-appearance-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('appearance-theme-option-system')));
    await tester.pumpAndSettle();

    expect(find.textContaining('主题设置保存失败'), findsOneWidget);
    expect(appearanceController.themePreference, AppThemePreference.light);
  });
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

class _FakeSyncDiagnosticModeController extends SyncDiagnosticModeController {
  _FakeSyncDiagnosticModeController({bool enabled = false})
    : _enabled = enabled;

  var toggleCount = 0;
  var _enabled = false;

  @override
  Future<bool> build() async {
    return _enabled;
  }

  @override
  Future<bool> toggle() async {
    toggleCount++;
    _enabled = !_enabled;
    state = AsyncData(_enabled);
    return _enabled;
  }
}

class _FakeThreadDetailDiagnosticController
    extends ThreadDetailDiagnosticController {
  _FakeThreadDetailDiagnosticController({this.exportedText = ''});

  final String exportedText;
  var enabled = false;

  @override
  Future<bool> build() async {
    return enabled;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    this.enabled = enabled;
    state = AsyncData(enabled);
  }

  @override
  String exportText() {
    return exportedText;
  }
}

class _FakeAppAppearanceController extends AppAppearanceController {
  _FakeAppAppearanceController({this.failOnSave = false});

  final bool failOnSave;
  var _settings = AppAppearanceSettings.defaults();

  AppThemePreference get themePreference => _settings.themePreference;

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
}

class _FakeUserProfileRepository implements UserProfileRepository {
  const _FakeUserProfileRepository();

  @override
  Future<ApiResult<UserProfileData>> getUserProfile({
    required String uid,
  }) async {
    return getMyProfile(uid: uid);
  }

  @override
  Future<ApiResult<UserProfileData>> getMyProfile({required String uid}) async {
    return const ApiSuccess<UserProfileData>(
      UserProfileData(
        uid: '100',
        username: 'tester',
        title: '我的资料',
        credits: [UserProfileMetric(label: '总积分', value: '65')],
        actions: [
          UserProfileAction(
            label: '消息提醒',
            url: 'https://bbs.yamibo.com/home.php?mod=space&do=pm',
          ),
        ],
        details: [UserProfileDetailItem(label: 'UID', value: '100')],
      ),
    );
  }
}

class _FakeMyMessageRepository implements MyMessageRepository {
  const _FakeMyMessageRepository();

  @override
  Future<ApiResult<MyMessageCenterData>> getMessageCenter() async {
    return const ApiSuccess<MyMessageCenterData>(
      MyMessageCenterData(
        notifications: MyNotificationPage(
          items: <MyNotificationItem>[],
          count: 0,
          page: 1,
          perPage: 30,
        ),
        privateMessages: MyPrivateMessagePage(
          items: <MyPrivateMessageItem>[],
          count: 0,
          page: 1,
          perPage: 15,
        ),
      ),
    );
  }

  @override
  Future<ApiResult<MyNotificationPage>> getNotifications() async {
    return ApiSuccess((await getMessageCenter()).dataOrNull!.notifications);
  }

  @override
  Future<ApiResult<MyPrivateMessagePage>> getPrivateMessages() async {
    return ApiSuccess((await getMessageCenter()).dataOrNull!.privateMessages);
  }
}

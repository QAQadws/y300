import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/auth/data/auth_repository.dart';
import 'package:y300/features/forum/data/forum_mode_settings_repository.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/forum/presentation/forum_shell_mode_controller.dart';
import 'package:y300/features/more/presentation/more_page.dart';

void main() {
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
        ],
        child: const MaterialApp(home: MorePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('更多'), findsWidgets);
    expect(find.byKey(const Key('more-login-entry')), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.byKey(const Key('more-forum-mode-entry')), findsOneWidget);
    expect(find.text('论坛显示模式'), findsOneWidget);
    expect(find.text('当前：WebView 模式'), findsOneWidget);
    expect(find.byKey(const Key('more-cache-settings-entry')), findsNothing);
    expect(find.byKey(const Key('more-data-storage-entry')), findsOneWidget);
    expect(find.text('数据与存储'), findsOneWidget);
    expect(find.text('管理图片缓存与下载位置'), findsOneWidget);
    expect(find.byKey(const Key('more-reader-settings-placeholder')), findsOneWidget);
    expect(find.byKey(const Key('more-about-placeholder')), findsOneWidget);
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
        ],
        child: const MaterialApp(home: MorePage()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('more-login-entry')), findsNothing);
    expect(find.byKey(const Key('more-logout-entry')), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
    expect(find.text('当前账号：tester'), findsOneWidget);

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
        ],
        child: const MaterialApp(home: MorePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前：WebView 模式'), findsOneWidget);

    await tester.tap(find.byKey(const Key('more-forum-mode-entry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('more-forum-mode-option-webview')), findsOneWidget);
    expect(find.byKey(const Key('more-forum-mode-option-native')), findsOneWidget);

    await tester.tap(find.byKey(const Key('more-forum-mode-option-native')));
    await tester.pumpAndSettle();

    expect(modeRepository.mode, ForumShellMode.native);
    expect(find.text('当前：原生模式'), findsOneWidget);
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
    expect(find.byKey(const Key('more-forum-mode-option-native')), findsOneWidget);
  });
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
  _FakeForumModeSettingsRepository({
    this.failOnSave = false,
  });

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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/data/forum_home_repository.dart';
import 'package:y300/features/forum/data/forum_mode_settings_repository.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/forum/presentation/forum_shell_mode_controller.dart';
import 'package:y300/features/forum/presentation/forum_shell_page.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';

void main() {
  testWidgets('ForumShellPage shows webview home page by default', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(mode: ForumShellMode.webview),
          ),
          forumWebViewDriverProvider.overrideWith((ref) => driver),
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
    final driver = _FakeForumWebViewDriver();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumModeSettingsRepositoryProvider.overrideWithValue(
            _FakeForumModeSettingsRepository(mode: ForumShellMode.native),
          ),
          forumHomeRepositoryProvider.overrideWithValue(
            _FakeForumHomeRepository(),
          ),
          forumWebViewDriverProvider.overrideWith((ref) => driver),
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
    final driver = _FakeForumWebViewDriver();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumModeSettingsRepositoryProvider.overrideWithValue(modeRepository),
          forumHomeRepositoryProvider.overrideWithValue(
            _FakeForumHomeRepository(),
          ),
          forumWebViewDriverProvider.overrideWith((ref) => driver),
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

class _FakeForumWebViewDriver implements ForumWebViewDriver {
  @override
  Widget buildWidget({Key? key}) {
    return Container(key: key);
  }

  @override
  Future<void> initialize({required ForumWebViewCallbacks callbacks}) async {}

  @override
  Future<void> load(Uri uri) async {}

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
  Future<String?> readCookieHeader(Uri uri) async {
    return null;
  }
}

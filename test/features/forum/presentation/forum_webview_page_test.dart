import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/data/forum_favorite_repository.dart';
import 'package:y300/features/forum/domain/models/forum_favorite_models.dart';
import 'package:y300/features/composer_shared/data/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/composer_providers.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_external_launcher.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_page.dart';
import 'package:y300/features/posting/data/new_thread_repository.dart';
import 'package:y300/features/posting/data/posting_form_metadata_repository.dart';
import 'package:y300/features/posting/data/posting_providers.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/reply/data/reply_providers.dart';
import 'package:y300/features/reply/data/reply_repository.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/tags/data/forum_tag_repository.dart';
import 'package:y300/features/tags/data/tag_providers.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';
import 'package:y300/features/tags/domain/forum_tag_models.dart';

Matcher containsCssSelector(String selector) {
  final escapedSelector = RegExp.escape(selector);
  return contains(
    RegExp('(^|[^A-Za-z0-9_-])$escapedSelector(?=\$|[^A-Za-z0-9_-])'),
  );
}

void main() {
  testWidgets(
    'ForumWebViewPage waits for bootstrap config before building the real webview',
    (tester) async {
      final driver = _FakeForumWebViewDriver()
        ..capabilityProfile = const ForumWebViewCapabilityProfile(
          engine: ForumWebViewEngine.legacy,
          documentStartMode: ForumWebViewDocumentStartMode.unavailable,
          supportsContentBlockers: false,
          supportsTransparentBackground: false,
          supportsPlatformScrollTuning: false,
          supportsCookieHooks: false,
        );

      await tester.pumpWidget(_buildTestApp(driver: driver));

      expect(
        find.byKey(const Key('forum-webview-bootstrap-placeholder')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('forum-webview-bootstrap-placeholder-list')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('forum-webview-surface')), findsNothing);
      expect(driver.buildWidgetCallCount, 0);

      await tester.pump();

      expect(find.byKey(const Key('forum-webview-surface')), findsOneWidget);
      expect(driver.buildWidgetCallCount, greaterThanOrEqualTo(1));
    },
  );

  testWidgets(
    'ForumWebViewPage shows home app bar and seeds raw cookies before load',
    (tester) async {
      final driver = _FakeForumWebViewDriver();
      final cookieStore = _FakeCookieStore(
        cookies: <String, String>{
          'auth': 'token%2B123',
          'saltkey': 'abc%7Cxyz',
          'removed': 'deleted',
          'empty': '',
        },
      );

      await tester.pumpWidget(
        _buildTestApp(driver: driver, cookieStore: cookieStore),
      );
      await tester.pump();

      expect(find.byKey(const Key('forum-webview-page')), findsOneWidget);
      expect(find.text('百合会论坛'), findsOneWidget);
      expect(find.byKey(const Key('forum-webview-back-button')), findsNothing);
      expect(
        find.byKey(const Key('forum-webview-search-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('forum-webview-more-button')),
        findsOneWidget,
      );
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.systemOverlayStyle?.statusBarColor, Colors.transparent);
      expect(driver.events, <String>[
        'probeCapabilities',
        'initialize',
        'clearCookies',
        'seedCookies',
        'load',
      ]);
      expect(driver.probeCapabilitiesCallCount, 1);
      expect(
        driver.bootstrapConfig?.initialUri.toString(),
        'https://bbs.yamibo.com/index.php?mobile=2',
      );
      expect(
        driver.bootstrapConfig?.capabilityProfile.engine,
        ForumWebViewEngine.advanced,
      );
      final bootstrapConfig = driver.bootstrapConfig!;
      expect(bootstrapConfig.visualPolicy.earlyHiddenSelectors, const <String>{
        '#header-padding',
        '.header.cl',
        '.footer.mt10.cl',
        '.foot.flex-box',
      });
      expect(bootstrapConfig.visualPolicy.lateRemovedSelectors, const <String>{
        '#header-padding',
        '.header.cl',
        '.footer.mt10.cl',
        '.foot.flex-box',
      });
      expect(bootstrapConfig.initialUserScripts, hasLength(1));
      expect(
        bootstrapConfig.initialUserScripts.single.source,
        isNot(containsCssSelector('.foot_height')),
      );
      expect(
        bootstrapConfig.initialUserScripts.single.source,
        isNot(containsCssSelector('.foot-pwa')),
      );
      expect(bootstrapConfig.networkPolicy.customUserAgent, isNull);
      expect(bootstrapConfig.networkPolicy.preferAppLocale, isTrue);
      expect(driver.seededCookies.single.domain, 'bbs.yamibo.com');
      expect(driver.seededCookies.single.cookies, <String, String>{
        'auth': 'token%2B123',
        'saltkey': 'abc%7Cxyz',
      });
      final initialLoadRequest = driver.loadRequests.single;
      final initialHeaderKeys = initialLoadRequest.headers.keys
          .map((key) => key.toLowerCase())
          .toSet();
      expect(initialLoadRequest.headers['Referer'], 'https://bbs.yamibo.com/');
      expect(initialHeaderKeys, contains('accept-language'));
      expect(initialHeaderKeys, isNot(contains('cookie')));
      expect(initialHeaderKeys, isNot(contains('user-agent')));
      expect(
        initialLoadRequest.uri.toString(),
        'https://bbs.yamibo.com/index.php?mobile=2',
      );
    },
  );

  testWidgets(
    'ForumWebViewPage passes early user scripts into bootstrap config when document-start is available',
    (tester) async {
      final driver = _FakeForumWebViewDriver()
        ..capabilityProfile = const ForumWebViewCapabilityProfile(
          engine: ForumWebViewEngine.advanced,
          documentStartMode: ForumWebViewDocumentStartMode.bestEffort,
          supportsContentBlockers: false,
          supportsTransparentBackground: true,
          supportsPlatformScrollTuning: true,
          supportsCookieHooks: true,
        );

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      final bootstrapConfig = driver.bootstrapConfig!;
      expect(
        bootstrapConfig.capabilityProfile.engine,
        ForumWebViewEngine.advanced,
      );
      expect(bootstrapConfig.initialUserScripts, hasLength(1));
      expect(
        bootstrapConfig.initialUserScripts.single.injectionTime,
        ForumWebViewInitialUserScriptInjectionTime.documentStart,
      );
      expect(
        bootstrapConfig.initialUserScripts.single.source,
        contains("window.location.host !== 'bbs.yamibo.com'"),
      );
      expect(
        bootstrapConfig.initialUserScripts.single.source,
        isNot(containsCssSelector('.foot_height')),
      );
      expect(
        bootstrapConfig.initialUserScripts.single.source,
        isNot(containsCssSelector('.foot-pwa')),
      );
      expect(
        bootstrapConfig.initialUserScripts.single.source,
        containsCssSelector('.foot.foot_reply.flex-box.cl'),
      );
      expect(
        bootstrapConfig.initialUserScripts.single.source,
        containsCssSelector('.foot_height_view'),
      );
    },
  );

  testWidgets(
    'ForumWebViewPage cleans baseline chrome when home finishes loading',
    (tester) async {
      final driver = _FakeForumWebViewDriver();

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/index.php?mobile=2',
      );
      await tester.pump();

      expect(driver.scripts.length, 1);
      expect(driver.scripts.single, containsCssSelector('#header-padding'));
      expect(driver.scripts.single, containsCssSelector('.header.cl'));
      expect(driver.scripts.single, isNot(containsCssSelector('.foot_height')));
      expect(driver.scripts.single, isNot(containsCssSelector('.foot-pwa')));

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(driver.scripts.length, 2);
    },
  );

  testWidgets(
    'ForumWebViewPage uses thread-detail cleanup selectors after thread detail navigation',
    (tester) async {
      final driver = _FakeForumWebViewDriver()..title = '主题标题';

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
      );
      await tester.pump();

      expect(driver.scripts.length, 1);
      expect(
        driver.scripts.single,
        containsCssSelector('.foot.foot_reply.flex-box.cl'),
      );
      expect(driver.scripts.single, containsCssSelector('.foot_height_view'));
    },
  );

  testWidgets(
    'ForumWebViewPage uses pwa cleanup selectors after search navigation',
    (tester) async {
      final driver = _FakeForumWebViewDriver()..title = '帖子搜索';

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/search.php?mod=forum&searchid=777&mobile=2',
      );
      await tester.pump();

      expect(driver.scripts.length, 1);
      expect(driver.scripts.single, containsCssSelector('.foot_height'));
      expect(driver.scripts.single, containsCssSelector('.foot-pwa'));
    },
  );

  testWidgets(
    'ForumWebViewPage hides loading mask as soon as the first cleanChrome runs',
    (tester) async {
      final driver = _FakeForumWebViewDriver()
        ..capabilityProfile = const ForumWebViewCapabilityProfile(
          engine: ForumWebViewEngine.advanced,
          documentStartMode: ForumWebViewDocumentStartMode.bestEffort,
          supportsContentBlockers: false,
          supportsTransparentBackground: true,
          supportsPlatformScrollTuning: true,
          supportsCookieHooks: true,
          supportsPageCommitVisible: true,
        );

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      expect(
        find.byKey(const Key('forum-webview-loading-mask')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.byKey(const Key('forum-webview-bootstrap-placeholder-list')),
        findsWidgets,
      );

      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/index.php?mobile=2',
      );
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/index.php?mobile=2',
      );
      await tester.pump();

      // 蒙版应当在 pageFinished 的首次 cleanChrome 完成后立即关闭，
      // 不等 300ms 二次清理 —— 这是连续盲点不再卡住蒙版的关键。
      expect(find.byKey(const Key('forum-webview-loading-mask')), findsNothing);
      expect(driver.scripts.length, 1);

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      // 300ms 二次清理仍会跑（chrome 残留兜底），但不影响蒙版状态。
      expect(driver.scripts.length, 2);
      expect(find.byKey(const Key('forum-webview-loading-mask')), findsNothing);
    },
  );

  testWidgets(
    'ForumWebViewPage hides loading mask immediately on legacy engine too',
    (tester) async {
      final driver = _FakeForumWebViewDriver()
        ..capabilityProfile = const ForumWebViewCapabilityProfile(
          engine: ForumWebViewEngine.legacy,
          documentStartMode: ForumWebViewDocumentStartMode.unavailable,
          supportsContentBlockers: false,
          supportsTransparentBackground: false,
          supportsPlatformScrollTuning: false,
          supportsCookieHooks: false,
          supportsPageCommitVisible: false,
        );

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      expect(
        find.byKey(const Key('forum-webview-loading-mask')),
        findsOneWidget,
      );

      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/index.php?mobile=2',
      );
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/index.php?mobile=2',
      );
      await tester.pump();

      expect(find.byKey(const Key('forum-webview-loading-mask')), findsNothing);
      expect(driver.scripts.length, 1);

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(driver.scripts.length, 2);
      expect(find.byKey(const Key('forum-webview-loading-mask')), findsNothing);
    },
  );

  testWidgets(
    'ForumWebViewPage keeps mask hidden across rapid blind-tap navigation',
    (tester) async {
      // Regression: 用户能从蒙版穿透点击 (IgnorePointer)，连续触发新导航。
      // 旧实现每次 pageStarted 都把 _didCompleteInitialManagedPageLateRepair
      // 复位 + cancel 300ms 定时器 → 节奏快于 (页面加载 + 300ms) 时蒙版永远不消失。
      final driver = _FakeForumWebViewDriver()
        ..capabilityProfile = const ForumWebViewCapabilityProfile(
          engine: ForumWebViewEngine.advanced,
          documentStartMode: ForumWebViewDocumentStartMode.bestEffort,
          supportsContentBlockers: false,
          supportsTransparentBackground: true,
          supportsPlatformScrollTuning: true,
          supportsCookieHooks: true,
          supportsPageCommitVisible: true,
        );

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      expect(
        find.byKey(const Key('forum-webview-loading-mask')),
        findsOneWidget,
      );

      // 首次 pageFinished 完成 → 蒙版应当落下。
      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/index.php?mobile=2',
      );
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/index.php?mobile=2',
      );
      await tester.pump();
      expect(find.byKey(const Key('forum-webview-loading-mask')), findsNothing);

      // 用户盲点版块 A：300ms 二次清理还没跑就被新导航中断。
      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=49&mobile=2',
      );
      await tester.pump(const Duration(milliseconds: 100));

      // 用户继续盲点版块 B：再次中断。
      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
      );
      await tester.pump(const Duration(milliseconds: 100));
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
      );
      await tester.pump();

      // 整个连续盲点过程中蒙版必须保持隐藏，不允许"重新长出来"。
      expect(find.byKey(const Key('forum-webview-loading-mask')), findsNothing);
    },
  );

  testWidgets(
    'ForumWebViewPage home search button loads managed forum search url',
    (tester) async {
      final driver = _FakeForumWebViewDriver();

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      await tester.tap(find.byKey(const Key('forum-webview-search-button')));
      await tester.pumpAndSettle();

      expect(driver.loadedUris.length, 2);
      expect(
        driver.loadedUris.last.toString(),
        'https://bbs.yamibo.com/search.php?mod=forum&mobile=2',
      );
      expect(
        driver.loadRequests.last.headers['Referer'],
        'https://bbs.yamibo.com/index.php?mobile=2',
      );
      expect(
        driver.loadRequests.last.headers.keys
            .map((key) => key.toLowerCase())
            .toSet(),
        isNot(contains('cookie')),
      );
    },
  );

  testWidgets('ForumWebViewPage no longer wraps webview in refresh indicator', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();

    await tester.pumpWidget(_buildTestApp(driver: driver));
    await tester.pump();

    expect(
      find.byKey(const Key('forum-webview-refresh-indicator')),
      findsNothing,
    );
    expect(find.byKey(const Key('forum-webview-refresh-scroll')), findsNothing);
    expect(find.byType(RefreshIndicator), findsNothing);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets(
    'ForumWebViewPage refresh action reloads current page from more menu',
    (tester) async {
      final driver = _FakeForumWebViewDriver();

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      await tester.tap(find.byKey(const Key('forum-webview-more-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('forum-webview-refresh-action')));
      await tester.pumpAndSettle();

      expect(driver.reloadCallCount, 1);
    },
  );

  testWidgets('ForumWebViewPage keeps managed site links inside webview', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();
    final launcher = _FakeForumWebViewExternalLauncher();

    await tester.pumpWidget(_buildTestApp(driver: driver, launcher: launcher));
    await tester.pump();

    final decision = await driver.dispatchNavigationRequest(
      'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
    );

    expect(decision, ForumWebViewNavigationDecision.navigate);
    expect(launcher.launchedUris, isEmpty);
  });

  testWidgets('ForumWebViewPage opens external links in system browser', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();
    final launcher = _FakeForumWebViewExternalLauncher();

    await tester.pumpWidget(_buildTestApp(driver: driver, launcher: launcher));
    await tester.pump();

    final decision = await driver.dispatchNavigationRequest(
      'https://example.com/thread/123',
    );
    await tester.pump();

    expect(decision, ForumWebViewNavigationDecision.prevent);
    expect(
      launcher.launchedUris.single.toString(),
      'https://example.com/thread/123',
    );
  });

  testWidgets('ForumWebViewPage shows snackbar when external launch fails', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();
    final launcher = _FakeForumWebViewExternalLauncher(shouldSucceed: false);

    await tester.pumpWidget(_buildTestApp(driver: driver, launcher: launcher));
    await tester.pump();

    final decision = await driver.dispatchNavigationRequest(
      'https://example.com/thread/123',
    );
    await tester.pumpAndSettle();

    expect(decision, ForumWebViewNavigationDecision.prevent);
    expect(find.text('打开外部链接失败'), findsOneWidget);
  });

  testWidgets('ForumWebViewPage home more menu shows unfavorite action', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();

    await tester.pumpWidget(_buildTestApp(driver: driver));
    await tester.pump();

    await tester.tap(find.byKey(const Key('forum-webview-more-button')));
    await tester.pumpAndSettle();

    expect(find.text('刷新页面'), findsOneWidget);
    expect(
      find.byKey(const Key('forum-webview-refresh-action')),
      findsOneWidget,
    );
    expect(find.text('取消收藏'), findsOneWidget);
    expect(
      find.byKey(const Key('forum-webview-home-unfavorite-action')),
      findsOneWidget,
    );
  });

  testWidgets('ForumWebViewPage home picker displays favorite forum list', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();
    final favoriteRepository = _FakeForumFavoriteRepository(
      favoriteForums: <FavoriteForum>[
        _favoriteForum(fid: '55', favid: 'fav-55', title: '综合区'),
        _favoriteForum(fid: '66', favid: 'fav-66', title: '讨论区'),
      ],
    );

    await tester.pumpWidget(
      _buildTestApp(driver: driver, favoriteRepository: favoriteRepository),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('forum-webview-more-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消收藏'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('forum-favorite-forum-picker')),
      findsOneWidget,
    );
    expect(find.text('综合区'), findsOneWidget);
    expect(find.text('讨论区'), findsOneWidget);
    expect(favoriteRepository.loadCallCount, 1);
  });

  testWidgets('ForumWebViewPage home picker retries after load failure', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();
    final favoriteRepository = _FakeForumFavoriteRepository(
      loadResults: <ApiResult<List<FavoriteForum>>>[
        const ApiFailure<List<FavoriteForum>>(
          ApiError(type: ApiErrorType.network, message: '加载失败'),
        ),
        ApiSuccess<List<FavoriteForum>>(<FavoriteForum>[
          _favoriteForum(fid: '55', favid: 'fav-55', title: '综合区'),
        ]),
      ],
    );

    await tester.pumpWidget(
      _buildTestApp(driver: driver, favoriteRepository: favoriteRepository),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('forum-webview-more-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消收藏'));
    await tester.pumpAndSettle();

    expect(find.text('加载失败'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('forum-favorite-forum-picker-retry')),
    );
    await tester.pumpAndSettle();

    expect(find.text('综合区'), findsOneWidget);
    expect(favoriteRepository.loadCallCount, 2);
  });

  testWidgets(
    'ForumWebViewPage home unfavorite closes picker and reloads home',
    (tester) async {
      final driver = _FakeForumWebViewDriver();
      final favoriteRepository = _FakeForumFavoriteRepository(
        favoriteForums: <FavoriteForum>[
          _favoriteForum(fid: '55', favid: 'fav-55', title: '综合区'),
        ],
      );

      await tester.pumpWidget(
        _buildTestApp(driver: driver, favoriteRepository: favoriteRepository),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('forum-webview-more-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消收藏'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('综合区'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('forum-favorite-forum-picker')),
        findsNothing,
      );
      expect(find.text('取消收藏成功'), findsOneWidget);
      expect(favoriteRepository.unfavoriteCalls, <String>['fav-55']);
      expect(driver.loadedUris.length, 2);
      expect(
        driver.loadedUris.last.toString(),
        'https://bbs.yamibo.com/index.php?mobile=2',
      );
      expect(
        driver.loadRequests.last.headers['Referer'],
        'https://bbs.yamibo.com/index.php?mobile=2',
      );
    },
  );

  testWidgets(
    'ForumWebViewPage shows forum display app bar and loads curForum search',
    (tester) async {
      final driver = _FakeForumWebViewDriver()..title = '页面标题';
      final favoriteRepository = _FakeForumFavoriteRepository();

      await tester.pumpWidget(
        _buildTestApp(driver: driver, favoriteRepository: favoriteRepository),
      );
      await tester.pump();

      driver.canGoBackValue = true;
      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
      );
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('forum-webview-back-button')),
        findsOneWidget,
      );
      expect(find.text('综合区'), findsOneWidget);

      await tester.tap(find.byKey(const Key('forum-webview-search-button')));
      await tester.pumpAndSettle();

      expect(driver.loadedUris.length, 2);
      expect(
        driver.loadedUris.last.toString(),
        'https://bbs.yamibo.com/search.php?mod=curforum&srhfid=55&mobile=2',
      );
      expect(
        driver.loadRequests.last.headers['Referer'],
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
      );
    },
  );

  testWidgets(
    'ForumWebViewPage forum display shows favorite action when forum is not favorited',
    (tester) async {
      final driver = _FakeForumWebViewDriver()..title = '页面标题';
      final favoriteRepository = _FakeForumFavoriteRepository();

      await tester.pumpWidget(
        _buildTestApp(driver: driver, favoriteRepository: favoriteRepository),
      );
      await tester.pump();

      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
      );
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const Key('forum-webview-more-button')));
      await tester.pumpAndSettle();

      expect(find.text('收藏本版'), findsOneWidget);
    },
  );

  testWidgets(
    'ForumWebViewPage forum display shows unfavorite action when forum is favorited',
    (tester) async {
      final driver = _FakeForumWebViewDriver()..title = '页面标题';
      final favoriteRepository = _FakeForumFavoriteRepository(
        favoriteForums: <FavoriteForum>[
          _favoriteForum(fid: '55', favid: 'fav-55', title: '综合区'),
        ],
      );

      await tester.pumpWidget(
        _buildTestApp(driver: driver, favoriteRepository: favoriteRepository),
      );
      await tester.pump();

      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
      );
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const Key('forum-webview-more-button')));
      await tester.pumpAndSettle();

      expect(find.text('取消收藏'), findsOneWidget);
    },
  );

  testWidgets(
    'ForumWebViewPage forum display favorite action reloads current page',
    (tester) async {
      final driver = _FakeForumWebViewDriver()..title = '页面标题';
      final favoriteRepository = _FakeForumFavoriteRepository();
      const forumDisplayUrl =
          'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2';

      await tester.pumpWidget(
        _buildTestApp(driver: driver, favoriteRepository: favoriteRepository),
      );
      await tester.pump();

      await driver.dispatchPageStarted(forumDisplayUrl);
      await driver.dispatchPageFinished(forumDisplayUrl);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const Key('forum-webview-more-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('收藏本版'));
      await tester.pumpAndSettle();

      expect(favoriteRepository.favoriteCalls, <String>['55']);
      expect(find.text('收藏成功'), findsOneWidget);
      expect(driver.loadedUris.last.toString(), forumDisplayUrl);
      expect(driver.loadRequests.last.headers['Referer'], forumDisplayUrl);
    },
  );

  testWidgets(
    'ForumWebViewPage forum display unfavorite action reloads current page',
    (tester) async {
      final driver = _FakeForumWebViewDriver()..title = '页面标题';
      final favoriteRepository = _FakeForumFavoriteRepository(
        favoriteForums: <FavoriteForum>[
          _favoriteForum(fid: '55', favid: 'fav-55', title: '综合区'),
        ],
      );
      const forumDisplayUrl =
          'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2';

      await tester.pumpWidget(
        _buildTestApp(driver: driver, favoriteRepository: favoriteRepository),
      );
      await tester.pump();

      await driver.dispatchPageStarted(forumDisplayUrl);
      await driver.dispatchPageFinished(forumDisplayUrl);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const Key('forum-webview-more-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消收藏'));
      await tester.pumpAndSettle();

      expect(favoriteRepository.unfavoriteCalls, <String>['fav-55']);
      expect(find.text('取消收藏成功'), findsOneWidget);
      expect(driver.loadedUris.last.toString(), forumDisplayUrl);
      expect(driver.loadRequests.last.headers['Referer'], forumDisplayUrl);
    },
  );

  testWidgets(
    'ForumWebViewPage thread detail falls back to forum search when fid is unknown',
    (tester) async {
      final driver = _FakeForumWebViewDriver()..title = '主题标题';

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      driver.canGoBackValue = true;
      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
      );
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
      );
      await tester.pump();

      expect(
        find.byKey(const Key('forum-webview-back-button')),
        findsOneWidget,
      );
      expect(find.text('主题标题'), findsOneWidget);
      expect(
        find.byKey(const Key('forum-webview-thread-reply-button')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('forum-webview-search-button')));
      await tester.pumpAndSettle();

      expect(driver.loadedUris.length, 2);
      expect(
        driver.loadedUris.last.toString(),
        'https://bbs.yamibo.com/search.php?mod=forum&mobile=2',
      );
    },
  );

  testWidgets(
    'ForumWebViewPage hides thread reply button outside thread detail',
    (tester) async {
      final driver = _FakeForumWebViewDriver();

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      expect(
        find.byKey(const Key('forum-webview-thread-reply-button')),
        findsNothing,
      );

      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
      );
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
      );
      await tester.pump();

      expect(
        find.byKey(const Key('forum-webview-thread-reply-button')),
        findsNothing,
      );

      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/search.php?mod=forum&mobile=2',
      );
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/search.php?mod=forum&searchid=777&mobile=2',
      );
      await tester.pump();

      expect(
        find.byKey(const Key('forum-webview-thread-reply-button')),
        findsNothing,
      );
    },
  );

  testWidgets('ForumWebViewPage opens thread reply composer with fid and tid', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver()..title = '主题标题';
    final replyRepository = _FakeReplyRepository();

    await tester.pumpWidget(
      _buildTestApp(driver: driver, replyRepository: replyRepository),
    );
    await tester.pump();

    await driver.dispatchPageStarted(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&fid=55&mobile=2',
    );
    await driver.dispatchPageFinished(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&fid=55&mobile=2',
    );
    await tester.pump();

    expect(
      find.byKey(const Key('forum-webview-thread-reply-button')),
      findsOneWidget,
    );
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    final actionKeys = appBar.actions!
        .map((action) => action.key)
        .whereType<Key>()
        .toList(growable: false);
    expect(
      actionKeys,
      containsAllInOrder(const <Key>[
        Key('forum-webview-search-button'),
        Key('forum-webview-thread-reply-button'),
        Key('forum-webview-more-button'),
      ]),
    );

    await tester.tap(
      find.byKey(const Key('forum-webview-thread-reply-button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('回复帖子'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('reply-composer-message-input')),
      '来自 WebView 的回复',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('reply-composer-send-button')));
    await tester.pumpAndSettle();

    expect(replyRepository.sentDrafts, hasLength(1));
    expect(replyRepository.sentDrafts.single.fid, '55');
    expect(replyRepository.sentDrafts.single.tid, '123');
    expect(replyRepository.sentDrafts.single.message, '来自 WebView 的回复');
    expect(driver.reloadCallCount, 1);
    expect(find.text('回复发布成功'), findsOneWidget);
  });

  testWidgets(
    'ForumWebViewPage intercepts post reply navigation and reloads after sent',
    (tester) async {
      final driver = _FakeForumWebViewDriver()..title = '主题标题';
      final replyRepository = _FakeReplyRepository();

      await tester.pumpWidget(
        _buildTestApp(driver: driver, replyRepository: replyRepository),
      );
      await tester.pump();

      final decision = await driver.dispatchNavigationRequest(
        'https://bbs.yamibo.com/forum.php?mod=post&action=reply'
        '&fid=55&tid=123&repquote=41554317'
        '&extra=page%3D1&page=1&mobile=2',
      );
      await tester.pumpAndSettle();

      expect(decision, ForumWebViewNavigationDecision.prevent);
      expect(find.text('回复楼层'), findsOneWidget);
      expect(replyRepository.prepareCallCount, 1);
      expect(
        find.byKey(const Key('reply-composer-reference-banner')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('reply-composer-message-input')),
        '来自 WebView 的楼层回复',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('reply-composer-send-button')));
      await tester.pumpAndSettle();

      expect(replyRepository.sentDrafts, hasLength(1));
      expect(replyRepository.sentDrafts.single.fid, '55');
      expect(replyRepository.sentDrafts.single.tid, '123');
      expect(replyRepository.sentDrafts.single.formHash, 'prepared-formhash');
      expect(
        replyRepository.sentDrafts.single.noticeTrimStr,
        '[quote]引用[/quote]',
      );
      expect(replyRepository.sentDrafts.single.repPost, '41554317');
      expect(driver.reloadCallCount, 1);
    },
  );

  testWidgets(
    'ForumWebViewPage intercepts newthread navigation and reloads after sent',
    (tester) async {
      final driver = _FakeForumWebViewDriver()..title = '主题标题';
      final newThreadRepository = _FakeNewThreadRepository();
      final metadataRepository = _FakePostingFormMetadataRepository(
        metadata: const NewThreadFormMetadata(
          fid: '33',
          forumName: '日常版',
          formHash: 'fh',
          threadTypes: <ThreadType>[],
          threadSorts: <ThreadSort>[],
          typeRequired: false,
          sortRequired: false,
        ),
      );

      await tester.pumpWidget(
        _buildTestApp(
          driver: driver,
          newThreadRepository: newThreadRepository,
          postingFormMetadataRepository: metadataRepository,
        ),
      );
      await tester.pump();

      // WebView 拦截到形如 forum.php?mod=post&action=newthread&fid=33&mobile=2 的 URL，
      // 应该 prevent 并打开自制发帖页。`&amp;` HTML 转义场景同时覆盖。
      final decision = await driver.dispatchNavigationRequest(
        'https://bbs.yamibo.com/forum.php?mod=post&amp;action=newthread'
        '&amp;fid=33&amp;mobile=2',
      );
      await tester.pumpAndSettle();

      expect(decision, ForumWebViewNavigationDecision.prevent);
      expect(find.text('发帖 — 日常版'), findsOneWidget);
      expect(metadataRepository.callCount, 1);

      await tester.enterText(
        find.byKey(const Key('posting-composer-subject-input')),
        '来自 WebView 的标题',
      );
      await tester.enterText(
        find.byKey(const Key('posting-composer-message-input')),
        '来自 WebView 的正文',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('posting-composer-send-button')));
      await tester.pumpAndSettle();

      expect(newThreadRepository.submittedPayloads, hasLength(1));
      expect(newThreadRepository.submittedPayloads.single.fid, '33');
      expect(
        newThreadRepository.submittedPayloads.single.subject,
        '来自 WebView 的标题',
      );
      expect(
        newThreadRepository.submittedPayloads.single.message,
        '来自 WebView 的正文',
      );
      expect(newThreadRepository.submittedPayloads.single.formHash, 'fh');
      // 提交成功 → SnackBar + WebView reload。
      expect(driver.reloadCallCount, 1);
      expect(find.text('发布成功'), findsOneWidget);
    },
  );

  testWidgets(
    'ForumWebViewPage does not intercept reply newthread without fid',
    (tester) async {
      final driver = _FakeForumWebViewDriver()..title = '论坛首页';
      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      // mod=post & action=newthread 但 fid 为空 → navigator 返回 null，
      // 当前是站内 URL 应该回退到 navigate（让 WebView 自己渲染兜底）。
      final decision = await driver.dispatchNavigationRequest(
        'https://bbs.yamibo.com/forum.php?mod=post&action=newthread',
      );

      expect(decision, ForumWebViewNavigationDecision.navigate);
      expect(find.text('发帖 — 日常版'), findsNothing);
    },
  );

  testWidgets(
    'ForumWebViewPage thread detail more menu shows author order and home actions',
    (tester) async {
      final driver = _FakeForumWebViewDriver()
        ..title = '主题标题'
        ..javaScriptResult = jsonEncode(
          jsonEncode(<String, String?>{
            'authorOnlyHref':
                'forum.php?mod=viewthread&tid=123&authorid=9&mobile=2',
            'normalThreadHref': null,
            'reverseOrderHref':
                'forum.php?mod=viewthread&tid=123&ordertype=1&mobile=2',
            'normalOrderHref': null,
          }),
        );

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
      );
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('forum-webview-more-button')));
      await tester.pumpAndSettle();

      expect(find.text('刷新页面'), findsOneWidget);
      expect(find.text('只看楼主'), findsOneWidget);
      expect(find.text('倒序浏览'), findsOneWidget);
      expect(find.text('返回首页'), findsOneWidget);
      expect(
        driver.returningScripts.single,
        contains('#nav-more-menu .nav-more-item'),
      );
    },
  );

  testWidgets(
    'ForumWebViewPage thread detail author filter action loads author-only url',
    (tester) async {
      final driver = _FakeForumWebViewDriver()
        ..title = '主题标题'
        ..javaScriptResult = jsonEncode(
          jsonEncode(<String, String?>{
            'authorOnlyHref':
                'forum.php?mod=viewthread&tid=123&authorid=9&mobile=2',
          }),
        );

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
      );
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('forum-webview-more-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('只看楼主'));
      await tester.pumpAndSettle();

      expect(
        driver.loadedUris.last.toString(),
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&authorid=9&mobile=2',
      );
    },
  );

  testWidgets(
    'ForumWebViewPage thread detail already author-only shows normal thread action',
    (tester) async {
      final driver = _FakeForumWebViewDriver()..title = '主题标题';

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&authorid=9&mobile=2',
      );
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&authorid=9&mobile=2',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('forum-webview-more-button')));
      await tester.pumpAndSettle();

      expect(find.text('看全部'), findsOneWidget);

      await tester.tap(find.text('看全部'));
      await tester.pumpAndSettle();

      expect(
        driver.loadedUris.last.toString(),
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
      );
    },
  );

  testWidgets(
    'ForumWebViewPage thread detail order action toggles between reverse and normal order',
    (tester) async {
      final driver = _FakeForumWebViewDriver()..title = '主题标题';

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
      );
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('forum-webview-more-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('倒序浏览'));
      await tester.pumpAndSettle();

      expect(
        driver.loadedUris.last.toString(),
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2&ordertype=1',
      );

      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&ordertype=1&mobile=2',
      );
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&ordertype=1&mobile=2',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('forum-webview-more-button')));
      await tester.pumpAndSettle();

      expect(find.text('正序浏览'), findsOneWidget);

      await tester.tap(find.text('正序浏览'));
      await tester.pumpAndSettle();

      expect(
        driver.loadedUris.last.toString(),
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
      );
    },
  );

  testWidgets('ForumWebViewPage thread detail more menu can load home', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver()..title = '主题标题';

    await tester.pumpWidget(_buildTestApp(driver: driver));
    await tester.pump();

    await driver.dispatchPageStarted(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );
    await driver.dispatchPageFinished(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('forum-webview-more-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('返回首页'));
    await tester.pumpAndSettle();

    expect(
      driver.loadedUris.last.toString(),
      'https://bbs.yamibo.com/index.php?mobile=2',
    );
    expect(
      driver.loadRequests.last.headers['Referer'],
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
    );
  });

  testWidgets(
    'ForumWebViewPage thread detail uses curForum search when fid is known',
    (tester) async {
      final driver = _FakeForumWebViewDriver()..title = '主题标题';

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      driver.canGoBackValue = true;
      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&fid=55&mobile=2',
      );
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&fid=55&mobile=2',
      );
      await tester.pump();

      expect(
        find.byKey(const Key('forum-webview-back-button')),
        findsOneWidget,
      );
      expect(find.text('综合区'), findsOneWidget);

      await tester.tap(find.byKey(const Key('forum-webview-search-button')));
      await tester.pumpAndSettle();

      expect(driver.loadedUris.length, 2);
      expect(
        driver.loadedUris.last.toString(),
        'https://bbs.yamibo.com/search.php?mod=curforum&srhfid=55&mobile=2',
      );
      expect(
        driver.loadRequests.last.headers['Referer'],
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&fid=55&mobile=2',
      );
    },
  );

  testWidgets(
    'ForumWebViewPage search app bar uses forum search title and hides search button',
    (tester) async {
      final driver = _FakeForumWebViewDriver()..title = '帖子搜索';

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      driver.canGoBackValue = true;
      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/search.php?mod=forum&mobile=2',
      );
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/search.php?mod=forum&searchid=777&mobile=2',
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('forum-webview-back-button')),
        findsOneWidget,
      );
      expect(find.text('论坛搜索'), findsOneWidget);
      expect(
        find.byKey(const Key('forum-webview-search-button')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('forum-webview-more-button')));
      await tester.pumpAndSettle();

      expect(find.text('刷新页面'), findsOneWidget);
      expect(find.text('返回首页'), findsOneWidget);
    },
  );

  testWidgets(
    'ForumWebViewPage search app bar uses board name search title for curforum scope',
    (tester) async {
      final driver = _FakeForumWebViewDriver()..title = '帖子搜索';

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      driver.canGoBackValue = true;
      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/search.php?mod=curforum&srhfid=55&mobile=2',
      );
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/search.php?mod=curforum&srhfid=55&mobile=2',
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('综合区搜索'), findsOneWidget);
      expect(
        find.byKey(const Key('forum-webview-search-button')),
        findsNothing,
      );
    },
  );

  testWidgets('ForumWebViewPage search more action loads home', (tester) async {
    final driver = _FakeForumWebViewDriver()..title = '帖子搜索';

    await tester.pumpWidget(_buildTestApp(driver: driver));
    await tester.pump();

    await driver.dispatchPageStarted(
      'https://bbs.yamibo.com/search.php?mod=forum&mobile=2',
    );
    await driver.dispatchPageFinished(
      'https://bbs.yamibo.com/search.php?mod=forum&searchid=777&mobile=2',
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('forum-webview-more-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('返回首页'));
    await tester.pumpAndSettle();

    expect(
      driver.loadedUris.last.toString(),
      'https://bbs.yamibo.com/index.php?mobile=2',
    );
    expect(
      driver.loadRequests.last.headers['Referer'],
      'https://bbs.yamibo.com/search.php?mod=forum&searchid=777&mobile=2',
    );
  });

  testWidgets(
    'ForumWebViewPage search page still cleans chrome when loading finishes',
    (tester) async {
      final driver = _FakeForumWebViewDriver()..title = '帖子搜索';

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/search.php?mod=forum&searchid=777&mobile=2',
      );
      await tester.pump();

      expect(driver.scripts.length, 1);
    },
  );

  testWidgets(
    'ForumWebViewPage back button uses driver.goBack when history exists',
    (tester) async {
      final driver = _FakeForumWebViewDriver()..title = '页面标题';

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      driver.canGoBackValue = true;
      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
      );
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
      );
      await tester.pump();

      await tester.tap(find.byType(BackButton));
      await tester.pump();

      expect(driver.goBackCallCount, 1);
      expect(
        driver.loadedUris.single.toString(),
        'https://bbs.yamibo.com/index.php?mobile=2',
      );
    },
  );

  testWidgets(
    'ForumWebViewPage back button loads home when history is unavailable',
    (tester) async {
      final driver = _FakeForumWebViewDriver()..title = '页面标题';

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      driver.canGoBackValue = false;
      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
      );
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
      );
      await tester.pump();

      await tester.tap(find.byType(BackButton));
      await tester.pump();

      expect(driver.goBackCallCount, 0);
      expect(driver.loadedUris.length, 2);
      expect(
        driver.loadedUris.last.toString(),
        'https://bbs.yamibo.com/index.php?mobile=2',
      );
    },
  );

  testWidgets(
    'ForumWebViewPage system back uses driver.goBack when history exists',
    (tester) async {
      final driver = _FakeForumWebViewDriver()..title = '页面标题';

      await tester.pumpWidget(_buildRoutedTestApp(driver: driver));
      await tester.tap(find.byKey(const Key('open-forum-webview-page')));
      await tester.pumpAndSettle();

      driver.canGoBackValue = true;
      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
      );
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2',
      );
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(driver.goBackCallCount, 1);
      expect(find.byKey(const Key('forum-webview-page')), findsOneWidget);
    },
  );

  testWidgets(
    'ForumWebViewPage system back loads home when history is unavailable away from home',
    (tester) async {
      final driver = _FakeForumWebViewDriver()..title = '页面标题';

      await tester.pumpWidget(_buildRoutedTestApp(driver: driver));
      await tester.tap(find.byKey(const Key('open-forum-webview-page')));
      await tester.pumpAndSettle();

      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
      );
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=123&mobile=2',
      );
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(driver.goBackCallCount, 0);
      expect(
        driver.loadedUris.last.toString(),
        'https://bbs.yamibo.com/index.php?mobile=2',
      );
      expect(find.byKey(const Key('forum-webview-page')), findsOneWidget);
    },
  );

  testWidgets(
    'ForumWebViewPage system back allows route pop on home without history',
    (tester) async {
      final driver = _FakeForumWebViewDriver();

      await tester.pumpWidget(_buildRoutedTestApp(driver: driver));
      await tester.tap(find.byKey(const Key('open-forum-webview-page')));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('forum-webview-page')), findsNothing);
      expect(find.byKey(const Key('open-forum-webview-page')), findsOneWidget);
    },
  );
}

Widget _buildTestApp({
  required _FakeForumWebViewDriver driver,
  CookieStore? cookieStore,
  ForumTagRepository? tagRepository,
  ForumFavoriteRepository? favoriteRepository,
  ForumWebViewExternalLauncher? launcher,
  ReplyRepository? replyRepository,
  ComposerDraftRepository? replyDraftRepository,
  PostingFormMetadataRepository? postingFormMetadataRepository,
  NewThreadRepository? newThreadRepository,
}) {
  return ProviderScope(
    overrides: [
      forumWebViewDriverProvider.overrideWith((ref) => driver),
      forumWebViewExternalLauncherProvider.overrideWithValue(
        launcher ?? _FakeForumWebViewExternalLauncher(),
      ),
      cookieStoreProvider.overrideWithValue(cookieStore ?? _FakeCookieStore()),
      forumTagRepositoryProvider.overrideWithValue(
        tagRepository ?? _FakeForumTagRepository(),
      ),
      forumFavoriteRepositoryProvider.overrideWithValue(
        favoriteRepository ?? _FakeForumFavoriteRepository(),
      ),
      replyRepositoryProvider.overrideWithValue(
        replyRepository ?? _FakeReplyRepository(),
      ),
      composerDraftRepositoryProvider.overrideWithValue(
        replyDraftRepository ?? _MemoryComposerDraftRepository(),
      ),
      postingFormMetadataRepositoryProvider.overrideWithValue(
        postingFormMetadataRepository ?? _FakePostingFormMetadataRepository(),
      ),
      newThreadRepositoryProvider.overrideWithValue(
        newThreadRepository ?? _FakeNewThreadRepository(),
      ),
    ],
    child: const MaterialApp(home: ForumWebViewPage()),
  );
}

Widget _buildRoutedTestApp({
  required _FakeForumWebViewDriver driver,
  CookieStore? cookieStore,
  ForumTagRepository? tagRepository,
  ForumFavoriteRepository? favoriteRepository,
  ForumWebViewExternalLauncher? launcher,
  ReplyRepository? replyRepository,
  ComposerDraftRepository? replyDraftRepository,
  PostingFormMetadataRepository? postingFormMetadataRepository,
  NewThreadRepository? newThreadRepository,
}) {
  return ProviderScope(
    overrides: [
      forumWebViewDriverProvider.overrideWith((ref) => driver),
      forumWebViewExternalLauncherProvider.overrideWithValue(
        launcher ?? _FakeForumWebViewExternalLauncher(),
      ),
      cookieStoreProvider.overrideWithValue(cookieStore ?? _FakeCookieStore()),
      forumTagRepositoryProvider.overrideWithValue(
        tagRepository ?? _FakeForumTagRepository(),
      ),
      forumFavoriteRepositoryProvider.overrideWithValue(
        favoriteRepository ?? _FakeForumFavoriteRepository(),
      ),
      replyRepositoryProvider.overrideWithValue(
        replyRepository ?? _FakeReplyRepository(),
      ),
      composerDraftRepositoryProvider.overrideWithValue(
        replyDraftRepository ?? _MemoryComposerDraftRepository(),
      ),
      postingFormMetadataRepositoryProvider.overrideWithValue(
        postingFormMetadataRepository ?? _FakePostingFormMetadataRepository(),
      ),
      newThreadRepositoryProvider.overrideWithValue(
        newThreadRepository ?? _FakeNewThreadRepository(),
      ),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open-forum-webview-page'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ForumWebViewPage(),
                    ),
                  );
                },
                child: const Text('打开论坛 WebView'),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _FakeForumWebViewDriver implements ForumWebViewDriver {
  final List<String> events = <String>[];
  final List<Uri> loadedUris = <Uri>[];
  final List<_LoadRequestRecord> loadRequests = <_LoadRequestRecord>[];
  final List<String> scripts = <String>[];
  final List<String> returningScripts = <String>[];
  final List<_SeededCookieRecord> seededCookies = <_SeededCookieRecord>[];
  String? title;
  Object? javaScriptResult;
  bool canGoBackValue = false;
  int goBackCallCount = 0;
  int reloadCallCount = 0;
  int buildWidgetCallCount = 0;
  int probeCapabilitiesCallCount = 0;
  ForumWebViewBootstrapConfig? bootstrapConfig;
  ForumWebViewCapabilityProfile capabilityProfile =
      const ForumWebViewCapabilityProfile(
        engine: ForumWebViewEngine.advanced,
        documentStartMode: ForumWebViewDocumentStartMode.reliable,
        supportsContentBlockers: false,
        supportsTransparentBackground: true,
        supportsPlatformScrollTuning: true,
        supportsCookieHooks: true,
        supportsPageCommitVisible: true,
      );
  ForumWebViewCallbacks? _callbacks;

  @override
  Widget buildWidget({Key? key}) {
    buildWidgetCallCount += 1;
    return Container(key: key);
  }

  Future<void> dispatchPageStarted(String url) async {
    final callbacks = _callbacks;
    if (callbacks == null) {
      return;
    }
    callbacks.onPageStarted(url);
  }

  Future<void> dispatchPageFinished(String url) async {
    final callbacks = _callbacks;
    if (callbacks == null) {
      return;
    }
    await callbacks.onPageFinished(url);
  }

  Future<void> dispatchPageCommitVisible(String url) async {
    final onPageCommitVisible = _callbacks?.onPageCommitVisible;
    if (onPageCommitVisible == null) {
      return;
    }
    onPageCommitVisible(url);
  }

  Future<ForumWebViewNavigationDecision?> dispatchNavigationRequest(
    String url,
  ) async {
    final callbacks = _callbacks;
    if (callbacks == null) {
      return null;
    }
    return callbacks.onNavigationRequest(url);
  }

  @override
  Future<ForumWebViewCapabilityProfile> probeCapabilities() async {
    probeCapabilitiesCallCount += 1;
    events.add('probeCapabilities');
    return capabilityProfile;
  }

  @override
  Future<void> initialize({
    required ForumWebViewCallbacks callbacks,
    required ForumWebViewBootstrapConfig bootstrapConfig,
  }) async {
    events.add('initialize');
    this.bootstrapConfig = bootstrapConfig;
    _callbacks = callbacks;
  }

  @override
  Future<void> load(Uri uri, {Map<String, String> headers = const {}}) async {
    events.add('load');
    loadedUris.add(uri);
    loadRequests.add(
      _LoadRequestRecord(uri: uri, headers: Map<String, String>.from(headers)),
    );
  }

  @override
  Future<void> reload() async {
    reloadCallCount += 1;
  }

  @override
  Future<bool> clearCookies() async {
    events.add('clearCookies');
    return true;
  }

  @override
  Future<String?> getTitle() async {
    return title;
  }

  @override
  Future<bool> canGoBack() async {
    return canGoBackValue;
  }

  @override
  Future<void> goBack() async {
    goBackCallCount += 1;
  }

  @override
  Future<void> runJavaScript(String script) async {
    scripts.add(script);
  }

  @override
  Future<Object?> runJavaScriptReturningResult(String script) async {
    returningScripts.add(script);
    return javaScriptResult;
  }

  @override
  Future<void> seedCookies({
    required String domain,
    required Map<String, String> cookies,
    String path = '/',
  }) async {
    events.add('seedCookies');
    seededCookies.add(
      _SeededCookieRecord(
        domain: domain,
        cookies: Map<String, String>.from(cookies),
        path: path,
      ),
    );
  }
}

class _FakeForumWebViewExternalLauncher
    implements ForumWebViewExternalLauncher {
  _FakeForumWebViewExternalLauncher({this.shouldSucceed = true});

  final bool shouldSucceed;
  final List<Uri> launchedUris = <Uri>[];

  @override
  Future<bool> launch(Uri uri) async {
    launchedUris.add(uri);
    return shouldSucceed;
  }
}

class _MemoryComposerDraftRepository implements ComposerDraftRepository {
  final Map<String, ComposerDraftSnapshot> _drafts =
      <String, ComposerDraftSnapshot>{};

  @override
  Future<void> deleteDraft(ComposerDraftIdentity identity) async {
    _drafts.remove(identity.storageKey);
  }

  @override
  Future<List<ComposerDraftSnapshot>> listDraftsForThread({
    required String fid,
    required String tid,
  }) async {
    return _drafts.values
        .where(
          (draft) => draft.identity.fid == fid && draft.identity.tid == tid,
        )
        .toList(growable: false);
  }

  @override
  Future<ComposerDraftSnapshot?> loadDraft(
    ComposerDraftIdentity identity,
  ) async {
    return _drafts[identity.storageKey];
  }

  @override
  Future<ComposerDraftPruneResult> pruneDrafts({
    Duration maxAge = const Duration(days: 30),
    int maxCount = 100,
  }) async {
    return ComposerDraftPruneResult(removedCount: 0, keptCount: _drafts.length);
  }

  @override
  Future<void> saveDraft(ComposerDraftSnapshot draft) async {
    if (draft.isEmpty) {
      _drafts.remove(draft.identity.storageKey);
      return;
    }
    _drafts[draft.identity.storageKey] = draft;
  }
}

class _FakeReplyRepository implements ReplyRepository {
  _FakeReplyRepository({
    ApiResult<ReplySubmissionResult>? result,
    ApiResult<ReplyPreparation>? preparationResult,
  }) : result =
           result ??
           const ApiSuccess<ReplySubmissionResult>(
             ReplySubmissionResult(message: '回复发布成功'),
           ),
       preparationResult =
           preparationResult ??
           const ApiSuccess<ReplyPreparation>(
             ReplyPreparation(
               target: ReplyTarget.post(fid: '55', tid: '123', pid: '41554317'),
               reference: ReplyReference(
                 formHash: 'prepared-formhash',
                 noticeAuthor: 'notice-token',
                 noticeTrimStr: '[quote]引用[/quote]',
                 noticeAuthorMsg: '引用正文',
                 repPid: '41554317',
                 repPost: '41554317',
               ),
             ),
           );

  final ApiResult<ReplySubmissionResult> result;
  final ApiResult<ReplyPreparation> preparationResult;
  final List<ReplyDraft> sentDrafts = <ReplyDraft>[];
  int prepareCallCount = 0;

  @override
  Future<ApiResult<ReplySubmissionResult>> sendReply({
    required ReplyDraft draft,
  }) async {
    sentDrafts.add(draft);
    return result;
  }

  @override
  Future<ApiResult<ReplyPreparation>> preparePostReply({
    required Uri replyFormUri,
  }) async {
    prepareCallCount += 1;
    return preparationResult;
  }
}

class _SeededCookieRecord {
  const _SeededCookieRecord({
    required this.domain,
    required this.cookies,
    required this.path,
  });

  final String domain;
  final Map<String, String> cookies;
  final String path;
}

class _LoadRequestRecord {
  const _LoadRequestRecord({required this.uri, required this.headers});

  final Uri uri;
  final Map<String, String> headers;
}

class _FakeCookieStore extends CookieStore {
  _FakeCookieStore({this.cookies = const <String, String>{}});

  final Map<String, String> cookies;

  @override
  Future<Map<String, String>> readCookieMap(Uri uri) async {
    return Map<String, String>.from(cookies);
  }

  @override
  Future<String?> readCookieHeader(Uri uri) async {
    return null;
  }
}

class _FakeForumTagRepository implements ForumTagRepository {
  @override
  Future<ForumTagLookup> loadLookup() async {
    return ForumTagLookup(const <ForumBoardTagSet>[
      ForumBoardTagSet(fid: '55', name: '综合区', tags: <ForumTagDefinition>[]),
    ]);
  }
}

FavoriteForum _favoriteForum({
  required String fid,
  required String favid,
  required String title,
}) {
  return FavoriteForum(
    favid: favid,
    fid: fid,
    title: title,
    description: '',
    threads: 0,
    posts: 0,
    todayPosts: 0,
  );
}

class _FakeForumFavoriteRepository implements ForumFavoriteRepository {
  _FakeForumFavoriteRepository({
    List<FavoriteForum>? favoriteForums,
    List<ApiResult<List<FavoriteForum>>>? loadResults,
    ApiResult<ForumFavoriteMutationResult>? favoriteResult,
    ApiResult<ForumFavoriteMutationResult>? unfavoriteResult,
  }) : favoriteForums = List<FavoriteForum>.from(
         favoriteForums ?? const <FavoriteForum>[],
       ),
       _loadResults = List<ApiResult<List<FavoriteForum>>>.from(
         loadResults ?? const <ApiResult<List<FavoriteForum>>>[],
       ),
       _favoriteResult = favoriteResult,
       _unfavoriteResult = unfavoriteResult;

  List<FavoriteForum> favoriteForums;
  final List<ApiResult<List<FavoriteForum>>> _loadResults;
  final ApiResult<ForumFavoriteMutationResult>? _favoriteResult;
  final ApiResult<ForumFavoriteMutationResult>? _unfavoriteResult;

  final List<String> favoriteCalls = <String>[];
  final List<String> unfavoriteCalls = <String>[];
  int loadCallCount = 0;

  @override
  Future<ApiResult<ForumFavoriteMutationResult>> favoriteForum({
    required String fid,
  }) async {
    favoriteCalls.add(fid);
    final result =
        _favoriteResult ??
        const ApiSuccess<ForumFavoriteMutationResult>(
          ForumFavoriteMutationResult(message: '收藏成功'),
        );
    if (result.isSuccess) {
      favoriteForums = <FavoriteForum>[
        ...favoriteForums.where((item) => item.fid != fid),
        _favoriteForum(fid: fid, favid: 'fav-$fid', title: '版块$fid'),
      ];
    }
    return result;
  }

  @override
  Future<ApiResult<List<FavoriteForum>>> loadFavoriteForums() async {
    loadCallCount += 1;
    if (_loadResults.isNotEmpty) {
      final result = _loadResults.removeAt(0);
      if (result case ApiSuccess<List<FavoriteForum>>(:final data)) {
        favoriteForums = List<FavoriteForum>.from(data);
      }
      return result;
    }
    return ApiSuccess<List<FavoriteForum>>(
      List<FavoriteForum>.from(favoriteForums),
    );
  }

  @override
  Future<ApiResult<ForumFavoriteMutationResult>> unfavoriteForum({
    required String favid,
  }) async {
    unfavoriteCalls.add(favid);
    final result =
        _unfavoriteResult ??
        const ApiSuccess<ForumFavoriteMutationResult>(
          ForumFavoriteMutationResult(message: '取消收藏成功'),
        );
    if (result.isSuccess) {
      favoriteForums = favoriteForums
          .where((item) => item.favid != favid)
          .toList();
    }
    return result;
  }
}

class _FakePostingFormMetadataRepository
    implements PostingFormMetadataRepository {
  _FakePostingFormMetadataRepository({this.metadata});

  final NewThreadFormMetadata? metadata;
  int callCount = 0;

  @override
  Future<ApiResult<NewThreadFormMetadata>> getFormMetadata({
    required String fid,
  }) async {
    callCount += 1;
    final value =
        metadata ??
        NewThreadFormMetadata(
          fid: fid,
          forumName: '集成测试版块',
          formHash: 'fh-int',
          threadTypes: const <ThreadType>[],
          threadSorts: const <ThreadSort>[],
          typeRequired: false,
          sortRequired: false,
        );
    return ApiSuccess<NewThreadFormMetadata>(value);
  }
}

class _FakeNewThreadRepository implements NewThreadRepository {
  _FakeNewThreadRepository({ApiResult<NewThreadSubmissionResult>? result})
    : _result =
          result ??
          const ApiSuccess<NewThreadSubmissionResult>(
            NewThreadSubmissionResult(
              tid: '900001',
              pid: '910001',
              message: '发布成功',
            ),
          );

  final ApiResult<NewThreadSubmissionResult> _result;
  final List<NewThreadDraftPayload> submittedPayloads =
      <NewThreadDraftPayload>[];

  @override
  Future<ApiResult<NewThreadSubmissionResult>> submit({
    required NewThreadDraftPayload payload,
  }) async {
    submittedPayloads.add(payload);
    return _result;
  }
}

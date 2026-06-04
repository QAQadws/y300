import 'dart:convert';
import 'package:y300/core/network/api_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/data/forum_favorite_repository.dart';
import 'package:y300/features/forum/domain/models/forum_favorite_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_external_launcher.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_page.dart';
import 'package:y300/features/tags/data/forum_tag_repository.dart';
import 'package:y300/features/tags/data/tag_providers.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';
import 'package:y300/features/tags/domain/forum_tag_models.dart';

void main() {
  testWidgets('ForumWebViewPage waits for bootstrap config before building the real webview', (
    tester,
  ) async {
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

    expect(find.byKey(const Key('forum-webview-bootstrap-placeholder')), findsOneWidget);
    final placeholder = tester.widget<ColoredBox>(
      find.byKey(const Key('forum-webview-bootstrap-placeholder')),
    );
    expect(
      placeholder.color,
      Theme.of(
        tester.element(find.byKey(const Key('forum-webview-bootstrap-placeholder'))),
      ).colorScheme.surface,
    );
    expect(find.byKey(const Key('forum-webview-surface')), findsNothing);
    expect(driver.buildWidgetCallCount, 0);

    await tester.pump();

    expect(find.byKey(const Key('forum-webview-surface')), findsOneWidget);
    expect(driver.buildWidgetCallCount, greaterThanOrEqualTo(1));
  });

  testWidgets('ForumWebViewPage shows home app bar and seeds normalized cookies before load', (
    tester,
  ) async {
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
      _buildTestApp(
        driver: driver,
        cookieStore: cookieStore,
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('forum-webview-page')), findsOneWidget);
    expect(find.text('百合会论坛'), findsOneWidget);
    expect(find.byKey(const Key('forum-webview-back-button')), findsNothing);
    expect(find.byKey(const Key('forum-webview-search-button')), findsOneWidget);
    expect(find.byKey(const Key('forum-webview-more-button')), findsOneWidget);
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.systemOverlayStyle?.statusBarColor, Colors.transparent);
    expect(
      driver.events,
      <String>[
        'probeCapabilities',
        'initialize',
        'clearCookies',
        'seedCookies',
        'load',
      ],
    );
    expect(driver.probeCapabilitiesCallCount, 1);
    expect(
      driver.bootstrapConfig?.initialUri.toString(),
      'https://bbs.yamibo.com/index.php?mobile=2',
    );
    expect(driver.bootstrapConfig?.capabilityProfile.engine, ForumWebViewEngine.advanced);
    final bootstrapConfig = driver.bootstrapConfig;
    expect(bootstrapConfig, isNotNull);
    expect(
      bootstrapConfig!.visualPolicy.earlyHiddenSelectors,
      const <String>{
        '#header-padding',
        '.header.cl',
        '.footer.mt10.cl',
        '.foot.flex-box',
      },
    );
    expect(bootstrapConfig.initialUserScripts, hasLength(1));
    expect(bootstrapConfig.networkPolicy.customUserAgent, isNull);
    expect(bootstrapConfig.networkPolicy.preferAppLocale, isTrue);
    expect(driver.seededCookies.single.domain, 'bbs.yamibo.com');
    expect(
      driver.seededCookies.single.cookies,
      <String, String>{'auth': 'token+123', 'saltkey': 'abc|xyz'},
    );
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
  });

  testWidgets('ForumWebViewPage passes early user scripts into bootstrap config when document-start is available', (
    tester,
  ) async {
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

    final bootstrapConfig = driver.bootstrapConfig;
    expect(bootstrapConfig, isNotNull);
    expect(bootstrapConfig!.capabilityProfile.engine, ForumWebViewEngine.advanced);
    expect(bootstrapConfig.initialUserScripts, hasLength(1));
    expect(
      bootstrapConfig.initialUserScripts.single.injectionTime,
      ForumWebViewInitialUserScriptInjectionTime.documentStart,
    );
    expect(
      bootstrapConfig.initialUserScripts.single.source,
      contains("window.location.host !== 'bbs.yamibo.com'"),
    );
  });

  testWidgets('ForumWebViewPage cleans chrome when page finishes loading', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();

    await tester.pumpWidget(_buildTestApp(driver: driver));
    await tester.pump();

    await driver.dispatchPageFinished(
      'https://bbs.yamibo.com/index.php?mobile=2',
    );
    await tester.pump();

    expect(driver.scripts.length, 1);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(driver.scripts.length, 2);
  });

  testWidgets('ForumWebViewPage keeps loading mask until the first managed page commits visible and stabilizes', (
    tester,
  ) async {
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

    expect(find.byKey(const Key('forum-webview-loading-mask')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final mask = tester.widget<ColoredBox>(
      find.byKey(const Key('forum-webview-loading-mask')),
    );
    expect(
      mask.color,
      Theme.of(
        tester.element(find.byKey(const Key('forum-webview-loading-mask'))),
      ).colorScheme.surface,
    );

    await driver.dispatchPageStarted(
      'https://bbs.yamibo.com/index.php?mobile=2',
    );
    await driver.dispatchPageFinished(
      'https://bbs.yamibo.com/index.php?mobile=2',
    );
    await tester.pump();

    expect(find.byKey(const Key('forum-webview-loading-mask')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(driver.scripts.length, 2);
    expect(find.byKey(const Key('forum-webview-loading-mask')), findsOneWidget);

    await driver.dispatchPageCommitVisible(
      'https://bbs.yamibo.com/index.php?mobile=2',
    );
    await tester.pump();

    expect(find.byKey(const Key('forum-webview-loading-mask')), findsNothing);
  });

  testWidgets('ForumWebViewPage falls back to page-finished stabilization when commit-visible is unavailable', (
    tester,
  ) async {
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

    expect(find.byKey(const Key('forum-webview-loading-mask')), findsOneWidget);

    await driver.dispatchPageStarted(
      'https://bbs.yamibo.com/index.php?mobile=2',
    );
    await driver.dispatchPageFinished(
      'https://bbs.yamibo.com/index.php?mobile=2',
    );
    await tester.pump();

    expect(find.byKey(const Key('forum-webview-loading-mask')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(driver.scripts.length, 2);
    expect(find.byKey(const Key('forum-webview-loading-mask')), findsNothing);
  });

  testWidgets('ForumWebViewPage home search button loads managed forum search url', (
    tester,
  ) async {
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
      driver.loadRequests.last.headers.keys.map((key) => key.toLowerCase()).toSet(),
      isNot(contains('cookie')),
    );
  });

  testWidgets('ForumWebViewPage no longer wraps webview in refresh indicator', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();

    await tester.pumpWidget(_buildTestApp(driver: driver));
    await tester.pump();

    expect(find.byKey(const Key('forum-webview-refresh-indicator')), findsNothing);
    expect(find.byKey(const Key('forum-webview-refresh-scroll')), findsNothing);
    expect(find.byType(RefreshIndicator), findsNothing);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('ForumWebViewPage refresh action reloads current page from more menu', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();

    await tester.pumpWidget(_buildTestApp(driver: driver));
    await tester.pump();

    await tester.tap(find.byKey(const Key('forum-webview-more-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('forum-webview-refresh-action')));
    await tester.pumpAndSettle();

    expect(driver.reloadCallCount, 1);
  });

  testWidgets('ForumWebViewPage keeps managed site links inside webview', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();
    final launcher = _FakeForumWebViewExternalLauncher();

    await tester.pumpWidget(
      _buildTestApp(
        driver: driver,
        launcher: launcher,
      ),
    );
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

    await tester.pumpWidget(
      _buildTestApp(
        driver: driver,
        launcher: launcher,
      ),
    );
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

    await tester.pumpWidget(
      _buildTestApp(
        driver: driver,
        launcher: launcher,
      ),
    );
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
    expect(find.byKey(const Key('forum-webview-refresh-action')), findsOneWidget);
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
      _buildTestApp(
        driver: driver,
        favoriteRepository: favoriteRepository,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('forum-webview-more-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消收藏'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forum-favorite-forum-picker')), findsOneWidget);
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
        ApiSuccess<List<FavoriteForum>>(
          <FavoriteForum>[
            _favoriteForum(fid: '55', favid: 'fav-55', title: '综合区'),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      _buildTestApp(
        driver: driver,
        favoriteRepository: favoriteRepository,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('forum-webview-more-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消收藏'));
    await tester.pumpAndSettle();

    expect(find.text('加载失败'), findsOneWidget);

    await tester.tap(find.byKey(const Key('forum-favorite-forum-picker-retry')));
    await tester.pumpAndSettle();

    expect(find.text('综合区'), findsOneWidget);
    expect(favoriteRepository.loadCallCount, 2);
  });

  testWidgets('ForumWebViewPage home unfavorite closes picker and reloads home', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();
    final favoriteRepository = _FakeForumFavoriteRepository(
      favoriteForums: <FavoriteForum>[
        _favoriteForum(fid: '55', favid: 'fav-55', title: '综合区'),
      ],
    );

    await tester.pumpWidget(
      _buildTestApp(
        driver: driver,
        favoriteRepository: favoriteRepository,
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('forum-webview-more-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消收藏'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('综合区'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forum-favorite-forum-picker')), findsNothing);
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
  });

  testWidgets('ForumWebViewPage shows forum display app bar and loads curForum search', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver()..title = '页面标题';
    final favoriteRepository = _FakeForumFavoriteRepository();

    await tester.pumpWidget(
      _buildTestApp(
        driver: driver,
        favoriteRepository: favoriteRepository,
      ),
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

    expect(find.byKey(const Key('forum-webview-back-button')), findsOneWidget);
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
  });

  testWidgets('ForumWebViewPage forum display shows favorite action when forum is not favorited', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver()..title = '页面标题';
    final favoriteRepository = _FakeForumFavoriteRepository();

    await tester.pumpWidget(
      _buildTestApp(
        driver: driver,
        favoriteRepository: favoriteRepository,
      ),
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
  });

  testWidgets('ForumWebViewPage forum display shows unfavorite action when forum is favorited', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver()..title = '页面标题';
    final favoriteRepository = _FakeForumFavoriteRepository(
      favoriteForums: <FavoriteForum>[
        _favoriteForum(fid: '55', favid: 'fav-55', title: '综合区'),
      ],
    );

    await tester.pumpWidget(
      _buildTestApp(
        driver: driver,
        favoriteRepository: favoriteRepository,
      ),
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
  });

  testWidgets('ForumWebViewPage forum display favorite action reloads current page', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver()..title = '页面标题';
    final favoriteRepository = _FakeForumFavoriteRepository();
    const forumDisplayUrl =
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2';

    await tester.pumpWidget(
      _buildTestApp(
        driver: driver,
        favoriteRepository: favoriteRepository,
      ),
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
  });

  testWidgets('ForumWebViewPage forum display unfavorite action reloads current page', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver()..title = '页面标题';
    final favoriteRepository = _FakeForumFavoriteRepository(
      favoriteForums: <FavoriteForum>[
        _favoriteForum(fid: '55', favid: 'fav-55', title: '综合区'),
      ],
    );
    const forumDisplayUrl =
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=55&mobile=2';

    await tester.pumpWidget(
      _buildTestApp(
        driver: driver,
        favoriteRepository: favoriteRepository,
      ),
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
  });

  testWidgets('ForumWebViewPage thread detail falls back to forum search when fid is unknown', (
    tester,
  ) async {
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

    expect(find.byKey(const Key('forum-webview-back-button')), findsOneWidget);
    expect(find.text('主题标题'), findsOneWidget);

    await tester.tap(find.byKey(const Key('forum-webview-search-button')));
    await tester.pumpAndSettle();

    expect(driver.loadedUris.length, 2);
    expect(
      driver.loadedUris.last.toString(),
      'https://bbs.yamibo.com/search.php?mod=forum&mobile=2',
    );
  });

  testWidgets('ForumWebViewPage thread detail more menu shows author order and home actions', (
    tester,
  ) async {
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
    expect(driver.returningScripts.single, contains('#nav-more-menu .nav-more-item'));
  });

  testWidgets('ForumWebViewPage thread detail author filter action loads author-only url', (
    tester,
  ) async {
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
  });

  testWidgets('ForumWebViewPage thread detail already author-only shows normal thread action', (
    tester,
  ) async {
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
  });

  testWidgets('ForumWebViewPage thread detail order action toggles between reverse and normal order', (
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
  });

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

  testWidgets('ForumWebViewPage thread detail uses curForum search when fid is known', (
    tester,
  ) async {
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

    expect(find.byKey(const Key('forum-webview-back-button')), findsOneWidget);
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
  });

  testWidgets('ForumWebViewPage search app bar uses forum search title and hides search button', (
    tester,
  ) async {
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

    expect(find.byKey(const Key('forum-webview-back-button')), findsOneWidget);
    expect(find.text('论坛搜索'), findsOneWidget);
    expect(find.byKey(const Key('forum-webview-search-button')), findsNothing);

    await tester.tap(find.byKey(const Key('forum-webview-more-button')));
    await tester.pumpAndSettle();

    expect(find.text('刷新页面'), findsOneWidget);
    expect(find.text('返回首页'), findsOneWidget);
  });

  testWidgets('ForumWebViewPage search app bar uses board name search title for curforum scope', (
    tester,
  ) async {
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
    expect(find.byKey(const Key('forum-webview-search-button')), findsNothing);
  });

  testWidgets('ForumWebViewPage search more action loads home', (
    tester,
  ) async {
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

  testWidgets('ForumWebViewPage search page still cleans chrome when loading finishes', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver()..title = '帖子搜索';

    await tester.pumpWidget(_buildTestApp(driver: driver));
    await tester.pump();

    await driver.dispatchPageFinished(
      'https://bbs.yamibo.com/search.php?mod=forum&searchid=777&mobile=2',
    );
    await tester.pump();

    expect(driver.scripts.length, 1);
  });

  testWidgets('ForumWebViewPage back button uses driver.goBack when history exists', (
    tester,
  ) async {
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
  });

  testWidgets('ForumWebViewPage back button loads home when history is unavailable', (
    tester,
  ) async {
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
  });

  testWidgets('ForumWebViewPage system back uses driver.goBack when history exists', (
    tester,
  ) async {
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
  });

  testWidgets('ForumWebViewPage system back loads home when history is unavailable away from home', (
    tester,
  ) async {
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
  });

  testWidgets('ForumWebViewPage system back allows route pop on home without history', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();

    await tester.pumpWidget(_buildRoutedTestApp(driver: driver));
    await tester.tap(find.byKey(const Key('open-forum-webview-page')));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forum-webview-page')), findsNothing);
    expect(find.byKey(const Key('open-forum-webview-page')), findsOneWidget);
  });
}

Widget _buildTestApp({
  required _FakeForumWebViewDriver driver,
  CookieStore? cookieStore,
  ForumTagRepository? tagRepository,
  ForumFavoriteRepository? favoriteRepository,
  ForumWebViewExternalLauncher? launcher,
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
      _LoadRequestRecord(
        uri: uri,
        headers: Map<String, String>.from(headers),
      ),
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
  const _LoadRequestRecord({
    required this.uri,
    required this.headers,
  });

  final Uri uri;
  final Map<String, String> headers;
}

class _FakeCookieStore extends CookieStore {
  _FakeCookieStore({
    this.cookies = const <String, String>{},
  });

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
    return ForumTagLookup(
      const <ForumBoardTagSet>[
        ForumBoardTagSet(
          fid: '55',
          name: '综合区',
          tags: <ForumTagDefinition>[],
        ),
      ],
    );
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
  }) : favoriteForums =
           List<FavoriteForum>.from(favoriteForums ?? const <FavoriteForum>[]),
       _loadResults =
           List<ApiResult<List<FavoriteForum>>>.from(
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

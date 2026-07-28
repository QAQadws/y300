import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/data/repositories/forum_mode_settings_repository.dart';
import 'package:y300/features/forum/data/repositories/forum_favorite_repository.dart';
import 'package:y300/features/forum/data/services/forum_webview_redirect_resolver.dart';
import 'package:y300/features/forum/domain/models/forum_favorite_models.dart';
import 'package:y300/features/composer_shared/data/repositories/composer_draft_repository.dart';
import 'package:y300/features/composer_shared/data/providers/composer_providers.dart';
import 'package:y300/features/composer_shared/domain/models/composer_draft_models.dart';
import 'package:y300/features/forum/domain/models/forum_shell_mode.dart';
import 'package:y300/features/forum/presentation/forum_shell_mode_controller.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_external_launcher.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_page.dart';
import 'package:y300/features/history/data/providers/history_providers.dart';
import 'package:y300/features/history/domain/models/history_models.dart';
import 'package:y300/features/history/domain/services/history_visit_recorder.dart';
import 'package:y300/features/posting/data/repositories/new_thread_repository.dart';
import 'package:y300/features/posting/data/repositories/posting_form_metadata_repository.dart';
import 'package:y300/features/posting/data/providers/posting_providers.dart';
import 'package:y300/features/posting/domain/models/posting_models.dart';
import 'package:y300/features/reply/data/providers/reply_providers.dart';
import 'package:y300/features/reply/data/repositories/reply_repository.dart';
import 'package:y300/features/reply/domain/models/reply_models.dart';
import 'package:y300/features/tags/data/repositories/forum_tag_repository.dart';
import 'package:y300/features/tags/data/providers/tag_providers.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';
import 'package:y300/features/tags/domain/forum_tag_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/data/repositories/thread_repository.dart';
import 'package:y300/features/thread/data/services/thread_post_locator.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

Matcher containsCssSelector(String selector) {
  final escapedSelector = RegExp.escape(selector);
  return contains(
    RegExp('(^|[^A-Za-z0-9_-])$escapedSelector(?=\$|[^A-Za-z0-9_-])'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'ForumWebViewPage waits for bootstrap config without skeleton page',
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
        findsNothing,
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
      expect(find.text('论坛首页'), findsOneWidget);
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
    'ForumWebViewPage renders the WebView surface without loading masks',
    (tester) async {
      for (final profile in <ForumWebViewCapabilityProfile>[
        const ForumWebViewCapabilityProfile(
          engine: ForumWebViewEngine.advanced,
          documentStartMode: ForumWebViewDocumentStartMode.bestEffort,
          supportsContentBlockers: false,
          supportsTransparentBackground: true,
          supportsPlatformScrollTuning: true,
          supportsCookieHooks: true,
          supportsPageCommitVisible: true,
        ),
        const ForumWebViewCapabilityProfile(
          engine: ForumWebViewEngine.legacy,
          documentStartMode: ForumWebViewDocumentStartMode.unavailable,
          supportsContentBlockers: false,
          supportsTransparentBackground: false,
          supportsPlatformScrollTuning: false,
          supportsCookieHooks: false,
          supportsPageCommitVisible: false,
        ),
      ]) {
        final driver = _FakeForumWebViewDriver()..capabilityProfile = profile;

        await tester.pumpWidget(_buildTestApp(driver: driver));
        await tester.pump();

        expect(find.byKey(const Key('forum-webview-surface')), findsOneWidget);
        expect(
          find.byKey(const Key('forum-webview-loading-mask')),
          findsNothing,
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);

        await driver.dispatchPageStarted(
          'https://bbs.yamibo.com/index.php?mobile=2',
        );
        await driver.dispatchPageFinished(
          'https://bbs.yamibo.com/index.php?mobile=2',
        );
        await tester.pump();

        expect(
          find.byKey(const Key('forum-webview-loading-mask')),
          findsNothing,
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(driver.scripts.length, 1);

        await tester.pumpWidget(const SizedBox.shrink());
      }
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

  testWidgets(
    'Phase 0 baseline ignores a stale page-finished navigation generation',
    (tester) async {
      const firstUrl =
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=101&mobile=2';
      const secondUrl =
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=202&mobile=2';
      final driver = _FakeForumWebViewDriver()..holdTitleReads = true;

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();

      await driver.dispatchPageStarted(firstUrl);
      final firstFinish = driver.dispatchPageFinished(firstUrl);
      await tester.pump();
      expect(driver.pendingTitleReads, hasLength(1));

      await driver.dispatchPageStarted(secondUrl);
      final secondFinish = driver.dispatchPageFinished(secondUrl);
      await tester.pump();
      expect(driver.pendingTitleReads, hasLength(2));

      driver.pendingTitleReads[1].complete('第二个主题');
      await secondFinish;
      await tester.pump();

      expect(find.text('第二个主题'), findsOneWidget);
      expect(driver.scripts, hasLength(1));

      driver.pendingTitleReads[0].complete('迟到的第一个主题');
      await firstFinish;
      await tester.pump();

      expect(find.text('第二个主题'), findsOneWidget);
      expect(find.text('迟到的第一个主题'), findsNothing);
      expect(driver.scripts, hasLength(1));
    },
  );

  testWidgets(
    'ForumWebViewPage advanced engine records only after visible commit and DOM proof',
    (tester) async {
      const url =
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=524596&page=3&highlight=%D2%B2%CE%DE&mobile=2';
      final recorder = _RecordingHistoryVisitRecorder();
      final driver = _FakeForumWebViewDriver()
        ..title = '浏览器标题'
        ..javaScriptResult = _threadDocumentResult(
          title: '结构化主题',
          forumName: '中文百合漫画区',
          canonicalHref:
              'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=524596&highlight=%BC%AB%CF%DE',
          postCount: 20,
        );

      await tester.pumpWidget(
        _buildTestApp(driver: driver, historyRecorder: recorder),
      );
      await tester.pump();

      await driver.dispatchPageStarted(url);
      await driver.dispatchPageFinished(url);
      await tester.pump();
      expect(recorder.drafts, isEmpty);

      await driver.dispatchPageCommitVisible(url);
      await tester.pump();

      expect(recorder.drafts, hasLength(1));
      final draft = recorder.drafts.single;
      expect(draft.target.id, '524596');
      expect(draft.surface, HistoryVisitSurface.threadWebView);
      expect(draft.title, '结构化主题');
      expect(draft.forumName, '中文百合漫画区');
      expect(draft.page, 3);
      expect(
        draft.thumbnail?.remoteUrl,
        'https://bbs.yamibo.com/data/attachment/forum/cover.jpg',
      );
      expect(draft.canonicalUri.toString(), isNot(contains('highlight')));
    },
  );

  testWidgets(
    'ForumWebViewPage advanced engine handles visible commit before finish once',
    (tester) async {
      const url =
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=101&mobile=2';
      final recorder = _RecordingHistoryVisitRecorder();
      final driver = _FakeForumWebViewDriver()
        ..title = '主题'
        ..javaScriptResult = _threadDocumentResult(title: '主题');

      await tester.pumpWidget(
        _buildTestApp(driver: driver, historyRecorder: recorder),
      );
      await tester.pump();

      await driver.dispatchPageStarted(url);
      await driver.dispatchPageCommitVisible(url);
      expect(recorder.drafts, isEmpty);
      await driver.dispatchPageFinished(url);
      await tester.pump();

      expect(recorder.drafts, hasLength(1));
      await driver.dispatchPageCommitVisible(url);
      await tester.pump();
      expect(recorder.drafts, hasLength(1));
    },
  );

  testWidgets(
    'ForumWebViewPage legacy engine uses finished plus DOM proof fallback',
    (tester) async {
      const url =
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=202&mobile=2';
      final recorder = _RecordingHistoryVisitRecorder();
      final driver = _FakeForumWebViewDriver()
        ..capabilityProfile = const ForumWebViewCapabilityProfile(
          engine: ForumWebViewEngine.legacy,
          documentStartMode: ForumWebViewDocumentStartMode.unavailable,
          supportsContentBlockers: false,
          supportsTransparentBackground: false,
          supportsPlatformScrollTuning: false,
          supportsCookieHooks: false,
          supportsPageCommitVisible: false,
        )
        ..title = '主题'
        ..javaScriptResult = _threadDocumentResult(title: 'Legacy 主题');

      await tester.pumpWidget(
        _buildTestApp(driver: driver, historyRecorder: recorder),
      );
      await tester.pump();
      await driver.dispatchPageStarted(url);
      await driver.dispatchPageFinished(url);
      await tester.pump();

      expect(recorder.drafts, hasLength(1));
      expect(recorder.drafts.single.target.id, '202');
      expect(recorder.drafts.single.title, 'Legacy 主题');
    },
  );

  testWidgets(
    'ForumWebViewPage does not record thread error document without post proof',
    (tester) async {
      const url =
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=303&mobile=2';
      final recorder = _RecordingHistoryVisitRecorder();
      final driver = _FakeForumWebViewDriver()
        ..title = '主题不存在'
        ..javaScriptResult = _threadDocumentResult(
          title: '主题不存在',
          postCount: 0,
        );

      await tester.pumpWidget(
        _buildTestApp(driver: driver, historyRecorder: recorder),
      );
      await tester.pump();
      await driver.dispatchPageStarted(url);
      await driver.dispatchPageCommitVisible(url);
      await driver.dispatchPageFinished(url);
      await tester.pump();

      expect(recorder.drafts, isEmpty);
      expect(find.byKey(const Key('forum-webview-page')), findsOneWidget);
    },
  );

  testWidgets(
    'ForumWebViewPage records the final visible thread after redirect generation',
    (tester) async {
      const redirectUrl =
          'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&ptid=404&pid=1&mobile=2';
      const finalUrl =
          'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=404&page=2&mobile=2';
      final recorder = _RecordingHistoryVisitRecorder();
      final driver = _FakeForumWebViewDriver()
        ..title = '落地主题'
        ..javaScriptResult = _threadDocumentResult(title: '落地主题');

      await tester.pumpWidget(
        _buildTestApp(driver: driver, historyRecorder: recorder),
      );
      await tester.pump();
      await driver.dispatchPageStarted(redirectUrl);
      await driver.dispatchPageCommitVisible(finalUrl);
      await driver.dispatchPageFinished(finalUrl);
      await tester.pump();

      expect(recorder.drafts, hasLength(1));
      expect(recorder.drafts.single.target.id, '404');
      expect(recorder.drafts.single.page, 2);
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

  testWidgets(
    'ForumWebViewPage webview mode normalizes thread links in webview',
    (tester) async {
      final driver = _FakeForumWebViewDriver();

      await tester.pumpWidget(_buildTestApp(driver: driver));
      await tester.pump();
      await driver.dispatchPageStarted(
        'https://bbs.yamibo.com/home.php?mod=space&uid=100&mobile=2',
      );
      await driver.dispatchPageFinished(
        'https://bbs.yamibo.com/home.php?mod=space&uid=100&mobile=2',
      );
      await tester.pump();

      final decision = await driver.dispatchNavigationRequest(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=573279&extra=',
      );
      await tester.pump();

      expect(decision, ForumWebViewNavigationDecision.prevent);
      expect(
        driver.loadedUris.last.toString(),
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=573279&mobile=2',
      );
    },
  );

  testWidgets('ForumWebViewPage webview mode loads normalized findpost redirect', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();

    await tester.pumpWidget(_buildTestApp(driver: driver));
    await tester.pump();

    final decision = await driver.dispatchNavigationRequest(
      'forum.php?mod=redirect&amp;goto=findpost&amp;ptid=570388&amp;pid=41575705',
    );
    await tester.pump();

    expect(decision, ForumWebViewNavigationDecision.prevent);
    expect(
      driver.loadedUris.last.toString(),
      'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&ptid=570388&pid=41575705&mobile=2',
    );
  });

  testWidgets('ForumWebViewPage native mode opens direct thread natively', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();

    await tester.pumpWidget(
      _buildTestApp(driver: driver, forumMode: ForumShellMode.native),
    );
    await tester.pumpAndSettle();

    final decision = await driver.dispatchNavigationRequest(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=573279&extra=',
    );
    await tester.pumpAndSettle();

    expect(decision, ForumWebViewNavigationDecision.prevent);
    expect(find.byType(ThreadDetailPage), findsOneWidget);
    expect(driver.loadedUris.length, 1);
  });

  testWidgets('ForumWebViewPage native mode opens fragment post natively', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();

    await tester.pumpWidget(
      _buildTestApp(driver: driver, forumMode: ForumShellMode.native),
    );
    await tester.pumpAndSettle();

    final decision = await driver.dispatchNavigationRequest(
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=570388&page=2#pid41575705',
    );
    await tester.pumpAndSettle();

    expect(decision, ForumWebViewNavigationDecision.prevent);
    expect(find.byType(ThreadDetailPage), findsOneWidget);
    expect(
      find.byKey(const Key('thread-detail-target-scroll-spacer')),
      findsOneWidget,
    );
  });

  testWidgets('ForumWebViewPage native mode locates findpost before opening', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();
    final locator = _FakeThreadPostLocator(
      const ThreadPostLocation(
        tid: '570388',
        pid: '41575705',
        page: 2,
        url:
            'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=570388&page=2#pid41575705',
      ),
    );

    await tester.pumpWidget(
      _buildTestApp(
        driver: driver,
        forumMode: ForumShellMode.native,
        threadPostLocator: locator,
      ),
    );
    await tester.pumpAndSettle();

    final decision = await driver.dispatchNavigationRequest(
      'forum.php?mod=redirect&goto=findpost&ptid=570388&pid=41575705',
    );
    await tester.pumpAndSettle();

    expect(decision, ForumWebViewNavigationDecision.prevent);
    expect(locator.lastTid, '570388');
    expect(locator.lastPid, '41575705');
    expect(locator.lastSourceUri?.queryParameters['mobile'], '2');
    expect(find.byType(ThreadDetailPage), findsOneWidget);
    expect(
      find.byKey(const Key('thread-detail-target-scroll-spacer')),
      findsOneWidget,
    );
  });

  testWidgets('ForumWebViewPage native mode resolves empty findpost redirect', (
    tester,
  ) async {
    final driver = _FakeForumWebViewDriver();
    final redirectResolver = _FakeForumWebViewRedirectResolver(
      finalUri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=572051',
      ),
    );

    await tester.pumpWidget(
      _buildTestApp(
        driver: driver,
        forumMode: ForumShellMode.native,
        redirectResolver: redirectResolver,
      ),
    );
    await tester.pumpAndSettle();

    final decision = await driver.dispatchNavigationRequest(
      'forum.php?mod=redirect&goto=findpost&ptid=570388&pid=',
    );
    await tester.pumpAndSettle();

    expect(decision, ForumWebViewNavigationDecision.prevent);
    expect(redirectResolver.lastSourceUri?.queryParameters['mobile'], '2');
    expect(find.byType(ThreadDetailPage), findsOneWidget);
  });

  testWidgets(
    'ForumWebViewPage falls back to webview when empty redirect fails',
    (tester) async {
      final driver = _FakeForumWebViewDriver();
      final redirectResolver = _FakeForumWebViewRedirectResolver(
        result: const ApiFailure<ForumWebViewRedirectResolution>(
          ApiError(type: ApiErrorType.business, message: 'redirect failed'),
        ),
      );

      await tester.pumpWidget(
        _buildTestApp(
          driver: driver,
          forumMode: ForumShellMode.native,
          redirectResolver: redirectResolver,
        ),
      );
      await tester.pumpAndSettle();

      final decision = await driver.dispatchNavigationRequest(
        'forum.php?mod=redirect&goto=findpost&ptid=570388&pid=',
      );
      await tester.pumpAndSettle();

      expect(decision, ForumWebViewNavigationDecision.prevent);
      expect(find.text('帖子链接解析失败，已在网页中打开'), findsOneWidget);
      expect(
        driver.loadedUris.last.toString(),
        'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&ptid=570388&mobile=2',
      );
    },
  );

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

    expect(find.text('加载收藏版块失败：加载失败'), findsOneWidget);

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
      expect(find.text('已取消收藏本版'), findsOneWidget);
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
      expect(find.text('已收藏本版'), findsOneWidget);
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
      expect(find.text('已取消收藏本版'), findsOneWidget);
      expect(driver.loadedUris.last.toString(), forumDisplayUrl);
      expect(driver.loadRequests.last.headers['Referer'], forumDisplayUrl);
    },
  );

  testWidgets(
    'ForumWebViewPage thread detail hides search button when fid is unknown',
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
      expect(
        find.byKey(const Key('forum-webview-search-button')),
        findsNothing,
      );
      expect(driver.loadedUris.length, 1);
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
        Key('forum-webview-thread-reply-button'),
        Key('forum-webview-more-button'),
      ]),
    );
    expect(
      actionKeys,
      isNot(contains(const Key('forum-webview-search-button'))),
    );

    await tester.tap(
      find.byKey(const Key('forum-webview-thread-reply-button')),
    );
    await _pumpRouteWithoutSettlingEditor(
      tester,
      readyWhen: find.byKey(const Key('reply-composer-source-button')),
      requireEnabled: true,
    );

    expect(find.text('回复帖子'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reply-composer-source-button')));
    await _pumpRouteWithoutSettlingEditor(
      tester,
      readyWhen: find.byKey(const Key('reply-composer-message-input')),
    );
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
    expect(find.text('回复成功：回复发布成功'), findsOneWidget);
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
      await _pumpRouteWithoutSettlingEditor(
        tester,
        readyWhen: find.byKey(const Key('reply-composer-source-button')),
        requireEnabled: true,
      );

      expect(decision, ForumWebViewNavigationDecision.prevent);
      expect(find.text('回复楼层'), findsOneWidget);
      expect(replyRepository.prepareCallCount, 1);
      expect(
        find.byKey(const Key('reply-composer-reference-banner')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('reply-composer-source-button')));
      await _pumpRouteWithoutSettlingEditor(
        tester,
        readyWhen: find.byKey(const Key('reply-composer-message-input')),
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
      await _pumpRouteWithoutSettlingEditor(
        tester,
        readyWhen: find.byKey(const Key('posting-composer-source-button')),
        requireEnabled: true,
      );

      expect(decision, ForumWebViewNavigationDecision.prevent);
      expect(find.text('发帖 — 日常版'), findsOneWidget);
      expect(metadataRepository.callCount, 1);

      await tester.enterText(
        find.byKey(const Key('posting-composer-subject-input')),
        '来自 WebView 的标题',
      );
      await tester.tap(find.byKey(const Key('posting-composer-source-button')));
      await _pumpRouteWithoutSettlingEditor(
        tester,
        readyWhen: find.byKey(const Key('posting-composer-message-input')),
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
      expect(find.text('发布成功：发布成功'), findsOneWidget);
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
    'ForumWebViewPage thread detail hides search button when fid is known',
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
      expect(
        find.byKey(const Key('forum-webview-search-button')),
        findsNothing,
      );
      expect(driver.loadedUris.length, 1);
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

Future<void> _pumpRouteWithoutSettlingEditor(
  WidgetTester tester, {
  Finder? readyWhen,
  bool requireEnabled = false,
}) async {
  // The composer intentionally keeps a caret animation alive. Waiting for
  // the route and its async controller to expose a real widget is sufficient;
  // pumpAndSettle would never converge while the editor caret is active.
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (readyWhen == null ||
        _isVisibleAndReady(tester, readyWhen, requireEnabled: requireEnabled)) {
      return;
    }
  }
  if (readyWhen != null) {
    expect(readyWhen, findsOneWidget);
  }
}

bool _isVisibleAndReady(
  WidgetTester tester,
  Finder finder, {
  required bool requireEnabled,
}) {
  final elements = finder.evaluate().toList(growable: false);
  if (elements.isEmpty) {
    return false;
  }
  if (requireEnabled &&
      elements.every(
        (element) =>
            element.widget is IconButton &&
            (element.widget as IconButton).onPressed == null,
      )) {
    return false;
  }
  final rect = tester.getRect(finder);
  final renderViews = tester.binding.renderViews;
  if (renderViews.isEmpty) {
    return false;
  }
  final viewport = Offset.zero & renderViews.first.size;
  return rect.left >= viewport.left &&
      rect.top >= viewport.top &&
      rect.right <= viewport.right &&
      rect.bottom <= viewport.bottom;
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
  ForumShellMode forumMode = ForumShellMode.webview,
  ThreadRepository? threadRepository,
  ThreadPostLocator? threadPostLocator,
  ForumWebViewRedirectResolver? redirectResolver,
  HistoryVisitRecorder? historyRecorder,
}) {
  return ProviderScope(
    overrides: [
      forumModeSettingsRepositoryProvider.overrideWithValue(
        _FakeForumModeSettingsRepository(forumMode),
      ),
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
      threadRepositoryProvider.overrideWithValue(
        threadRepository ?? _FakeThreadRepository(),
      ),
      threadPostLocatorProvider.overrideWithValue(
        threadPostLocator ?? _FakeThreadPostLocator(null),
      ),
      forumWebViewRedirectResolverProvider.overrideWithValue(
        redirectResolver ?? _FakeForumWebViewRedirectResolver(),
      ),
      imageCacheServiceProvider.overrideWithValue(_NoopImageCacheService()),
      historyVisitRecorderProvider.overrideWithValue(
        historyRecorder ?? _NoopHistoryVisitRecorder(),
      ),
    ],
    child: const LocalizedTestApp(home: ForumWebViewPage()),
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
  ForumShellMode forumMode = ForumShellMode.webview,
  ThreadRepository? threadRepository,
  ThreadPostLocator? threadPostLocator,
  ForumWebViewRedirectResolver? redirectResolver,
  HistoryVisitRecorder? historyRecorder,
}) {
  return ProviderScope(
    overrides: [
      forumModeSettingsRepositoryProvider.overrideWithValue(
        _FakeForumModeSettingsRepository(forumMode),
      ),
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
      threadRepositoryProvider.overrideWithValue(
        threadRepository ?? _FakeThreadRepository(),
      ),
      threadPostLocatorProvider.overrideWithValue(
        threadPostLocator ?? _FakeThreadPostLocator(null),
      ),
      forumWebViewRedirectResolverProvider.overrideWithValue(
        redirectResolver ?? _FakeForumWebViewRedirectResolver(),
      ),
      imageCacheServiceProvider.overrideWithValue(_NoopImageCacheService()),
      historyVisitRecorderProvider.overrideWithValue(
        historyRecorder ?? _NoopHistoryVisitRecorder(),
      ),
    ],
    child: LocalizedTestApp(
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

Object _threadDocumentResult({
  required String title,
  String? forumName,
  String? canonicalHref,
  int postCount = 1,
}) {
  return jsonEncode(<String, Object?>{
    'title': title,
    'forumName': forumName,
    'canonicalHref': canonicalHref,
    'firstPostImageHref': '/data/attachment/forum/cover.jpg',
    'postCount': postCount,
  });
}

class _RecordingHistoryVisitRecorder implements HistoryVisitRecorder {
  final List<HistoryVisitDraft> drafts = <HistoryVisitDraft>[];

  @override
  Future<void> record(HistoryVisitDraft draft) async {
    drafts.add(draft);
  }
}

class _NoopHistoryVisitRecorder implements HistoryVisitRecorder {
  @override
  Future<void> record(HistoryVisitDraft draft) async {}
}

class _FakeForumWebViewDriver implements ForumWebViewDriver {
  final List<String> events = <String>[];
  final List<Uri> loadedUris = <Uri>[];
  final List<_LoadRequestRecord> loadRequests = <_LoadRequestRecord>[];
  final List<String> scripts = <String>[];
  final List<String> returningScripts = <String>[];
  final List<_SeededCookieRecord> seededCookies = <_SeededCookieRecord>[];
  String? title;
  bool holdTitleReads = false;
  final List<Completer<String?>> pendingTitleReads = <Completer<String?>>[];
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
    if (holdTitleReads) {
      final completer = Completer<String?>();
      pendingTitleReads.add(completer);
      return completer.future;
    }
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

class _FakeForumModeSettingsRepository implements ForumModeSettingsRepository {
  _FakeForumModeSettingsRepository(this.mode);

  ForumShellMode mode;

  @override
  Future<ForumShellMode> loadMode() async => mode;

  @override
  Future<void> saveMode(ForumShellMode mode) async {
    this.mode = mode;
  }
}

class _FakeThreadRepository implements ThreadRepository {
  @override
  Future<ApiResult<ThreadDetailData>> getThreadDetail({
    required String tid,
    int page = 1,
    Map<String, String> queryParameters = const <String, String>{},
  }) async {
    return ApiSuccess<ThreadDetailData>(
      ThreadDetailData(
        tid: tid,
        fid: '33',
        subject: '测试主题',
        author: 'alice',
        replies: 0,
        views: 1,
        currentPage: page,
        lastPage: page,
        perPage: 20,
        posts: [
          ThreadPost(
            pid: 'p1',
            author: 'alice',
            authorId: '1',
            message: '<p>正文</p>',
            number: 1,
            isFirst: true,
            dateline: 'today',
          ),
        ],
      ),
    );
  }
}

class _FakeThreadPostLocator implements ThreadPostLocator {
  _FakeThreadPostLocator(this.location);

  final ThreadPostLocation? location;
  String? lastTid;
  String? lastPid;
  Uri? lastSourceUri;

  @override
  Future<ApiResult<ThreadPostLocation>> locate({
    required String tid,
    required String pid,
    required Uri sourceUri,
  }) async {
    lastTid = tid;
    lastPid = pid;
    lastSourceUri = sourceUri;
    final value = location;
    if (value == null) {
      return const ApiFailure<ThreadPostLocation>(
        ApiError(type: ApiErrorType.business, message: '测试未配置楼层定位'),
      );
    }
    return ApiSuccess<ThreadPostLocation>(value);
  }
}

class _FakeForumWebViewRedirectResolver
    implements ForumWebViewRedirectResolver {
  _FakeForumWebViewRedirectResolver({
    Uri? finalUri,
    ApiResult<ForumWebViewRedirectResolution>? result,
  }) : result =
           result ??
           ApiSuccess<ForumWebViewRedirectResolution>(
             ForumWebViewRedirectResolution(
               finalUri:
                   finalUri ??
                   Uri.parse(
                     'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=100',
                   ),
             ),
           );

  final ApiResult<ForumWebViewRedirectResolution> result;
  Uri? lastSourceUri;

  @override
  Future<ApiResult<ForumWebViewRedirectResolution>> resolve(
    Uri sourceUri,
  ) async {
    lastSourceUri = sourceUri;
    return result;
  }
}

class _NoopImageCacheService implements ImageCacheService {
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult(
      success: false,
      cacheKey: request.cacheKey,
      fromCache: false,
    );
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult.failed;
  }

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async {
    return 0;
  }

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}

  @override
  Future<void> clearUnprotected() async {}

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
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

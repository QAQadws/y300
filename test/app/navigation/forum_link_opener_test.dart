import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/navigation/forum_link_opener.dart';
import 'package:y300/app/navigation/forum_link_routes.dart';
import 'package:y300/core/clipboard/clipboard_providers.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/auth/application/verified_session_owner.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/features/forum/domain/services/yamibo_forum_link_resolver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_external_launcher.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';
import 'package:y300/features/thread/domain/repositories/thread_post_locator.dart';
import 'package:y300/features/thread/domain/services/thread_post_navigation_session.dart';
import 'package:y300/features/thread/domain/services/thread_post_route_resolver.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../test_support/localized_test_app.dart';

void main() {
  late _Observer observer;
  late _Locator locator;
  late _ExternalLauncher launcher;
  late ThreadPostNavigationSession session;
  late ForumLinkOpener opener;
  late BuildContext source;
  late List<YamiboForumLinkDestination> native;
  late List<ForumWebViewLaunchConfig> web;
  late List<String> copied;
  late Object owner;
  late bool active;
  late bool sourceValid;

  setUp(() {
    observer = _Observer();
    locator = _Locator();
    launcher = _ExternalLauncher();
    session = ThreadPostNavigationSession();
    native = [];
    web = [];
    copied = [];
    owner = (uid: '101', revision: 0);
    active = true;
    sourceValid = true;
    opener = ForumLinkOpener(
      readViewerUserId: () => '101',
      readOwner: () => owner,
      isActive: () => active,
      nativePage: (destination) {
        native.add(destination);
        return const SizedBox();
      },
      webViewRoute: (config) {
        web.add(config);
        return MaterialPageRoute(builder: (_) => const SizedBox());
      },
      externalLauncher: () => launcher,
      postResolver: () => ThreadPostRouteResolver(locator),
    );
  });
  tearDown(() => session.dispose());

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      LocalizedTestApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) {
            source = context;
            return const Scaffold();
          },
        ),
      ),
    );
    observer.pushed.clear();
  }

  Future<void> open(WidgetTester tester, String url) async {
    unawaited(
      opener.open(
        context: source,
        url: url,
        session: session,
        isCurrent: () => sourceValid,
        onCopyLink: (value) async => copied.add(value),
      ),
    );
    await tester.idle();
  }

  Widget takePage() {
    final route = observer.pushed.removeLast() as MaterialPageRoute;
    final page = route.builder(source);
    Navigator.of(source).removeRoute(route);
    return page;
  }

  testWidgets('native dispatch retains page and floor coordinates', (
    tester,
  ) async {
    await pumpHost(tester);
    await open(tester, 'https://bbs.yamibo.com/thread-42-3-1.html');
    expect(native.single.kind, YamiboForumLinkKind.thread);
    expect(native.single.tid, '42');
    expect(native.single.page, 3);
    takePage();
    await open(tester, 'thread-42-4-1.html#pid90');
    final floor = takePage() as ThreadDetailPage;
    expect(floor.tid, '42');
    expect(floor.targetPid, '90');
    expect(floor.initialPage, 4);
    expect(locator.requests, isEmpty);
    expect(web, isEmpty);
    expect(launcher.opened, isEmpty);
  });

  testWidgets('unknown filters and duplicate query fields keep web semantics', (
    tester,
  ) async {
    await pumpHost(tester);
    for (final url in [
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=42&page=3&authorid=7',
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=42&tid=43',
      'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=42&foo=bar#x',
    ]) {
      await open(tester, url);
      expect(web.last.initialUri, Uri.parse(url));
      expect(web.last.popOnRootBack, isTrue);
      expect(
        web.last.navigationPolicy,
        ForumWebViewNavigationPolicy.keepWebView,
      );
      takePage();
    }
    expect(native, isEmpty);
    expect(locator.requests, isEmpty);
  });

  testWidgets('external URLs use the existing launcher once while pending', (
    tester,
  ) async {
    await pumpHost(tester);
    const url = 'https://example.org/read?a=1#chapter';
    await open(tester, url);
    await open(tester, url);
    expect(launcher.opened, [Uri.parse(url)]);
    expect(observer.pushed, isEmpty);
    expect(copied, isEmpty);
    launcher.requests.single.complete(true);
    await tester.idle();
    await open(tester, url);
    expect(launcher.opened, hasLength(2));
    launcher.requests.last.complete(true);
    await tester.idle();
  });

  testWidgets('launcher failure offers localized feedback and explicit copy', (
    tester,
  ) async {
    await pumpHost(tester);
    const url = 'https://example.org/read';
    await open(tester, url);
    launcher.requests.single.complete(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(copied, isEmpty);
    final l10n = AppLocalizations.of(source);
    expect(find.text(l10n.messageLinkFailed), findsOneWidget);
    await tester.tap(find.text(l10n.threadDetailCopyLink));
    await tester.idle();
    expect(copied, [url]);
  });

  testWidgets(
    'lookalike domains remain external and unsupported schemes fail',
    (tester) async {
      await pumpHost(tester);
      for (final url in [
        'https://bbs.yamibo.com.example.org/thread-42-1-1.html',
        'https://example.org/read?next=https://bbs.yamibo.com/',
      ]) {
        await open(tester, url);
        expect(launcher.opened.last, Uri.parse(url));
        launcher.requests.last.complete(true);
        await tester.idle();
      }
      for (final url in ['javascript:alert(1)', 'file:///tmp/secret']) {
        await open(tester, url);
      }
      expect(launcher.opened, hasLength(2));
      expect(native, isEmpty);
      expect(web, isEmpty);
      expect(copied, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'floor taps share the locator and a new target retires old work',
    (tester) async {
      await pumpHost(tester);
      const first = 'forum.php?mod=redirect&goto=findpost&ptid=42&pid=90';
      await open(tester, first);
      await open(tester, first);
      expect(locator.requests, hasLength(1));
      await open(tester, 'forum.php?mod=redirect&goto=findpost&ptid=42&pid=91');
      expect(locator.requests, hasLength(2));
      locator.requests.first.complete(_location('90', 2));
      await tester.idle();
      expect(observer.pushed, isEmpty);
      locator.requests.last.complete(_location('91', 5));
      await tester.idle();
      final page = takePage() as ThreadDetailPage;
      expect(page.targetPid, '91');
      expect(page.initialPage, 5);
    },
  );

  testWidgets('filtered floor hints are re-located for the ordinary view', (
    tester,
  ) async {
    await pumpHost(tester);
    await open(
      tester,
      'forum.php?mod=viewthread&tid=42&page=8&authorid=7#pid90',
    );
    expect(observer.pushed, isEmpty);
    expect(locator.requests, hasLength(1));
    locator.requests.single.complete(_location('90', 3));
    await tester.idle();
    expect((takePage() as ThreadDetailPage).initialPage, 3);
  });

  testWidgets('same floor under a new owner starts fresh pending work', (
    tester,
  ) async {
    await pumpHost(tester);
    const url = 'forum.php?mod=redirect&goto=findpost&ptid=42&pid=90';
    await open(tester, url);
    owner = (uid: '101', revision: 1);
    await open(tester, url);
    expect(locator.requests, hasLength(2));
    locator.requests.first.complete(_location('90', 2));
    await tester.idle();
    expect(observer.pushed, isEmpty);
    locator.requests.last.complete(_location('90', 5));
    await tester.idle();
    expect((takePage() as ThreadDetailPage).initialPage, 5);
  });

  for (final invalidation in ['owner', 'source', 'dispose', 'covered']) {
    testWidgets('late floor result is rejected after $invalidation changes', (
      tester,
    ) async {
      await pumpHost(tester);
      await open(tester, 'forum.php?mod=redirect&goto=findpost&ptid=42&pid=90');
      Route<void>? covering;
      switch (invalidation) {
        case 'owner':
          owner = (uid: '101', revision: 1);
        case 'source':
          sourceValid = false;
        case 'dispose':
          active = false;
          session.dispose();
        case 'covered':
          covering = MaterialPageRoute<void>(builder: (_) => const Scaffold());
          unawaited(Navigator.of(source).push(covering));
      }
      locator.requests.single.complete(_location('90', 3));
      await tester.idle();
      expect(observer.pushed, covering == null ? isEmpty : [covering]);
      if (covering != null) Navigator.of(source).removeRoute(covering);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('late external error cannot replace newer navigation feedback', (
    tester,
  ) async {
    await pumpHost(tester);
    await open(tester, 'https://example.org/read');
    await open(tester, 'forum.php?mod=redirect&goto=findpost&ptid=42&pid=90');
    launcher.requests.single.completeError(StateError('old launch failure'));
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
    locator.requests.single.complete(_location('90', 3));
    await tester.idle();
    expect(takePage(), isA<ThreadDetailPage>());
  });

  testWidgets(
    'App provider fallback Copy records successful shared writer evidence',
    (tester) async {
      await pumpHost(tester);
      final platformCalls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') platformCalls.add(call);
        if (call.method == 'Clipboard.getData') {
          fail('Copy must not read back the clipboard');
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final container = ProviderContainer.test(
        overrides: [
          yamiboSessionStoreProvider.overrideWithValue(YamiboSessionStore()),
          forumWebViewExternalLauncherProvider.overrideWithValue(launcher),
        ],
      );
      addTearDown(container.dispose);
      const url = 'https://example.org/read?keep=1#fragment';
      unawaited(
        container
            .read(forumLinkOpenerProvider)
            .open(
              context: source,
              url: url,
              session: session,
              isCurrent: () => sourceValid,
            ),
      );
      await tester.idle();
      launcher.requests.single.complete(false);
      await tester.pumpAndSettle();
      expect(platformCalls, isEmpty);
      final l10n = AppLocalizations.of(source);
      await tester.tap(find.text(l10n.threadDetailCopyLink));
      await tester.pumpAndSettle();
      expect(platformCalls, hasLength(1));
      expect(platformCalls.single.arguments, {'text': url});
      expect(
        container
            .read(clipboardSelfCopyFingerprintRegistryProvider)
            .containsText(url),
        isTrue,
      );
    },
  );

  testWidgets('App provider opens ordinary links without auth verification', (
    tester,
  ) async {
    await pumpHost(tester);
    final container = ProviderContainer.test(
      overrides: [
        yamiboSessionStoreProvider.overrideWithValue(YamiboSessionStore()),
        verifiedSessionOwnerProvider.overrideWith((_) {
          fail('Ordinary links must not evaluate auth validation.');
        }),
        forumWebViewExternalLauncherProvider.overrideWithValue(launcher),
        nativeForumLinkPageFactoryProvider.overrideWithValue((
          destination, {
          isActive = true,
        }) {
          native.add(destination);
          return const SizedBox();
        }),
      ],
    );
    addTearDown(container.dispose);
    opener = container.read(forumLinkOpenerProvider);
    await open(tester, 'https://example.org/read');
    expect(launcher.opened, [Uri.parse('https://example.org/read')]);
    launcher.requests.single.complete(true);
    await tester.idle();
    await open(tester, 'https://bbs.yamibo.com/thread-42-2-1.html');
    expect(native.single.page, 2);
    takePage();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'App provider rejects late floor results after same UID relogin',
    (tester) async {
      await pumpHost(tester);
      final snapshot = YamiboSessionSnapshot(
        isLoggedIn: true,
        uid: '101',
        username: 'member',
        formhash: '',
        updatedAt: DateTime.utc(2026, 10, 10),
        source: 'test',
      );
      final sessions = YamiboSessionStore()..saveExtracted(snapshot);
      final container = ProviderContainer.test(
        overrides: [
          yamiboSessionStoreProvider.overrideWithValue(sessions),
          verifiedSessionOwnerProvider.overrideWith((_) {
            fail('Floor dispatch must not evaluate auth validation.');
          }),
          threadPostLocatorProvider.overrideWithValue(locator),
        ],
      );
      addTearDown(container.dispose);
      opener = container.read(forumLinkOpenerProvider);
      await open(tester, 'forum.php?mod=redirect&goto=findpost&ptid=42&pid=90');
      sessions
        ..clear()
        ..saveExtracted(snapshot);
      await container.pump();
      locator.requests.single.complete(_location('90', 3));
      await tester.idle();
      expect(observer.pushed, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

ApiSuccess<ThreadPostLocation> _location(String pid, int page) =>
    ApiSuccess(ThreadPostLocation(tid: '42', pid: pid, page: page, url: ''));

class _Observer extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route);
}

class _Locator implements ThreadPostLocator {
  final requests = <Completer<ApiResult<ThreadPostLocation>>>[];
  @override
  Future<ApiResult<ThreadPostLocation>> locate({
    required String tid,
    required String pid,
    required Uri sourceUri,
  }) {
    final request = Completer<ApiResult<ThreadPostLocation>>();
    requests.add(request);
    return request.future;
  }
}

class _ExternalLauncher implements ForumWebViewExternalLauncher {
  final opened = <Uri>[];
  final requests = <Completer<bool>>[];
  @override
  Future<bool> launch(Uri uri) {
    opened.add(uri);
    final request = Completer<bool>();
    requests.add(request);
    return request.future;
  }
}

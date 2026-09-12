import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/navigation/message_routes.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_external_launcher.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/messages/presentation/message_center_page.dart';
import 'package:y300/features/messages/presentation/new_private_message_page.dart';
import 'package:y300/features/messages/presentation/private_conversation_page.dart';
import 'package:y300/features/profile/presentation/user_profile_page.dart';
import 'package:y300/features/tags/presentation/yamibo_tag_thread_page.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';
import 'package:y300/features/thread/data/services/thread_post_locator.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';

import '../../test_support/localized_test_app.dart';

void main() {
  late ProviderContainer container;
  late _RouteObserver observer;
  late _Locator locator;
  late _ExternalLauncher launcher;
  late List<ForumWebViewLaunchConfig> web;
  late BuildContext source;

  setUp(() {
    observer = _RouteObserver();
    locator = _Locator();
    launcher = _ExternalLauncher();
    web = [];
    container = ProviderContainer.test(
      overrides: [
        threadPostLocatorProvider.overrideWithValue(locator),
        forumWebViewExternalLauncherProvider.overrideWithValue(launcher),
        forumWebViewRouteFactoryProvider.overrideWithValue((config) {
          web.add(config);
          return MaterialPageRoute<void>(builder: (_) => const SizedBox());
        }),
      ],
    );
  });

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: LocalizedTestApp(
          navigatorObservers: [observer],
          home: Builder(
            builder: (context) {
              source = context;
              return const Scaffold();
            },
          ),
        ),
      ),
    );
    observer.pushed.clear();
  }

  Future<void> open(WidgetTester tester, String url) async {
    container.read(messageLinkOpenerProvider)(source, url);
    await tester.idle();
  }

  // Inspect route configuration before building destination features. Each
  // destination has its own widget tests; this fixture never opens a network.
  Widget takeDestination() {
    final route = observer.pushed.removeLast() as MaterialPageRoute;
    final page = route.builder(source);
    Navigator.of(source).removeRoute(route);
    return page;
  }

  testWidgets('native thread, explicit floor and tag retain page coordinates', (
    tester,
  ) async {
    await pumpHost(tester);
    await open(tester, 'forum.php?mod=viewthread&tid=42&page=3');
    final thread = takeDestination() as ThreadDetailPage;
    expect(thread.tid, '42');
    expect(thread.initialPage, 3);
    await open(tester, 'thread-42-4-1.html#pid90');
    final floor = takeDestination() as ThreadDetailPage;
    expect(floor.targetPid, '90');
    expect(floor.initialPage, 4);
    expect(locator.requests, isEmpty);
    await open(tester, 'misc.php?mod=tag&id=15&page=2');
    final tag = takeDestination() as YamiboTagThreadPage;
    expect(tag.tagId, '15');
    expect(tag.page, 2);
  });

  testWidgets(
    'locates an unspecified floor and ignores a late result behind another route',
    (tester) async {
      await pumpHost(tester);
      await open(tester, 'forum.php?mod=redirect&goto=findpost&ptid=42&pid=90');
      expect(observer.pushed, isEmpty);
      locator.requests.single.complete(
        const ApiSuccess(
          ThreadPostLocation(tid: '42', pid: '90', page: 5, url: ''),
        ),
      );
      await tester.idle();
      expect((takeDestination() as ThreadDetailPage).initialPage, 5);
      await open(tester, 'forum.php?mod=redirect&goto=findpost&ptid=42&pid=91');
      final other = MaterialPageRoute<void>(builder: (_) => const Scaffold());
      unawaited(Navigator.of(source).push(other));
      locator.requests.last.complete(
        const ApiSuccess(
          ThreadPostLocation(tid: '42', pid: '91', page: 6, url: ''),
        ),
      );
      await tester.idle();
      expect(observer.pushed, [other]);
      Navigator.of(source).removeRoute(other);
    },
  );

  testWidgets(
    'mobile profile, direct, group, compose and center links open native destinations',
    (tester) async {
      await pumpHost(tester);
      for (final link in [
        'home.php?mod=space&uid=20',
        'home.php?mod=space&uid=20&do=profile&mycenter=1',
        'space-uid-20.html',
      ]) {
        await open(tester, link);
        expect((takeDestination() as UserProfilePage).uid, '20');
      }
      await open(tester, 'home.php?mod=space&do=pm&subop=view&touid=20');
      expect(
        (takeDestination() as PrivateConversationPage).target,
        const ForumConversationTarget.direct('20'),
      );
      await open(tester, 'home.php?mod=space&do=pm&subop=view&type=1&plid=20');
      expect(
        (takeDestination() as PrivateConversationPage).target,
        const ForumConversationTarget.group('20'),
      );
      await open(tester, 'home.php?mod=spacecp&ac=pm&touid=21');
      expect(
        (takeDestination() as PrivateConversationPage).target,
        const ForumConversationTarget.direct('21'),
      );
      await open(tester, 'home.php?mod=spacecp&ac=pm');
      expect(takeDestination(), isA<NewPrivateMessagePage>());
      await open(tester, 'home.php?mod=space&do=notice');
      expect(
        (takeDestination() as MessageCenterDestination).initialTab,
        MessageCenterTab.notifications,
      );
      await open(tester, 'home.php?mod=space&do=pm');
      expect(
        (takeDestination() as MessageCenterDestination).initialTab,
        MessageCenterTab.messages,
      );
      expect(web, isEmpty);
    },
  );

  testWidgets(
    'other site pages use shared webview and only HTTP external links launch',
    (tester) async {
      await pumpHost(tester);
      await open(tester, 'home.php?mod=space&do=blog&uid=20');
      takeDestination();
      expect(web.single.initialUri.queryParameters['do'], 'blog');
      expect(web.single.popOnRootBack, isTrue);
      await open(tester, 'https://example.org/read');
      expect(launcher.opened, [Uri.parse('https://example.org/read')]);
      await open(tester, 'javascript:alert(1)');
      await open(tester, 'file:///tmp/secret');
      expect(launcher.opened, hasLength(1));
      expect(observer.pushed, isEmpty);
    },
  );
}

class _RouteObserver extends NavigatorObserver {
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
  @override
  Future<bool> launch(Uri uri) async {
    opened.add(uri);
    return true;
  }
}

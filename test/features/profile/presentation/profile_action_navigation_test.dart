import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/navigation/friend_routes.dart';
import 'package:y300/app/navigation/message_routes.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_account_guard.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/profile/presentation/profile_action_navigation.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/features/auth/application/verified_session_owner.dart';
import 'package:y300/features/profile/presentation/threads/my_thread_page.dart';

const _owner = (uid: '42', revision: 0);

void main() {
  for (final action in [
    ForumUserProfileActionKind.threads,
    ForumUserProfileActionKind.replies,
  ]) {
    testWidgets('self $action opens the corresponding native directory', (
      tester,
    ) async {
      final observer = await _pump(
        tester,
        action: action,
        isMyProfile: true,
        native: true,
      );
      await tester.tap(find.byKey(const Key('open-action')));
      final page = observer.destination(tester) as MyThreadPage;
      expect(
        page.initialType,
        action == ForumUserProfileActionKind.replies
            ? UserThreadDirectoryType.replies
            : UserThreadDirectoryType.threads,
      );
    });

    testWidgets('public $action preserves the target UID', (tester) async {
      final observer = await _pump(tester, action: action);
      await tester.tap(find.byKey(const Key('open-action')));
      final page = observer.destination(tester) as UserThreadPage;
      expect(page.userId, '7');
      expect(
        page.initialType,
        action == ForumUserProfileActionKind.replies
            ? UserThreadDirectoryType.replies
            : UserThreadDirectoryType.threads,
      );
    });
  }

  testWidgets('blogs route separates self and another author', (tester) async {
    for (final self in [false, true]) {
      final observer = await _pump(
        tester,
        action: ForumUserProfileActionKind.blogs,
        isMyProfile: self,
      );
      await tester.tap(find.byKey(const Key('open-action')));
      final page = observer.destination(tester) as ProfileBlogPage;
      expect(page.ownerUserId, self ? isNull : '7');
      expect(page.initialScope, UserBlogFeedScope.self);
    }
  });

  testWidgets('message center is available before self profile loads', (
    tester,
  ) async {
    final observer = await _pump(
      tester,
      action: ForumUserProfileActionKind.messages,
      isMyProfile: true,
      native: true,
    );
    await tester.tap(find.byKey(const Key('open-action')));
    expect(observer.destination(tester), isA<MessageCenterDestination>());
  });

  testWidgets('the self friends shortcut opens the native directory', (
    tester,
  ) async {
    final observer = await _pump(
      tester,
      action: ForumUserProfileActionKind.friends,
      isMyProfile: true,
      native: true,
    );
    await tester.tap(find.byKey(const Key('open-action')));
    final page = observer.destination(tester) as MyFriendsDestination;
    expect(page.initialScope, ForumFriendFeedScope.friends);
    expect(page.initialPage, 1);
  });

  for (final (query, scope, page) in [
    ('mobile=2', ForumFriendFeedScope.friends, 1),
    ('view=visitor&page=3&mobile=2', ForumFriendFeedScope.visitors, 3),
    ('view=trace&page=2', ForumFriendFeedScope.footprints, 2),
    ('view=online&type=member&page=4', ForumFriendFeedScope.online, 4),
  ]) {
    testWidgets(
      'advertised friends $query opens an account-bound native feed',
      (tester) async {
        final observer = await _pump(
          tester,
          action: ForumUserProfileActionKind.friends,
          isMyProfile: true,
          link: ForumUserProfileActionLink(
            kind: ForumUserProfileActionKind.friends,
            uri: Uri.parse(
              'https://bbs.yamibo.com/home.php?mod=space&do=friend&$query',
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('open-action')));
        final guard = observer.destination(tester) as ForumWebViewAccountGuard;
        expect(guard.accountId, _owner.uid);
        final destination =
            guard.builder(
                  tester.element(find.byKey(const Key('open-action'))),
                  () => true,
                )
                as MyFriendsDestination;
        expect(destination.initialScope, scope);
        expect(destination.initialPage, page);
      },
    );
  }

  testWidgets('friends requires an advertised same-site source link', (
    tester,
  ) async {
    for (final link in <ForumUserProfileActionLink?>[
      null,
      ForumUserProfileActionLink(
        kind: ForumUserProfileActionKind.friends,
        uri: Uri.parse('https://foreign.test/home.php?mod=space&do=friend'),
      ),
      ForumUserProfileActionLink(
        kind: ForumUserProfileActionKind.friends,
        uri: Uri.parse('https://bbs.yamibo.com/member.php?mod=space&do=friend'),
      ),
    ]) {
      final observer = await _pump(
        tester,
        action: ForumUserProfileActionKind.friends,
        isMyProfile: true,
        link: link,
      );
      await tester.tap(find.byKey(const Key('open-action')));
      expect(observer.routes, hasLength(1));
    }
  });

  testWidgets('friends preserves action, viewer and current-owner checks', (
    tester,
  ) async {
    final link = ForumUserProfileActionLink(
      kind: ForumUserProfileActionKind.friends,
      uri: Uri.parse('https://bbs.yamibo.com/home.php?mod=space&do=friend'),
    );
    for (final (self, owner, target, current, viewer, advertised) in [
      (true, null, '42', true, null, true),
      (true, _owner, '7', true, null, true),
      (false, _owner, '7', true, null, true),
      (true, _owner, '42', false, null, true),
      (true, _owner, '42', true, '99', true),
      (true, _owner, '42', true, null, false),
    ]) {
      final observer = await _pump(
        tester,
        action: ForumUserProfileActionKind.friends,
        isMyProfile: self,
        owner: owner,
        targetUserId: target,
        currentOwner: current,
        responseViewer: viewer,
        advertisesAction: advertised,
        link: link,
      );
      await tester.tap(find.byKey(const Key('open-action')));
      expect(observer.routes, hasLength(1));
    }
  });

  testWidgets('a covered profile cannot open its advertised friends link', (
    tester,
  ) async {
    final observer = await _pump(
      tester,
      action: ForumUserProfileActionKind.friends,
      isMyProfile: true,
      link: ForumUserProfileActionLink(
        kind: ForumUserProfileActionKind.friends,
        uri: Uri.parse('https://bbs.yamibo.com/home.php?mod=space&do=friend'),
      ),
    );
    final source = tester.element(find.byKey(const Key('open-action')));
    final callback = tester
        .widget<IconButton>(find.byKey(const Key('open-action')))
        .onPressed!;
    final coveringRoute = MaterialPageRoute<void>(
      builder: (_) => const SizedBox(),
    );
    unawaited(Navigator.of(source).push(coveringRoute));
    callback();
    expect(observer.routes, hasLength(2));
    expect(observer.routes.last, same(coveringRoute));
  });

  testWidgets('public private message uses native conversation identity', (
    tester,
  ) async {
    ForumConversationTarget? target;
    String? openedTitle;
    await _pump(
      tester,
      action: ForumUserProfileActionKind.sendMessage,
      conversationRoute: (value, {title = ''}) {
        target = value;
        openedTitle = title;
        return MaterialPageRoute<void>(builder: (_) => const SizedBox());
      },
    );
    await tester.tap(find.byKey(const Key('open-action')));
    expect(target, const ForumConversationTarget.direct('7'));
    expect(openedTitle, 'profile-member');
  });

  for (final owner in <VerifiedSessionOwner?>[null, _owner]) {
    testWidgets('private message rejects guest or own UID for $owner', (
      tester,
    ) async {
      final observer = await _pump(
        tester,
        action: ForumUserProfileActionKind.sendMessage,
        owner: owner,
        targetUserId: owner?.uid ?? '7',
      );
      await tester.tap(find.byKey(const Key('open-action')));
      expect(observer.routes, hasLength(1));
    });
  }

  testWidgets('settings opens the account-bound source WebView destination', (
    tester,
  ) async {
    final uri = Uri.parse('https://bbs.yamibo.com/home.php?mod=spacecp');
    ForumWebViewLaunchConfig? opened;
    await _pump(
      tester,
      action: ForumUserProfileActionKind.settings,
      isMyProfile: true,
      link: ForumUserProfileActionLink(
        kind: ForumUserProfileActionKind.settings,
        uri: uri,
      ),
      webRoute: (config) {
        opened = config;
        return MaterialPageRoute<Object?>(builder: (_) => const SizedBox());
      },
    );
    await tester.tap(find.byKey(const Key('open-action')));
    expect(opened?.initialUri, uri);
    expect(opened?.expectedAccountId, _owner.uid);
    expect(opened?.popOnRootBack, isTrue);
  });

  testWidgets('friends keeps the exact validated template URI', (tester) async {
    final uri = Uri.parse(
      'https://bbs.yamibo.com/home.php?mod=space&do=friend',
    );
    ForumWebViewLaunchConfig? opened;
    await _pump(
      tester,
      action: ForumUserProfileActionKind.friends,
      isMyProfile: true,
      link: ForumUserProfileActionLink(
        kind: ForumUserProfileActionKind.friends,
        uri: uri,
      ),
      webRoute: (config) {
        opened = config;
        return MaterialPageRoute<Object?>(builder: (_) => const SizedBox());
      },
    );
    await tester.tap(find.byKey(const Key('open-action')));
    expect(opened?.initialUri, uri);
    expect(opened?.expectedAccountId, _owner.uid);
    expect(opened?.popOnRootBack, isTrue);
  });

  for (final uri in [
    'https://other.example/home.php?mod=spacecp',
    'https://bbs.yamibo.com@other.example/home.php?mod=spacecp',
    'https://bbs.yamibo.com/member.php?mod=logging',
    'http://bbs.yamibo.com/home.php?mod=spacecp',
    'https://bbs.yamibo.com/home.php?mod=spacecp#unsafe',
  ]) {
    testWidgets('web action rejects invalid source destination $uri', (
      tester,
    ) async {
      final observer = await _pump(
        tester,
        action: ForumUserProfileActionKind.settings,
        isMyProfile: true,
        link: ForumUserProfileActionLink(
          kind: ForumUserProfileActionKind.settings,
          uri: Uri.parse(uri),
        ),
      );
      await tester.tap(find.byKey(const Key('open-action')));
      expect(observer.routes, hasLength(1));
    });
  }

  testWidgets('stale owner cannot open either native or advertised actions', (
    tester,
  ) async {
    for (final native in [false, true]) {
      final observer = await _pump(
        tester,
        action: ForumUserProfileActionKind.threads,
        isMyProfile: true,
        native: native,
        currentOwner: false,
      );
      await tester.tap(find.byKey(const Key('open-action')));
      expect(observer.routes, hasLength(1));
    }
  });

  testWidgets('advertised actions are bound to their response viewer', (
    tester,
  ) async {
    final observer = await _pump(
      tester,
      action: ForumUserProfileActionKind.threads,
      responseViewer: '99',
    );
    await tester.tap(find.byKey(const Key('open-action')));
    expect(observer.routes, hasLength(1));
  });

  testWidgets('web operations require the advertised destination', (
    tester,
  ) async {
    final observer = await _pump(
      tester,
      action: ForumUserProfileActionKind.settings,
      isMyProfile: true,
    );
    await tester.tap(find.byKey(const Key('open-action')));
    expect(observer.routes, hasLength(1));
  });
}

Future<_Observer> _pump(
  WidgetTester tester, {
  required ForumUserProfileActionKind action,
  bool isMyProfile = false,
  bool native = false,
  bool currentOwner = true,
  bool advertisesAction = true,
  String? targetUserId,
  String? responseViewer,
  VerifiedSessionOwner? owner = _owner,
  ForumUserProfileActionLink? link,
  PrivateConversationRouteFactory? conversationRoute,
  ForumWebViewRouteFactory? webRoute,
}) async {
  final observer = _Observer();
  final profile = ForumUserProfileData(
    identity: ProfileUserIdentity(
      userId: targetUserId ?? (isMyProfile ? '42' : '7'),
      displayName: 'profile-member',
    ),
    viewerUserId: responseViewer,
    metrics: const [],
    details: const [],
    actions: [if (advertisesAction) action],
    actionLinks: [?link],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        verifiedSessionOwnerProvider.overrideWithValue(owner),
        if (conversationRoute != null)
          privateConversationRouteFactoryProvider.overrideWithValue(
            conversationRoute,
          ),
        if (webRoute != null)
          forumWebViewRouteFactoryProvider.overrideWithValue(webRoute),
      ],
      child: MaterialApp(
        key: UniqueKey(),
        navigatorObservers: [observer],
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: IconButton(
              key: const Key('open-action'),
              icon: const Icon(Icons.person),
              onPressed: () => unawaited(
                native
                    ? openProfileNativeAction(
                        context: context,
                        ref: ref,
                        action: action,
                        userId: profile.identity.userId,
                        isMyProfile: isMyProfile,
                        isCurrentOwner: () => currentOwner,
                      )
                    : openProfileAction(
                        context: context,
                        ref: ref,
                        action: action,
                        profile: profile,
                        isMyProfile: isMyProfile,
                        isCurrentOwner: () => currentOwner,
                      ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return observer;
}

final class _Observer extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.add(route);

  Widget destination(WidgetTester tester) => (routes.last as MaterialPageRoute)
      .builder(tester.element(find.byKey(const Key('open-action'))));
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/forum/domain/models/forum_webview_launch_models.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/profile/presentation/threads/user_thread_page.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/features/profile/presentation/user_profile_page.dart';
import 'package:y300/features/thread/domain/services/thread_post_navigation_session.dart';
import 'package:y300/features/thread/presentation/services/thread_post_navigation.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  testWidgets('author identities open native profiles with route isolation', (
    tester,
  ) async {
    final observer = _Observer();
    final browser = <ForumWebViewLaunchConfig>[];
    final session = ThreadPostNavigationSession();
    addTearDown(session.dispose);
    late ThreadPostNavigation navigation;
    late BuildContext source;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          verifiedProfileOwnerProvider.overrideWithValue(null),
          forumWebViewRouteFactoryProvider.overrideWithValue((config) {
            browser.add(config);
            return MaterialPageRoute(builder: (_) => const SizedBox());
          }),
        ],
        child: LocalizedTestApp(
          navigatorObservers: [observer],
          home: Consumer(
            builder: (context, ref, _) {
              source = context;
              navigation = ThreadPostNavigation(
                context: context,
                ref: ref,
                tid: '100',
                imageReferer: null,
                isCurrent: () => ModalRoute.of(context)?.isCurrent != false,
                routeSession: session,
              );
              return const Scaffold();
            },
          ),
        ),
      ),
    );
    observer.pushed.clear();
    String takeProfile() {
      final route = observer.pushed.removeLast() as MaterialPageRoute;
      final page = route.builder(source) as UserProfilePage;
      Navigator.of(source).removeRoute(route);
      return page.uid;
    }

    navigation.openAuthor(_author('7'));
    expect(takeProfile(), '7');
    navigation.openCommentAuthor(
      const ThreadPostCommentEntry(
        author: 'commenter',
        authorId: '8',
        message: '',
        dateline: '',
      ),
    );
    expect(takeProfile(), '8');
    navigation.openCommentAuthor(
      const ThreadPostCommentEntry(
        author: 'commenter',
        authorId: '',
        authorUrl: 'home.php?mod=space&uid=9',
        message: '',
        dateline: '',
      ),
    );
    expect(takeProfile(), '9');
    navigation.openAuthor(_author('invalid'));
    expect(observer.pushed, isEmpty);
    final covering = MaterialPageRoute<void>(builder: (_) => const Scaffold());
    Navigator.of(source).push(covering);
    navigation.openAuthor(_author('7'));
    expect(observer.pushed, [covering]);
    Navigator.of(source).removeRoute(covering);
    expect(browser, isEmpty);
  });

  testWidgets('post content URLs open native user topics and reply coordinates', (
    tester,
  ) async {
    final observer = _Observer();
    final browser = <ForumWebViewLaunchConfig>[];
    final session = ThreadPostNavigationSession();
    addTearDown(session.dispose);
    late ThreadPostNavigation navigation;
    late BuildContext source;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          verifiedProfileOwnerProvider.overrideWithValue((
            uid: '101',
            revision: 0,
          )),
          forumWebViewRouteFactoryProvider.overrideWithValue((config) {
            browser.add(config);
            return MaterialPageRoute(builder: (_) => const SizedBox());
          }),
        ],
        child: LocalizedTestApp(
          navigatorObservers: [observer],
          home: Consumer(
            builder: (context, ref, _) {
              source = context;
              navigation = ThreadPostNavigation(
                context: context,
                ref: ref,
                tid: '100',
                imageReferer: null,
                isCurrent: () => ModalRoute.of(context)?.isCurrent != false,
                routeSession: session,
              );
              return const Scaffold();
            },
          ),
        ),
      ),
    );
    observer.pushed.clear();
    UserThreadPage takePage() {
      final route = observer.pushed.removeLast() as MaterialPageRoute;
      final page = route.builder(source) as UserThreadPage;
      Navigator.of(source).removeRoute(route);
      return page;
    }

    navigation.openLink(
      'https://bbs.yamibo.com/home.php?mod=space&uid=260328&do=thread&mobile=2',
    );
    final topics = takePage();
    expect(topics.userId, '260328');
    expect(topics.initialType, UserThreadDirectoryType.threads);
    expect(topics.initialPage, 1);
    navigation.openLink(
      'home.php?mod=space&uid=260328&do=thread&type=reply&page=4',
    );
    final replies = takePage();
    expect(replies.userId, '260328');
    expect(replies.initialType, UserThreadDirectoryType.replies);
    expect(replies.initialPage, 4);
    expect(browser, isEmpty);
    final covering = MaterialPageRoute<void>(builder: (_) => const Scaffold());
    Navigator.of(source).push(covering);
    navigation.openLink('home.php?mod=space&uid=260328&do=thread&type=reply');
    expect(observer.pushed, [covering]);
    Navigator.of(source).removeRoute(covering);
  });
}

ThreadPost _author(String uid) => ThreadPost(
  pid: '1',
  author: 'author',
  authorId: uid,
  message: '',
  number: 1,
  isFirst: true,
  dateline: '',
);

class _Observer extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

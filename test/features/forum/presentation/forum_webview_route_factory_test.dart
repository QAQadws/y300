import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/navigation/friend_routes.dart';
import 'package:y300/features/forum/presentation/forum_home_page.dart';
import 'package:y300/features/forum/presentation/forum_display_page.dart';
import 'package:y300/features/search/presentation/forum_search_page.dart';
import 'package:y300/features/thread/presentation/thread_detail_page.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_account_guard.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/auth/application/verified_session_owner.dart';
import 'package:y300/features/profile/presentation/threads/user_thread_page.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

import '../../../test_support/localized_test_app.dart';

void main() {
  for (final entry in [
    (url: 'index.php?mobile=2', type: ForumHomePage),
    (url: 'forum.php?mod=forumdisplay&fid=42&page=3', type: ForumDisplayPage),
    (url: 'search.php?mod=curforum&srhfid=42', type: ForumSearchPage),
    (url: 'thread-572514-4-1.html', type: ThreadDetailPage),
  ]) {
    testWidgets('common initial ${entry.type} skips WebView construction', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final route = container.read(forumWebViewRouteFactoryProvider)(
        ForumWebViewLaunchConfig(
          initialUri: Uri.parse('https://bbs.yamibo.com/${entry.url}'),
        ),
      );
      final built = await _inspectRouteBuilder(tester, route);
      expect(built.runtimeType, entry.type);
      if (built case final ForumDisplayPage page) {
        expect(page.fid, '42');
        expect(page.initialPage, 3);
      }
      if (built case final ThreadDetailPage page) {
        expect(page.initialPage, 4);
      }
      if (built case final ForumSearchPage page) {
        expect(page.scope, ForumSearchScope.currentForum);
        expect(page.forumId, '42');
      }
      expect(tester.takeException(), isNull);
    });
  }
  for (final purpose in ForumWebViewHostPurpose.values) {
    for (final policy in ForumWebViewNavigationPolicy.values) {
      if (prefersNativeForumNavigation(purpose: purpose, policy: policy)) {
        continue;
      }
      testWidgets('initial thread retains browser for $purpose/$policy', (
        tester,
      ) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final route = container.read(forumWebViewRouteFactoryProvider)(
          ForumWebViewLaunchConfig(
            initialUri: Uri.parse(
              'https://bbs.yamibo.com/thread-572514-1-1.html',
            ),
            purpose: purpose,
            navigationPolicy: policy,
          ),
        );
        expect(await _inspectRouteBuilder(tester, route), isA<ProviderScope>());
        expect(tester.takeException(), isNull);
      });
    }
  }
  const friendCases = [
    (query: '', scope: ForumFriendFeedScope.friends, page: 1),
    (
      query: '&uid=101&view=me&page=2',
      scope: ForumFriendFeedScope.friends,
      page: 2,
    ),
    (
      query: '&uid=101&view=online&type=member&page=2',
      scope: ForumFriendFeedScope.online,
      page: 2,
    ),
    (
      query: '&view=visitor&page=3',
      scope: ForumFriendFeedScope.visitors,
      page: 3,
    ),
    (
      query: '&uid=101&view=trace&page=4',
      scope: ForumFriendFeedScope.footprints,
      page: 4,
    ),
  ];
  for (final entry in friendCases) {
    for (final purpose in [ForumWebViewHostPurpose.browse]) {
      testWidgets(
        'initial friend ${entry.scope} page ${entry.page} builds natively for $purpose',
        (tester) async {
          var driverFactoryReads = 0;
          final container = ProviderContainer(
            overrides: [
              verifiedSessionOwnerProvider.overrideWithValue((
                uid: '101',
                revision: 0,
              )),
              forumWebViewDriverFactoryProvider.overrideWith((ref) {
                driverFactoryReads++;
                throw StateError(
                  'A native friend feed must not create a WebView',
                );
              }),
            ],
          );
          addTearDown(container.dispose);
          final route = container.read(forumWebViewRouteFactoryProvider)(
            ForumWebViewLaunchConfig(
              initialUri: Uri.parse(
                'https://bbs.yamibo.com/home.php?mod=space&do=friend${entry.query}&mobile=2',
              ),
              purpose: purpose,
            ),
          );

          final built = await _inspectRouteBuilder(tester, route);

          expect(built, isA<MyFriendsDestination>());
          final page = built as MyFriendsDestination;
          expect(page.initialScope, entry.scope);
          expect(page.initialPage, entry.page);
          expect(page.isActive, isTrue);
          expect(driverFactoryReads, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('account-bound initial friend feed preserves its viewer guard', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        verifiedSessionOwnerProvider.overrideWithValue((
          uid: '101',
          revision: 0,
        )),
      ],
    );
    addTearDown(container.dispose);
    final route = container.read(forumWebViewRouteFactoryProvider)(
      ForumWebViewLaunchConfig(
        initialUri: Uri.parse(
          'https://bbs.yamibo.com/home.php?mod=space&do=friend&view=visitor&page=3&mobile=2',
        ),
        expectedAccountId: '101',
      ),
    );
    final built = await _inspectRouteBuilder(tester, route);

    expect(built, isA<ForumWebViewAccountGuard>());
    final guard = built as ForumWebViewAccountGuard;
    expect(guard.accountId, '101');
    final inactive =
        guard.builder(
              tester.element(find.byKey(const Key('route-factory-builder'))),
              () => false,
            )
            as MyFriendsDestination;
    expect(inactive.initialScope, ForumFriendFeedScope.visitors);
    expect(inactive.initialPage, 3);
    expect(inactive.isActive, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial friend feed preserves post edit WebView purpose', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        verifiedSessionOwnerProvider.overrideWithValue((
          uid: '101',
          revision: 0,
        )),
      ],
    );
    addTearDown(container.dispose);
    final route = container.read(forumWebViewRouteFactoryProvider)(
      ForumWebViewLaunchConfig(
        initialUri: Uri.parse(
          'https://bbs.yamibo.com/home.php?mod=space&do=friend&mobile=2',
        ),
        purpose: ForumWebViewHostPurpose.postEditFallback,
      ),
    );

    final built = await _inspectRouteBuilder(tester, route);

    expect(built, isA<ProviderScope>());
    expect(built, isNot(isA<MyFriendsDestination>()));
    expect(tester.takeException(), isNull);
  });

  for (final query in [
    'uid=260328',
    'view=all',
    'view=online&type=group',
    'view=visitor&type=member',
    'page=0',
    'uid=101&uid=101',
  ]) {
    testWidgets('unsupported initial friend $query keeps a WebView route', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          verifiedSessionOwnerProvider.overrideWithValue((
            uid: '101',
            revision: 0,
          )),
        ],
      );
      addTearDown(container.dispose);
      final route = container.read(forumWebViewRouteFactoryProvider)(
        ForumWebViewLaunchConfig(
          initialUri: Uri.parse(
            'https://bbs.yamibo.com/home.php?mod=space&do=friend&$query&mobile=2',
          ),
        ),
      );

      final built = await _inspectRouteBuilder(tester, route);

      expect(built, isA<ProviderScope>());
      expect(built, isNot(isA<MyFriendsDestination>()));
      expect(tester.takeException(), isNull);
    });
  }

  for (final explicitUser in [false, true]) {
    testWidgets(
      'unverified initial friend explicitUser=$explicitUser is owner-safe',
      (tester) async {
        final container = ProviderContainer(
          overrides: [verifiedSessionOwnerProvider.overrideWithValue(null)],
        );
        addTearDown(container.dispose);
        final route = container.read(forumWebViewRouteFactoryProvider)(
          ForumWebViewLaunchConfig(
            initialUri: Uri.parse(
              'https://bbs.yamibo.com/home.php?mod=space&do=friend${explicitUser ? '&uid=101' : ''}&mobile=2',
            ),
          ),
        );

        final built = await _inspectRouteBuilder(tester, route);

        expect(
          built,
          explicitUser ? isA<ProviderScope>() : isA<MyFriendsDestination>(),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final target in ['101', '260328']) {
    for (final type in UserThreadDirectoryType.values) {
      for (final purpose in [ForumWebViewHostPurpose.browse]) {
        testWidgets(
          'initial $target $type URL builds the native directory for $purpose',
          (tester) async {
            var driverFactoryReads = 0;
            final container = ProviderContainer(
              overrides: [
                verifiedSessionOwnerProvider.overrideWithValue((
                  uid: '101',
                  revision: 0,
                )),
                forumWebViewDriverFactoryProvider.overrideWith((ref) {
                  driverFactoryReads++;
                  throw StateError(
                    'A native directory must not create a WebView',
                  );
                }),
              ],
            );
            addTearDown(container.dispose);
            final pageNumber = type == UserThreadDirectoryType.replies ? 4 : 1;
            final query =
                '${target == '101' ? '&view=me' : ''}'
                '${type == UserThreadDirectoryType.replies ? '&type=reply&page=4' : ''}';
            final route = container.read(forumWebViewRouteFactoryProvider)(
              ForumWebViewLaunchConfig(
                initialUri: Uri.parse(
                  'https://bbs.yamibo.com/home.php?mod=space&uid=$target&do=thread$query&mobile=2',
                ),
                purpose: purpose,
              ),
            );
            Widget? built;
            await tester.pumpWidget(
              LocalizedTestApp(
                home: Builder(
                  builder: (context) {
                    built = (route as MaterialPageRoute<Object?>).builder(
                      context,
                    );
                    return const SizedBox.shrink();
                  },
                ),
              ),
            );

            expect(built, isA<UserThreadPage>());
            final page = built! as UserThreadPage;
            expect(page.userId, target);
            expect(page.initialType, type);
            expect(page.initialPage, pageNumber);
            expect(driverFactoryReads, 0);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('account-bound initial directory preserves its viewer guard', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        verifiedSessionOwnerProvider.overrideWithValue((
          uid: '101',
          revision: 0,
        )),
      ],
    );
    addTearDown(container.dispose);
    final route = container.read(forumWebViewRouteFactoryProvider)(
      ForumWebViewLaunchConfig(
        initialUri: Uri.parse(
          'https://bbs.yamibo.com/home.php?mod=space&uid=260328&do=thread&type=reply&page=4&mobile=2',
        ),
        expectedAccountId: '101',
      ),
    );
    Widget? built;
    UserThreadPage? inactivePage;
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Builder(
          builder: (context) {
            built = (route as MaterialPageRoute<Object?>).builder(context);
            if (built case final ForumWebViewAccountGuard guard) {
              inactivePage =
                  guard.builder(context, () => false) as UserThreadPage;
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(built, isA<ForumWebViewAccountGuard>());
    expect((built! as ForumWebViewAccountGuard).accountId, '101');
    expect(inactivePage?.userId, '260328');
    expect(inactivePage?.initialType, UserThreadDirectoryType.replies);
    expect(inactivePage?.initialPage, 4);
    expect(inactivePage?.isActive, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial directory URL preserves post edit WebView purpose', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        verifiedSessionOwnerProvider.overrideWithValue((
          uid: '101',
          revision: 0,
        )),
      ],
    );
    addTearDown(container.dispose);
    final route = container.read(forumWebViewRouteFactoryProvider)(
      ForumWebViewLaunchConfig(
        initialUri: Uri.parse(
          'https://bbs.yamibo.com/home.php?mod=space&uid=260328&do=thread&mobile=2',
        ),
        purpose: ForumWebViewHostPurpose.postEditFallback,
      ),
    );
    Widget? built;
    await tester.pumpWidget(
      LocalizedTestApp(
        home: Builder(
          builder: (context) {
            built = (route as MaterialPageRoute<Object?>).builder(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(built, isA<ProviderScope>());
    expect(built, isNot(isA<UserThreadPage>()));
    expect(tester.takeException(), isNull);
  });

  for (final query in ['type=postcomment', 'view=all', 'view=we', 'uid=101']) {
    testWidgets('unsupported initial directory $query keeps a WebView route', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          verifiedSessionOwnerProvider.overrideWithValue((
            uid: '101',
            revision: 0,
          )),
        ],
      );
      addTearDown(container.dispose);
      final route = container.read(forumWebViewRouteFactoryProvider)(
        ForumWebViewLaunchConfig(
          initialUri: Uri.parse(
            'https://bbs.yamibo.com/home.php?mod=space&${query == 'uid=101' ? query : 'uid=260328&$query'}&do=thread&mobile=2',
          ),
        ),
      );
      Widget? built;
      await tester.pumpWidget(
        LocalizedTestApp(
          home: Builder(
            builder: (context) {
              built = (route as MaterialPageRoute<Object?>).builder(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(built, isA<ProviderScope>());
      expect(built, isNot(isA<UserThreadPage>()));
      expect(tester.takeException(), isNull);
    });
  }
}

Future<Widget> _inspectRouteBuilder(
  WidgetTester tester,
  Route<Object?> route,
) async {
  late Widget built;
  await tester.pumpWidget(
    LocalizedTestApp(
      home: Builder(
        key: const Key('route-factory-builder'),
        builder: (context) {
          built = (route as MaterialPageRoute<Object?>).builder(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return built;
}

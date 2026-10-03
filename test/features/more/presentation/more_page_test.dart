import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/settings/app_appearance_controller.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/app/theme/app_theme_palette.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/cookie_store.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/core/network/webview_cookie_sync_service.dart';
import '../../../support/forum_auth_test_support.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/auth/presentation/login_webview_page.dart';
import 'package:y300/features/composer_shared/presentation/controllers/composer_unused_image_management_controller.dart';
import 'package:y300/features/composer_shared/presentation/widgets/composer_unused_image_management_page.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/more/presentation/appearance_settings_sheet.dart';
import 'package:y300/features/more/presentation/more_page.dart';
import 'package:y300/features/profile/data/providers/daily_sign_in_providers.dart';
import 'package:y300/features/profile/data/providers/friend_read_providers.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/data/providers/thread_read_providers.dart';
import 'package:y300/features/profile/presentation/threads/my_thread_page.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/features/profile/presentation/current_account_summary_controller.dart';
import 'package:y300/features/profile/presentation/friends/my_friends_page.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/features/profile/presentation/user_profile_page.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_renderer_prototype_page.dart';
import '../../profile/test_support/blog_directory_fixture.dart';
import '../../profile/test_support/friend_read_fixture.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  for (final type in UserThreadDirectoryType.values) {
    testWidgets('account ${type.name} statistic opens its native directory', (
      tester,
    ) async {
      final directory = _ThreadDirectoryRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._moreAuthOverrides(_FakeAuthRepository(isLoggedIn: true)),
            userThreadDirectoryRepositoryProvider.overrideWithValue(directory),

            appAppearanceControllerProvider.overrideWith(
              () => _FakeAppAppearanceController(),
            ),
          ],
          child: const LocalizedTestApp(home: MorePage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('more-account-${type.name}')));
      await tester.pumpAndSettle();
      expect(find.byType(MyThreadPage), findsOneWidget);
      expect(
        tester.widget<MyThreadPage>(find.byType(MyThreadPage)).initialType,
        type,
      );
      expect(directory.queries.single.type, type);
      expect(directory.queries.single.userId, '100');
    });
  }

  testWidgets(
    'account navigation ignores competing callbacks in the same frame',
    (tester) async {
      final observer = _RouteNameObserver();
      final webLaunches = <ForumWebViewLaunchConfig>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._moreAuthOverrides(_FakeAuthRepository(isLoggedIn: true)),
            userThreadDirectoryRepositoryProvider.overrideWithValue(
              _ThreadDirectoryRepository(),
            ),
            forumWebViewRouteFactoryProvider.overrideWithValue(
              _profileWebRoutes(webLaunches),
            ),

            appAppearanceControllerProvider.overrideWith(
              () => _FakeAppAppearanceController(),
            ),
          ],
          child: LocalizedTestApp(
            home: const MorePage(),
            navigatorObservers: [observer],
          ),
        ),
      );
      await tester.pumpAndSettle();
      VoidCallback statisticTap(String type) => tester
          .widget<InkWell>(
            find.descendant(
              of: find.byKey(Key('more-account-$type')),
              matching: find.byType(InkWell),
            ),
          )
          .onTap!;
      final threadTap = statisticTap('threads');
      final replyTap = statisticTap('replies');
      final creditTap = statisticTap('credits');
      final profileTap = tester
          .widget<InkWell>(find.byKey(const Key('more-account-avatar')))
          .onTap!;
      final logoutTap = tester
          .widget<IconButton>(find.byKey(const Key('more-logout-entry')))
          .onPressed!;
      final menuTaps = <VoidCallback>[];
      for (final name in ['threads', 'blogs', 'friends']) {
        final entry = find.byKey(Key('more-my-$name-entry'));
        await _scrollUntilVisibleIfNeeded(tester, entry);
        menuTaps.add(tester.widget<ListTile>(entry).onTap!);
      }
      threadTap();
      for (final tap in menuTaps) {
        tap();
      }
      creditTap();
      replyTap();
      profileTap();
      logoutTap();
      await tester.pumpAndSettle();
      expect(find.byType(MyThreadPage), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(observer.pushedNames.length, 2);
      expect(webLaunches, isEmpty);
    },
  );

  for (final action in [
    ForumUserProfileActionKind.threads,
    ForumUserProfileActionKind.blogs,
    ForumUserProfileActionKind.friends,
  ]) {
    testWidgets(
      'my ${action.name} menu opens the native current-account page',
      (tester) async {
        final directory = _ThreadDirectoryRepository();
        final blogs = BlogDirectoryFixture();
        final friends = _emptyFriends();
        final webLaunches = <ForumWebViewLaunchConfig>[];
        final summary = _AccountSummaryRepository(
          () => const CurrentUserProfileData(
            identity: ProfileUserIdentity(userId: '100', displayName: 'tester'),
            creditTotal: 42,
          ),
        );
        await _pumpMyContentPage(
          tester,
          isLoggedIn: true,
          directory: directory,
          blogs: blogs,
          friends: friends,
          launches: webLaunches,
          summary: summary,
        );
        final entry = find.byKey(Key('more-my-${action.name}-entry'));
        await _scrollUntilVisibleIfNeeded(tester, entry);
        await tester.tap(entry);
        await tester.pumpAndSettle();

        final Finder destination;
        switch (action) {
          case ForumUserProfileActionKind.threads:
            destination = find.byType(MyThreadPage);
            expect(destination, findsOneWidget);
            expect(
              tester.widget<MyThreadPage>(destination).initialType,
              UserThreadDirectoryType.threads,
            );
            expect(directory.queries.single.userId, '100');
            expect(
              directory.queries.single.type,
              UserThreadDirectoryType.threads,
            );
            expect(blogs.queries, isEmpty);
            expect(friends.requests, isEmpty);
          case ForumUserProfileActionKind.blogs:
            destination = find.byType(ProfileBlogPage);
            expect(destination, findsOneWidget);
            expect(
              tester.widget<ProfileBlogPage>(destination).initialScope,
              UserBlogFeedScope.self,
            );
            expect(
              tester.widget<ProfileBlogPage>(destination).ownerUserId,
              isNull,
            );
            expect(blogs.queries.single.scope, UserBlogFeedScope.self);
            expect(blogs.queries.single.ownerUserId, '100');
            expect(directory.queries, isEmpty);
            expect(friends.requests, isEmpty);
          case ForumUserProfileActionKind.friends:
            destination = find.byType(MyFriendsPage);
            expect(destination, findsOneWidget);
            expect(friends.requests.single.query.accountUserId, '100');
            expect(
              friends.requests.single.query.scope,
              ForumFriendFeedScope.friends,
            );
            expect(directory.queries, isEmpty);
            expect(blogs.queries, isEmpty);
          default:
            fail('Unexpected content action');
        }
        expect(webLaunches, isEmpty);
        expect(summary.reads, 1);
        Navigator.of(tester.element(destination)).pop();
        await tester.pumpAndSettle();
        expect(find.byType(MorePage), findsOneWidget);
        expect(summary.reads, 2);
        expect(tester.widget<ListTile>(entry).onTap, isNotNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final completesLogin in [true, false]) {
    testWidgets(
      'guest friends menu ${completesLogin ? 'continues after verified login' : 'stays on More after cancelled login'}',
      (tester) async {
        final friends = _emptyFriends();
        final webLaunches = <ForumWebViewLaunchConfig>[];
        final observer = _RouteNameObserver();
        await _pumpMyContentPage(
          tester,
          isLoggedIn: false,
          friends: friends,
          launches: webLaunches,
          observer: observer,
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(MorePage)),
        );
        final entry = find.byKey(const Key('more-my-friends-entry'));
        await _scrollUntilVisibleIfNeeded(tester, entry);
        final tap = tester.widget<ListTile>(entry).onTap!;
        tap();
        tap();
        expect(observer.pushedNames.last, LoginWebViewPage.routeName);
        expect(
          observer.pushedNames.where(
            (name) => name == LoginWebViewPage.routeName,
          ),
          hasLength(1),
        );
        expect(friends.requests, isEmpty);

        // Simulate the verified login handoff without building a platform view.
        if (completesLogin) {
          container
              .read(authSessionControllerProvider.notifier)
              .acceptSession(
                const ForumSessionIdentity(
                  userId: '200',
                  username: 'next-account',
                ),
              );
        }
        tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .pop(completesLogin);
        await tester.pumpAndSettle();

        expect(webLaunches, isEmpty);
        if (completesLogin) {
          expect(find.byType(MyFriendsPage), findsOneWidget);
          expect(friends.requests.single.query.accountUserId, '200');
          expect(
            friends.requests.single.query.scope,
            ForumFriendFeedScope.friends,
          );
          expect(observer.pushedNames, hasLength(3));
        } else {
          expect(find.byType(MorePage), findsOneWidget);
          expect(find.byType(MyFriendsPage), findsNothing);
          expect(friends.requests, isEmpty);
          expect(observer.pushedNames, hasLength(2));
          expect(tester.widget<ListTile>(entry).onTap, isNotNull);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'credit statistics open one account-bound route and refresh totals on return',
    (tester) async {
      var credits = 12;
      final summary = _AccountSummaryRepository(
        () => CurrentUserProfileData(
          identity: const ProfileUserIdentity(
            userId: '100',
            displayName: 'tester',
          ),
          creditTotal: credits,
        ),
      );
      final webLaunches = <ForumWebViewLaunchConfig>[];
      final observer = _RouteNameObserver();
      await _pumpCreditPage(
        tester,
        summary: summary,
        launches: webLaunches,
        observer: observer,
      );
      expect(summary.reads, 1);
      final creditsTap = _accountStatisticButton(tester, 'credits').onTap!;
      final threadsTap = _accountStatisticButton(tester, 'threads').onTap!;
      final repliesTap = _accountStatisticButton(tester, 'replies').onTap!;
      final profileTap = tester
          .widget<InkWell>(find.byKey(const Key('more-account-avatar')))
          .onTap!;
      final logoutTap = tester
          .widget<IconButton>(find.byKey(const Key('more-logout-entry')))
          .onPressed!;

      creditsTap();
      creditsTap();
      threadsTap();
      repliesTap();
      profileTap();
      logoutTap();
      await tester.pumpAndSettle();

      expect(webLaunches, hasLength(1));
      expect(
        webLaunches.single.initialUri,
        Uri.parse('https://bbs.yamibo.com/plugin.php?id=zqlj_sign&mobile=2'),
      );
      expect(webLaunches.single.popOnRootBack, isTrue);
      expect(webLaunches.single.expectedAccountId, '100');
      expect(find.byKey(const Key('test-profile-webview')), findsOneWidget);
      expect(find.byType(MyThreadPage, skipOffstage: false), findsNothing);
      expect(find.byType(MyProfilePage, skipOffstage: false), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(observer.pushedNames, hasLength(2));
      expect(summary.reads, 1);
      for (final name in ['threads', 'replies', 'credits']) {
        expect(
          _accountStatisticButton(tester, name, skipOffstage: false).onTap,
          isNull,
        );
      }
      expect(
        tester
            .widget<InkWell>(
              find.byKey(const Key('more-account-avatar'), skipOffstage: false),
            )
            .onTap,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const Key('more-logout-entry'), skipOffstage: false),
            )
            .onPressed,
        isNull,
      );

      credits = 19;
      Navigator.of(
        tester.element(find.byKey(const Key('test-profile-webview'))),
      ).pop();
      await tester.pumpAndSettle();

      expect(find.byType(MorePage), findsOneWidget);
      expect(summary.reads, 2);
      final counter = find.descendant(
        of: find.byKey(const Key('more-account-credits')),
        matching: find.byType(AnimatedFlipCounter),
      );
      expect(tester.widget<AnimatedFlipCounter>(counter).value, 19);
      expect(_accountStatisticButton(tester, 'credits').onTap, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'returning from old credit details does not refresh a new owner',
    (tester) async {
      var uid = '100';
      final summary = _AccountSummaryRepository(
        () => CurrentUserProfileData(
          identity: ProfileUserIdentity(
            userId: uid,
            displayName: 'Account $uid',
          ),
          creditTotal: uid == '100' ? 12 : 27,
        ),
      );
      final webLaunches = <ForumWebViewLaunchConfig>[];
      await _pumpCreditPage(tester, summary: summary, launches: webLaunches);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MorePage)),
      );
      final l10n = AppLocalizations.of(tester.element(find.byType(MorePage)));
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('more-account-credits')),
          matching: find.text(l10n.moreAccountCreditLabel),
        ),
      );
      await tester.pumpAndSettle();
      expect(webLaunches.single.expectedAccountId, '100');
      expect(summary.reads, 1);

      uid = '200';
      container
          .read(authSessionControllerProvider.notifier)
          .acceptSession(
            const ForumSessionIdentity(userId: '200', username: 'next-account'),
          );
      await tester.pumpAndSettle();
      expect(container.read(verifiedProfileOwnerProvider)?.uid, '200');
      // Offstage consumers may pause; observe the new summary before returning.
      expect(
        container.read(currentAccountSummaryControllerProvider).owner?.uid,
        '200',
      );
      await tester.pumpAndSettle();
      expect(summary.reads, 2);

      Navigator.of(
        tester.element(find.byKey(const Key('test-profile-webview'))),
      ).pop();
      await tester.pumpAndSettle();

      expect(summary.reads, 2);
      expect(webLaunches, hasLength(1));
      expect(find.text('Account 200'), findsOneWidget);
      final counter = find.descendant(
        of: find.byKey(const Key('more-account-credits')),
        matching: find.byType(AnimatedFlipCounter),
      );
      expect(tester.widget<AnimatedFlipCounter>(counter).value, 27);
      expect(_accountStatisticButton(tester, 'credits').onTap, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('MorePage builds dark theme chrome', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._moreAuthOverrides(_FakeAuthRepository(isLoggedIn: false)),

          appAppearanceControllerProvider.overrideWith(
            () => _FakeAppAppearanceController(),
          ),
        ],
        child: LocalizedTestApp(theme: AppTheme.dark(), home: const MorePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byKey(const Key('more-appearance-entry')), findsOneWidget);
    expect(find.byKey(const Key('more-data-storage-entry')), findsOneWidget);
  });

  testWidgets('MorePage renders entries without descriptions', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._moreAuthOverrides(_FakeAuthRepository(isLoggedIn: false)),

          appAppearanceControllerProvider.overrideWith(
            () => _FakeAppAppearanceController(),
          ),
        ],
        child: const LocalizedTestApp(home: MorePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('更多'), findsWidgets);
    expect(find.byKey(const Key('more-login-entry')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byKey(const Key('more-login-entry')),
      ),
      findsOneWidget,
    );
    expect(find.text('登录'), findsOneWidget);
    expect(find.byKey(const Key('more-my-profile-entry')), findsNothing);
    expect(find.byKey(const Key('more-daily-sign-in-entry')), findsNothing);
    expect(find.byKey(const Key('more-unused-images-entry')), findsOneWidget);
    expect(find.text('未使用图片管理'), findsOneWidget);
    expect(find.byKey(const Key('more-forum-mode-entry')), findsNothing);
    expect(find.byKey(const Key('more-appearance-entry')), findsOneWidget);
    expect(find.text('外观与文字'), findsOneWidget);
    expect(
      find.byKey(const Key('more-navigation-management-entry')),
      findsOneWidget,
    );
    expect(find.text('导航栏管理'), findsOneWidget);
    expect(find.byKey(const Key('more-cache-settings-entry')), findsNothing);
    expect(find.byKey(const Key('more-data-storage-entry')), findsOneWidget);
    expect(find.text('数据与存储'), findsOneWidget);
    final l10n = AppLocalizations.of(tester.element(find.byType(MorePage)));
    _expectMyContentEntryOrderAndLabels(tester, l10n);
    expect(find.text(l10n.moreMyProfile), findsNothing);
    expect(find.text(l10n.moreMyProfileSignedOutSubtitle), findsNothing);
    expect(find.text(l10n.moreUnusedImagesSubtitle), findsNothing);
    expect(find.text(l10n.moreDataAndStorageSubtitle), findsNothing);
    expect(find.text(l10n.moreVisibleNavigationCount(5)), findsNothing);
    await _scrollUntilVisibleIfNeeded(
      tester,
      find.byKey(const Key('more-download-queue-entry')),
    );
    expect(find.byKey(const Key('more-download-queue-entry')), findsOneWidget);
    expect(find.text('缓存队列'), findsOneWidget);
    expect(find.text(l10n.moreDownloadEmpty), findsNothing);
    expect(find.byIcon(Icons.offline_pin_outlined), findsOneWidget);
    expect(find.byKey(const Key('about-check-update-entry')), findsNothing);
    expect(
      find.byKey(const Key('more-reader-settings-placeholder')),
      findsNothing,
    );
    await _scrollUntilVisibleIfNeeded(
      tester,
      find.byKey(const Key('more-composer-quill-prototype-entry')),
    );
    expect(
      find.byKey(const Key('more-composer-quill-prototype-entry')),
      findsOneWidget,
    );
    await _scrollUntilVisibleIfNeeded(
      tester,
      find.byKey(const Key('more-html-renderer-prototype-entry')),
    );
    expect(
      find.byKey(const Key('more-html-renderer-prototype-entry')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('more-thread-detail-diagnostic-switch')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('more-thread-detail-diagnostic-copy-entry')),
      findsNothing,
    );
    await _scrollUntilVisibleIfNeeded(
      tester,
      find.byKey(const Key('more-about-entry')),
    );
    expect(find.byKey(const Key('more-about-entry')), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    expect(find.text(l10n.moreAboutSubtitle), findsNothing);
  });

  testWidgets('MorePage cache queue entry supports large Traditional text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._moreAuthOverrides(_FakeAuthRepository(isLoggedIn: false)),

          appAppearanceControllerProvider.overrideWith(
            () => _FakeAppAppearanceController(),
          ),
        ],
        child: const LocalizedTestApp(
          locale: Locale('zh', 'TW'),
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(1.6),
            ),
            child: MorePage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    _expectMyContentEntryOrderAndLabels(
      tester,
      AppLocalizations.of(tester.element(find.byType(MorePage))),
    );
    await _scrollUntilVisibleIfNeeded(tester, find.text('快取佇列'));
    expect(find.text('快取佇列'), findsOneWidget);
    final l10n = AppLocalizations.of(tester.element(find.byType(MorePage)));
    expect(find.text(l10n.moreDownloadEmpty), findsNothing);
    expect(find.byIcon(Icons.offline_pin_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MorePage opens the HTML renderer prototype in debug builds', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._moreAuthOverrides(_FakeAuthRepository(isLoggedIn: false)),

          appAppearanceControllerProvider.overrideWith(
            () => _FakeAppAppearanceController(),
          ),
        ],
        child: const LocalizedTestApp(home: MorePage()),
      ),
    );
    await tester.pumpAndSettle();

    final entry = find.byKey(const Key('more-html-renderer-prototype-entry'));
    await _scrollUntilVisibleIfNeeded(tester, entry);
    await tester.drag(find.byType(ListView), const Offset(0, -80));
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ForumHtmlRendererPrototypePage), findsOneWidget);
    expect(find.text('HTML 正文渲染原型'), findsWidgets);
  });

  testWidgets('MorePage renders logout entry when signed in', (tester) async {
    final repository = _FakeAuthRepository(isLoggedIn: true);
    final profileRepository = _SignedProfileRepository();
    final signInRepository = _SignedDailySignInRepository();
    final webLaunches = <ForumWebViewLaunchConfig>[];
    final summaryRepository = _AccountSummaryRepository(
      () => const CurrentUserProfileData(
        identity: ProfileUserIdentity(userId: '100', displayName: 'tester'),
        groupName: '普通会员',
        creditTotal: 42,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._moreAuthOverrides(
            repository,
            summaryRepository: summaryRepository,
          ),
          dailySignInRepositoryProvider.overrideWithValue(signInRepository),
          forumWebViewRouteFactoryProvider.overrideWithValue(
            _profileWebRoutes(webLaunches),
          ),
          forumUserProfileRepositoryProvider.overrideWithValue(
            profileRepository,
          ),

          appAppearanceControllerProvider.overrideWith(
            () => _FakeAppAppearanceController(),
          ),
          webViewCookieSyncServiceProvider.overrideWithValue(
            _FakeWebViewCookieSyncService(),
          ),
        ],
        child: const LocalizedTestApp(home: MorePage()),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.byType(MorePage)));
    expect(find.byKey(const Key('more-login-entry')), findsNothing);
    expect(find.byKey(const Key('more-logout-entry')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byKey(const Key('more-logout-entry')),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('more-my-profile-entry')), findsNothing);
    expect(find.text(l10n.moreLogout), findsNothing);
    expect(find.byTooltip(l10n.moreLogout), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('more-logout-entry')))
          .onPressed,
      isNotNull,
    );
    expect(find.text('tester'), findsOneWidget);
    expect(find.text('普通会员'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('more-account-credits')),
        matching: find.byWidgetPredicate(
          (widget) => widget is AnimatedFlipCounter && widget.value == 42,
        ),
      ),
      findsOneWidget,
    );
    expect(summaryRepository.reads, 1);

    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('more-page-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();
    scrollable.position.jumpTo(0);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(summaryRepository.reads, 1);

    expect(find.byKey(const Key('more-daily-sign-in-entry')), findsNothing);
    expect(find.byKey(const Key('daily-auto-sign-in-toggle')), findsOneWidget);
    expect(signInRepository.reads, 0);

    await tester.tap(find.byKey(const Key('more-account-name')));
    await tester.pumpAndSettle();

    expect(find.byType(MyProfilePage), findsOneWidget);
    expect(find.byKey(const Key('test-profile-webview')), findsNothing);
    expect(profileRepository.queries.single.userId, '100');
    expect(profileRepository.queries.single.view, ForumUserProfileView.self);
    expect(profileRepository.queries.single.viewerUserId, '100');
    expect(webLaunches, isEmpty);

    Navigator.of(tester.element(find.byType(MyProfilePage))).pop();
    await tester.pumpAndSettle();
    expect(summaryRepository.reads, 2);

    await tester.drag(
      find.byKey(const Key('more-page-list')),
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();
    expect(summaryRepository.reads, 3);

    // Cancelling the existing confirmation leaves the current account intact.
    await tester.tap(find.byKey(const Key('more-logout-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();
    expect(repository.logoutCount, 0);
    expect(find.text('tester'), findsOneWidget);

    await tester.tap(find.byKey(const Key('more-logout-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('more-logout-confirm-button')));
    await tester.pumpAndSettle();

    expect(repository.logoutCount, 1);
    expect(find.byKey(const Key('more-login-entry')), findsOneWidget);
    expect(find.text('已退出登录'), findsOneWidget);
    expect(find.byKey(const Key('more-account-group')), findsNothing);
    expect(find.byKey(const Key('more-account-credits')), findsNothing);
  });

  testWidgets('MorePage login entry navigates to the WebView login page', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(isLoggedIn: false);
    final routeObserver = _RouteNameObserver();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._moreAuthOverrides(repository),

          appAppearanceControllerProvider.overrideWith(
            () => _FakeAppAppearanceController(),
          ),
        ],
        child: LocalizedTestApp(
          home: const MorePage(),
          navigatorObservers: [routeObserver],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final login = tester
        .widget<TextButton>(find.byKey(const Key('more-login-entry')))
        .onPressed!;
    login();
    login();
    // 不 pump 目标页：Navigator.push 会同步通知 observer.didPush 记录路由名，
    // 而目标页（含真实 InAppWebView 平台视图）的 build 被推迟到下一帧。此处
    // 只断言“入栈了正确的登录路由”，避免在纯 widget 测试环境构建平台视图。
    // 登录检测/校验逻辑已由 resolver 单测覆盖。

    expect(routeObserver.pushedNames, contains(LoginWebViewPage.routeName));
    expect(
      routeObserver.pushedNames.where(
        (name) => name == LoginWebViewPage.routeName,
      ),
      hasLength(1),
    );
  });

  testWidgets('account avatar opens the current account after login', (
    tester,
  ) async {
    final routeObserver = _RouteNameObserver();
    final profileRepository = _SignedProfileRepository();
    final webLaunches = <ForumWebViewLaunchConfig>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._moreAuthOverrides(_FakeAuthRepository(isLoggedIn: false)),
          forumWebViewRouteFactoryProvider.overrideWithValue(
            _profileWebRoutes(webLaunches),
          ),

          appAppearanceControllerProvider.overrideWith(
            () => _FakeAppAppearanceController(),
          ),
          forumUserProfileRepositoryProvider.overrideWithValue(
            profileRepository,
          ),
          dailySignInRepositoryProvider.overrideWithValue(
            _SignedDailySignInRepository(),
          ),
        ],
        child: LocalizedTestApp(
          home: const MorePage(),
          navigatorObservers: [routeObserver],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MorePage)),
    );

    await tester.tap(find.byKey(const Key('more-login-entry')));
    expect(routeObserver.pushedNames.last, LoginWebViewPage.routeName);

    // LoginWebViewPage verifies the session before returning true. Simulate
    // that handoff without constructing a platform WebView in this widget test.
    container
        .read(authSessionControllerProvider.notifier)
        .acceptSession(
          const ForumSessionIdentity(userId: '200', username: 'next-account'),
        );
    tester.state<NavigatorState>(find.byType(Navigator).first).pop(true);
    await tester.pumpAndSettle();

    expect(find.byType(MyProfilePage), findsNothing);
    await tester.tap(find.byKey(const Key('more-account-avatar')));
    await tester.pumpAndSettle();

    expect(find.byType(MyProfilePage), findsOneWidget);
    expect(find.byKey(const Key('test-profile-webview')), findsNothing);
    expect(profileRepository.queries.single.userId, '200');
    expect(profileRepository.queries.single.view, ForumUserProfileView.self);
    expect(webLaunches, isEmpty);
  });

  testWidgets('account avatar stays disabled when login is cancelled', (
    tester,
  ) async {
    final routeObserver = _RouteNameObserver();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._moreAuthOverrides(_FakeAuthRepository(isLoggedIn: false)),

          appAppearanceControllerProvider.overrideWith(
            () => _FakeAppAppearanceController(),
          ),
        ],
        child: LocalizedTestApp(
          home: const MorePage(),
          navigatorObservers: [routeObserver],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('more-login-entry')));
    expect(routeObserver.pushedNames.last, LoginWebViewPage.routeName);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop(false);
    await tester.pumpAndSettle();

    expect(find.byType(MorePage), findsOneWidget);
    expect(find.byType(MyProfilePage), findsNothing);
    expect(routeObserver.pushedNames.length, 2);
    expect(
      tester
          .widget<InkWell>(find.byKey(const Key('more-account-avatar')))
          .onTap,
      isNull,
    );
  });

  testWidgets('account avatar ignores duplicate taps while navigating', (
    tester,
  ) async {
    final routeObserver = _RouteNameObserver();
    final webLaunches = <ForumWebViewLaunchConfig>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._moreAuthOverrides(_FakeAuthRepository(isLoggedIn: true)),
          forumWebViewRouteFactoryProvider.overrideWithValue(
            _profileWebRoutes(webLaunches),
          ),

          appAppearanceControllerProvider.overrideWith(
            () => _FakeAppAppearanceController(),
          ),
          forumUserProfileRepositoryProvider.overrideWithValue(
            _SignedProfileRepository(),
          ),
          dailySignInRepositoryProvider.overrideWithValue(
            _SignedDailySignInRepository(),
          ),
        ],
        child: LocalizedTestApp(
          home: const MorePage(),
          navigatorObservers: [routeObserver],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tap = tester
        .widget<InkWell>(find.byKey(const Key('more-account-avatar')))
        .onTap!;
    tap();
    tap();
    await tester.pumpAndSettle();

    expect(find.byType(MyProfilePage), findsOneWidget);
    expect(find.byKey(const Key('test-profile-webview')), findsNothing);
    expect(webLaunches, isEmpty);
    expect(routeObserver.pushedNames.length, 2);
  });

  testWidgets(
    'unused images entry resumes navigation after WebView login succeeds',
    (tester) async {
      final routeObserver = _RouteNameObserver();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._moreAuthOverrides(_FakeAuthRepository(isLoggedIn: false)),

            appAppearanceControllerProvider.overrideWith(
              () => _FakeAppAppearanceController(),
            ),
            composerUnusedImageManagementControllerProvider.overrideWith(
              _FakeUnusedImagesController.new,
            ),
          ],
          child: LocalizedTestApp(
            home: const MorePage(),
            navigatorObservers: [routeObserver],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('more-unused-images-entry')));
      expect(routeObserver.pushedNames.last, LoginWebViewPage.routeName);

      tester.state<NavigatorState>(find.byType(Navigator).first).pop(true);
      await tester.pump();
      await tester.pump();

      expect(
        routeObserver.pushedNames,
        contains(ComposerUnusedImageManagementPage.routeName),
      );
      expect(find.byType(ComposerUnusedImageManagementPage), findsOneWidget);
    },
  );

  testWidgets('unused images entry stays on More after login is cancelled', (
    tester,
  ) async {
    final routeObserver = _RouteNameObserver();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._moreAuthOverrides(_FakeAuthRepository(isLoggedIn: false)),

          appAppearanceControllerProvider.overrideWith(
            () => _FakeAppAppearanceController(),
          ),
          composerUnusedImageManagementControllerProvider.overrideWith(
            _FakeUnusedImagesController.new,
          ),
        ],
        child: LocalizedTestApp(
          home: const MorePage(),
          navigatorObservers: [routeObserver],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('more-unused-images-entry')));
    tester.state<NavigatorState>(find.byType(Navigator).first).pop(false);
    await tester.pumpAndSettle();

    expect(find.byType(MorePage), findsOneWidget);
    expect(find.byType(ComposerUnusedImageManagementPage), findsNothing);
    expect(
      routeObserver.pushedNames
          .where((name) => name == ComposerUnusedImageManagementPage.routeName)
          .length,
      0,
    );
  });

  testWidgets('MorePage changes theme family and brightness independently', (
    tester,
  ) async {
    final appearanceController = _FakeAppAppearanceController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._moreAuthOverrides(_FakeAuthRepository(isLoggedIn: false)),

          appAppearanceControllerProvider.overrideWith(
            () => appearanceController,
          ),
        ],
        child: const LocalizedTestApp(home: MorePage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('more-appearance-entry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('appearance-settings-sheet')), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);
    expect(find.text('外观与文字'), findsOneWidget);
    expect(
      find.byKey(const Key('appearance-settings-close-button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('appearance-theme-segmented-button')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('appearance-theme-family-warmPaper')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('appearance-theme-family-moonWhite')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('appearance-theme-family-plumPurple')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('appearance-brightness-option-system')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check), findsNothing);
    for (final family in AppThemeFamily.values) {
      final palette = AppThemePalette.resolve(family, Brightness.light);
      final swatch = tester.widget<Container>(
        find.byKey(Key('appearance-theme-family-swatch-${family.name}')),
      );
      final primarySwatch = find.byKey(
        Key('appearance-theme-family-swatch-${family.name}-primary'),
      );
      final pageSwatch = find.byKey(
        Key('appearance-theme-family-swatch-${family.name}-page'),
      );
      expect(tester.widget<ColoredBox>(primarySwatch).color, palette.primary);
      expect(
        tester.widget<ColoredBox>(pageSwatch).color,
        palette.surfaceContainer,
      );
      expect(tester.getSize(primarySwatch).height, greaterThan(0));
      expect(tester.getSize(pageSwatch).height, greaterThan(0));
      expect(
        tester.getSize(primarySwatch).width,
        tester.getSize(pageSwatch).width,
      );
      expect((swatch.decoration! as BoxDecoration).border, isNull);
    }

    await tester.tap(
      find.byKey(const Key('appearance-theme-family-plumPurple')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('appearance-brightness-option-dark')),
    );
    await tester.pumpAndSettle();

    expect(appearanceController.themeFamily, AppThemeFamily.plumPurple);
    expect(
      appearanceController.brightnessPreference,
      AppBrightnessPreference.dark,
    );
    expect(
      find.byKey(const Key('appearance-brightness-icon-dark')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('appearance-settings-sheet')), findsNothing);
  });

  testWidgets('Appearance theme swatches follow the active brightness', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appAppearanceControllerProvider.overrideWith(
            _FakeAppAppearanceController.new,
          ),
        ],
        child: LocalizedTestApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: AppearanceSettingsSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final family in AppThemeFamily.values) {
      final palette = AppThemePalette.resolve(family, Brightness.dark);
      expect(
        tester
            .widget<ColoredBox>(
              find.byKey(
                Key('appearance-theme-family-swatch-${family.name}-primary'),
              ),
            )
            .color,
        palette.primary,
      );
      expect(
        tester
            .widget<ColoredBox>(
              find.byKey(
                Key('appearance-theme-family-swatch-${family.name}-page'),
              ),
            )
            .color,
        palette.surfaceContainer,
      );
    }
  });

  testWidgets(
    'Appearance settings keeps each option group on one scrollable row',
    (tester) async {
      tester.view.physicalSize = const Size(280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final appearanceController = _FakeAppAppearanceController();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appAppearanceControllerProvider.overrideWith(
              () => appearanceController,
            ),
          ],
          child: const LocalizedTestApp(
            locale: Locale('zh', 'TW'),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(280, 720),
                textScaler: TextScaler.linear(1.6),
              ),
              child: Scaffold(body: AppearanceSettingsSheet()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final familyStrip = find.byKey(
        const Key('appearance-theme-family-options-scroll'),
      );
      final brightnessStrip = find.byKey(
        const Key('appearance-brightness-options-scroll'),
      );
      final languageStrip = find.byKey(
        const Key('appearance-language-options-scroll'),
      );
      expect(
        tester.widget<SingleChildScrollView>(familyStrip).scrollDirection,
        Axis.horizontal,
      );
      expect(
        tester.widget<SingleChildScrollView>(brightnessStrip).scrollDirection,
        Axis.horizontal,
      );
      expect(
        tester.widget<SingleChildScrollView>(languageStrip).scrollDirection,
        Axis.horizontal,
      );

      final familyScrollable = tester.state<ScrollableState>(
        find.descendant(of: familyStrip, matching: find.byType(Scrollable)),
      );
      final brightnessScrollable = tester.state<ScrollableState>(
        find.descendant(of: brightnessStrip, matching: find.byType(Scrollable)),
      );
      final languageScrollable = tester.state<ScrollableState>(
        find.descendant(of: languageStrip, matching: find.byType(Scrollable)),
      );
      expect(familyScrollable.position.maxScrollExtent, greaterThan(0));
      expect(brightnessScrollable.position.maxScrollExtent, greaterThan(0));
      expect(languageScrollable.position.maxScrollExtent, greaterThan(0));

      _expectSameVerticalCenter(tester, const <Key>[
        Key('appearance-brightness-option-light'),
        Key('appearance-brightness-option-dark'),
        Key('appearance-brightness-option-system'),
      ]);
      _expectSameVerticalCenter(tester, const <Key>[
        Key('appearance-language-option-system'),
        Key('appearance-language-option-simplifiedChinese'),
        Key('appearance-language-option-traditionalChinese'),
      ]);
      _expectSingleLineButtonLabel(
        tester,
        const Key('appearance-brightness-option-system'),
      );
      _expectSingleLineButtonLabel(
        tester,
        const Key('appearance-language-option-traditionalChinese'),
      );

      await tester.drag(languageStrip, const Offset(-160, 0));
      await tester.pumpAndSettle();

      expect(languageScrollable.position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Appearance settings drawer changes app language', (
    tester,
  ) async {
    final appearanceController = _FakeAppAppearanceController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._moreAuthOverrides(_FakeAuthRepository(isLoggedIn: false)),

          appAppearanceControllerProvider.overrideWith(
            () => appearanceController,
          ),
        ],
        child: const LocalizedTestApp(home: MorePage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('more-appearance-entry')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('appearance-language-option-system')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('appearance-language-option-simplifiedChinese')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('appearance-language-option-traditionalChinese')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('appearance-language-icon-system')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check), findsNothing);
    expect(
      find.byKey(const Key('appearance-language-behavior-description')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('appearance-language-content-note')),
      findsNothing,
    );
    expect(find.text('界面语言跟随设备，服务器内容保持原文'), findsNothing);
    expect(find.text('用户名和网页模式内容保持原样'), findsNothing);

    await tester.tap(
      find.byKey(const Key('appearance-language-option-traditionalChinese')),
    );
    await tester.pumpAndSettle();

    expect(
      appearanceController.languagePreference,
      AppLanguage.traditionalChinese,
    );
    expect(
      find.byKey(const Key('appearance-language-icon-traditionalChinese')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.text('界面使用繁体，原生解析内容转换为繁体'), findsNothing);
  });

  testWidgets('Appearance settings drawer shows snackbar when save fails', (
    tester,
  ) async {
    final appearanceController = _FakeAppAppearanceController(failOnSave: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._moreAuthOverrides(_FakeAuthRepository(isLoggedIn: false)),

          appAppearanceControllerProvider.overrideWith(
            () => appearanceController,
          ),
        ],
        child: const LocalizedTestApp(home: MorePage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('more-appearance-entry')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('appearance-brightness-option-system')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('主题设置保存失败'), findsOneWidget);
    expect(
      appearanceController.brightnessPreference,
      AppBrightnessPreference.light,
    );
    expect(find.byKey(const Key('appearance-settings-sheet')), findsOneWidget);
    expect(
      find.byKey(const Key('appearance-brightness-icon-light')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check), findsNothing);
  });
}

void _expectMyContentEntryOrderAndLabels(
  WidgetTester tester,
  AppLocalizations l10n,
) {
  final list = tester.widget<ListView>(find.byKey(const Key('more-page-list')));
  final children = (list.childrenDelegate as SliverChildListDelegate).children;
  final unusedIndex = children.indexWhere(
    (child) => child.key == const Key('more-unused-images-entry'),
  );
  for (final (offset, name, label) in [
    (3, 'threads', l10n.profileMyThreads),
    (2, 'blogs', l10n.profileMyBlogs),
    (1, 'friends', l10n.profileMyFriendsTitle),
  ]) {
    final tile = children[unusedIndex - offset] as ListTile;
    expect(tile.key, Key('more-my-$name-entry'));
    expect((tile.title! as Text).data, label);
    expect(tile.onTap, isNotNull);
  }
}

FriendFeedFixture _emptyFriends() => FriendFeedFixture(autoComplete: true)
  ..items = []
  ..hasNext = false
  ..totalPages = 1;

Future<void> _pumpMyContentPage(
  WidgetTester tester, {
  required bool isLoggedIn,
  required FriendFeedFixture friends,
  required List<ForumWebViewLaunchConfig> launches,
  _ThreadDirectoryRepository? directory,
  BlogDirectoryFixture? blogs,
  _AccountSummaryRepository? summary,
  _RouteNameObserver? observer,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._moreAuthOverrides(
          _FakeAuthRepository(isLoggedIn: isLoggedIn),
          summaryRepository: summary,
        ),
        userThreadDirectoryRepositoryProvider.overrideWithValue(
          directory ?? _ThreadDirectoryRepository(),
        ),
        userBlogDirectoryRepositoryProvider.overrideWithValue(
          blogs ?? BlogDirectoryFixture(),
        ),
        friendFeedRepositoryProvider.overrideWithValue(friends),
        friendRemovalCommandProvider.overrideWithValue(FriendRemovalFixture()),
        forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
        forumWebViewRouteFactoryProvider.overrideWithValue(
          _profileWebRoutes(launches),
        ),

        appAppearanceControllerProvider.overrideWith(
          () => _FakeAppAppearanceController(),
        ),
      ],
      child: LocalizedTestApp(
        home: const MorePage(),
        navigatorObservers: [?observer],
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpCreditPage(
  WidgetTester tester, {
  required _AccountSummaryRepository summary,
  required List<ForumWebViewLaunchConfig> launches,
  NavigatorObserver? observer,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ..._moreAuthOverrides(
          _FakeAuthRepository(isLoggedIn: true),
          summaryRepository: summary,
        ),
        userThreadDirectoryRepositoryProvider.overrideWithValue(
          _ThreadDirectoryRepository(),
        ),
        forumWebViewRouteFactoryProvider.overrideWithValue(
          _profileWebRoutes(launches),
        ),

        appAppearanceControllerProvider.overrideWith(
          () => _FakeAppAppearanceController(),
        ),
      ],
      child: LocalizedTestApp(
        home: const MorePage(),
        navigatorObservers: [?observer],
      ),
    ),
  );
  await tester.pumpAndSettle();
}

InkWell _accountStatisticButton(
  WidgetTester tester,
  String name, {
  bool skipOffstage = true,
}) => tester.widget<InkWell>(
  find.descendant(
    of: find.byKey(Key('more-account-$name'), skipOffstage: skipOffstage),
    matching: find.byType(InkWell, skipOffstage: skipOffstage),
    skipOffstage: skipOffstage,
  ),
);

ForumWebViewRouteFactory _profileWebRoutes(
  List<ForumWebViewLaunchConfig> launches,
) => (config) {
  launches.add(config);
  return MaterialPageRoute<Object?>(
    builder: (_) => const Scaffold(key: Key('test-profile-webview')),
  );
};

void _expectSameVerticalCenter(WidgetTester tester, List<Key> keys) {
  final centers = keys
      .map((key) => tester.getCenter(find.byKey(key)).dy)
      .toList(growable: false);
  for (final center in centers.skip(1)) {
    expect(center, closeTo(centers.first, 0.01));
  }
}

void _expectSingleLineButtonLabel(WidgetTester tester, Key buttonKey) {
  final label = tester.widget<Text>(
    find.descendant(of: find.byKey(buttonKey), matching: find.byType(Text)),
  );
  expect(label.maxLines, 1);
  expect(label.softWrap, isFalse);
}

Future<void> _scrollUntilVisibleIfNeeded(
  WidgetTester tester,
  Finder finder,
) async {
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder);
    await tester.pump();
    return;
  }
  await tester.scrollUntilVisible(finder, 160);
}

List<Override> _moreAuthOverrides(
  AuthRepository repository, {
  CurrentAccountSummaryRepository? summaryRepository,
}) => [
  ...forumAuthOverrides(repository),
  if (summaryRepository != null)
    currentAccountSummaryRepositoryProvider.overrideWithValue(summaryRepository)
  else
    currentAccountSummaryRepositoryProvider.overrideWith((ref) {
      return _AccountSummaryRepository(() {
        final session = ref.read(authSessionControllerProvider).asData!.value;
        return CurrentUserProfileData(
          identity: ProfileUserIdentity(
            userId: session.uid,
            displayName: session.username,
          ),
          groupName: '普通会员',
          creditTotal: 42,
        );
      });
    }),
];

class _AccountSummaryRepository implements CurrentAccountSummaryRepository {
  _AccountSummaryRepository(this.currentData);

  final CurrentUserProfileData Function() currentData;
  int reads = 0;

  @override
  CurrentUserProfileSourceCapabilities get capabilities =>
      CurrentUserProfileSourceCapabilities(
        values: DataCapabilitySet.supported(
          CurrentUserProfileCapability.values,
        ),
      );

  @override
  Future<
    DataReadResult<CurrentUserProfileData, CurrentUserProfileReadCapabilities>
  >
  load(
    CurrentAccountSummaryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    reads++;
    return DataReadSuccess(
      data: currentData(),
      capabilities: capabilities.toReadCapabilities(),
      metadata: const DataReadMetadata.network(),
    );
  }
}

class _ThreadDirectoryRepository extends Fake
    implements UserThreadDirectoryRepository {
  final queries = <UserThreadDirectoryQuery>[];

  @override
  Future<
    DataReadResult<UserThreadDirectoryData, UserThreadDirectoryReadCapabilities>
  >
  load(
    UserThreadDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) async {
    queries.add(query);
    return DataReadSuccess(
      data: const UserThreadDirectoryData(
        items: [],
        pagination: UserThreadDirectoryPagination(
          currentPage: 1,
          hasNext: false,
          hasPrevious: false,
        ),
      ),
      capabilities: UserThreadDirectoryReadCapabilities(
        values: DataCapabilitySet<UserThreadDirectoryCapability>({}),
      ),
      metadata: const DataReadMetadata.network(),
    );
  }
}

class _RouteNameObserver extends NavigatorObserver {
  final List<String?> pushedNames = <String?>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedNames.add(route.settings.name);
    super.didPush(route, previousRoute);
  }
}

class _FakeUnusedImagesController
    extends ComposerUnusedImageManagementController {
  @override
  Future<ComposerUnusedImageManagementState> build() async {
    return ComposerUnusedImageManagementState(images: const []);
  }
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
          : const SessionInfo(
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
    return const SessionInfo(
      uid: '100',
      username: 'tester',
      formhash: 'fh',
      isLoggedIn: true,
    );
  }
}

class _FakeAppAppearanceController extends AppAppearanceController {
  _FakeAppAppearanceController({this.failOnSave = false});

  final bool failOnSave;
  var _settings = AppAppearanceSettings.defaults();

  AppThemeFamily get themeFamily => _settings.themeFamily;
  AppBrightnessPreference get brightnessPreference =>
      _settings.brightnessPreference;
  AppLanguage get languagePreference => _settings.languagePreference;

  @override
  Future<AppAppearanceSettings> build() async {
    return _settings;
  }

  @override
  Future<void> setThemeFamily(AppThemeFamily family) async {
    final previous = _settings;
    if (previous.themeFamily == family) {
      return;
    }
    _settings = previous.copyWith(themeFamily: family);
    state = AsyncData(_settings);
    if (!failOnSave) {
      return;
    }
    _settings = previous;
    state = AsyncData(previous);
    throw StateError('save failed');
  }

  @override
  Future<void> setBrightnessPreference(
    AppBrightnessPreference preference,
  ) async {
    final previous = _settings;
    if (previous.brightnessPreference == preference) {
      return;
    }
    _settings = previous.copyWith(brightnessPreference: preference);
    state = AsyncData(_settings);
    if (!failOnSave) {
      return;
    }
    _settings = previous;
    state = AsyncData(previous);
    throw StateError('save failed');
  }

  @override
  Future<void> setLanguagePreference(AppLanguage language) async {
    final previous = _settings;
    if (previous.languagePreference == language) {
      return;
    }
    _settings = previous.copyWith(languagePreference: language);
    state = AsyncData(_settings);
    if (!failOnSave) {
      return;
    }
    _settings = previous;
    state = AsyncData(previous);
    throw StateError('save failed');
  }
}

class _FakeCookieStore extends CookieStore {
  @override
  Future<Map<String, String>> readCookieMap(Uri uri) async {
    return const <String, String>{};
  }

  @override
  Future<void> saveCookies(Uri uri, Map<String, String> cookies) async {}
}

class _FakeWebViewCookieJar implements WebViewCookieJar {
  @override
  Future<void> clear() async {}

  @override
  Future<Map<String, String>> readCookies(Uri uri) async {
    return const <String, String>{};
  }

  @override
  Future<void> writeCookies(Uri uri, Map<String, String> cookies) async {}
}

class _FakeWebViewCookieSyncService extends WebViewCookieSyncService {
  _FakeWebViewCookieSyncService()
    : super(
        cookieJar: _FakeWebViewCookieJar(),
        cookieStore: _FakeCookieStore(),
      );

  @override
  Future<void> clearWebViewCookies() async {}

  @override
  Future<Map<String, String>> syncToStore(
    Uri uri, {
    bool Function()? isCurrent,
  }) async {
    return const <String, String>{};
  }
}

class _SignedProfileRepository implements ForumUserProfileRepository {
  final queries = <ForumUserProfileQuery>[];
  final policies = <CacheLoadPolicy>[];

  @override
  ForumUserProfileSourceCapabilities get capabilities =>
      ForumUserProfileSourceCapabilities(
        values: DataCapabilitySet.supported(ForumUserProfileCapability.values),
      );

  @override
  Future<DataReadResult<ForumUserProfileData, ForumUserProfileReadCapabilities>>
  load(
    ForumUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) async {
    queries.add(query);
    policies.add(cachePolicy);
    return DataReadSuccess(
      data: ForumUserProfileData(
        identity: ProfileUserIdentity(
          userId: query.userId,
          displayName: 'sample-member',
        ),
        metrics: const <ForumUserProfileMetric>[],
        details: <ForumUserProfileDetail>[
          ForumUserProfileDetail(label: 'UID', value: query.userId),
        ],
      ),
      capabilities: ForumUserProfileReadCapabilities(
        values: DataCapabilitySet.supported(ForumUserProfileCapability.values),
      ),
      metadata: const DataReadMetadata.network(),
    );
  }
}

class _SignedDailySignInRepository implements ForumDailySignInRepository {
  int reads = 0;

  @override
  ForumDailySignInSourceCapabilities get capabilities =>
      ForumDailySignInSourceCapabilities(
        values: DataCapabilitySet.supported(
          ForumDailySignInReadCapability.values,
        ),
      );

  @override
  Future<
    DataReadResult<ForumDailySignInSnapshot, ForumDailySignInReadCapabilities>
  >
  load(ForumDailySignInQuery query) async {
    reads++;
    return DataReadSuccess(
      data: ForumDailySignInSnapshot(
        userId: query.userId,
        forumDay: '20260925',
        status: ForumDailySignInStatus.signed,
      ),
      capabilities: ForumDailySignInReadCapabilities(
        values: DataCapabilitySet.supported(
          ForumDailySignInReadCapability.values,
        ),
      ),
      metadata: const DataReadMetadata.network(),
    );
  }
}

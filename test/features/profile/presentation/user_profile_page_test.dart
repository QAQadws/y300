import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/app/navigation/message_routes.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/messages/data/message_repository_provider.dart';
import 'package:y300/features/messages/domain/message_repository.dart';
import 'package:y300/features/messages/presentation/message_center_page.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/data/providers/friend_read_providers.dart';
import 'package:y300/features/profile/data/providers/thread_read_providers.dart';
import 'package:y300/features/profile/presentation/threads/my_thread_page.dart';
import 'package:y300/features/profile/presentation/friends/my_friends_page.dart';
import 'package:y300/features/profile/presentation/daily_sign_in_controller.dart';
import 'package:y300/features/profile/presentation/my_profile_webview_action.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';
import 'package:y300/features/profile/presentation/user_profile_page.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_page.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../support/forum_auth_test_support.dart';
import '../../../test_support/localized_test_app.dart';
import '../../messages/support/message_test_repository.dart';
import '../test_support/friend_read_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets(
    'WebView profile action opens native once and returns to the web host',
    (tester) async {
      final repository = _FakeProfileRepository(data: _myProfile);
      final store = YamiboSessionStore()..saveExtracted(_sessionFor('654321'));
      await _pumpMyProfile(
        tester,
        repository: repository,
        store: store,
        home: Scaffold(
          key: const Key('profile-web-host'),
          appBar: AppBar(
            actions: [
              MyProfileWebViewAction(
                currentUri: Uri.parse(
                  'https://bbs.yamibo.com/home.php?mod=space&uid=654321&do=profile&mobile=2',
                ),
              ),
            ],
          ),
        ),
      );
      final button = find.byKey(
        const Key('forum-webview-native-profile-button'),
      );
      final l10n = AppLocalizations.of(tester.element(button));
      expect(tester.widget<IconButton>(button).tooltip, l10n.profileOpenNative);
      expect(repository.queries, isEmpty);
      final open = tester.widget<IconButton>(button).onPressed!;
      open();
      open();
      await tester.pumpAndSettle();
      expect(find.byType(MyProfilePage), findsOneWidget);
      expect(repository.queries, hasLength(1));
      expect(repository.queries.single.userId, '654321');
      expect(repository.queries.single.view, ForumUserProfileView.self);

      Navigator.of(tester.element(find.byType(MyProfilePage))).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-web-host')), findsOneWidget);
      expect(tester.widget<IconButton>(button).onPressed, isNotNull);
      store.clear();
      await tester.pumpAndSettle();
      expect(button, findsNothing);
      open();
      await tester.pumpAndSettle();
      expect(find.byType(MyProfilePage), findsNothing);
      expect(repository.queries, hasLength(1));
    },
  );

  for (final uri in [
    'https://bbs.yamibo.com/home.php?mod=space&uid=777777&do=profile',
    'https://example.test/home.php?mod=space&uid=654321&do=profile',
    'https://bbs.yamibo.com/member.php?mod=logging&action=login',
    'https://bbs.yamibo.com/home.php?mod=space&uid=654321&uid=777777&do=profile',
    'about:blank',
  ]) {
    testWidgets('native self-profile action stays hidden for $uri', (
      tester,
    ) async {
      final repository = _FakeProfileRepository(data: _myProfile);
      await _pumpMyProfile(
        tester,
        repository: repository,
        home: Scaffold(
          appBar: AppBar(
            actions: [MyProfileWebViewAction(currentUri: Uri.parse(uri))],
          ),
        ),
      );
      expect(
        find.byKey(const Key('forum-webview-native-profile-button')),
        findsNothing,
      );
      expect(repository.queries, isEmpty);
    });
  }

  for (final self in [false, true]) {
    testWidgets(
      '${self ? 'self' : 'public'} initial placeholder preserves the scrollable and identity anchor',
      (tester) async {
        final initialRead = Completer<_ProfileReadResult>();
        final repository = _ScriptedProfileRepository(
          (_, _) => initialRead.future,
        );
        final directory = _ProfileThreadDirectoryRepository();
        final profile = self ? _myProfile : _profile;
        if (self) {
          await _pumpMyProfile(
            tester,
            repository: repository,
            threadDirectory: directory,
            settle: false,
          );
        } else {
          await _pumpPublicProfile(
            tester,
            repository: repository,
            settle: false,
          );
        }
        await tester.pump(const Duration(milliseconds: 100));
        expect(repository.queries, hasLength(1));
        expect(
          find.byKey(const Key('user-profile-identity-skeleton')),
          findsOneWidget,
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(self ? MyProfilePage : UserProfilePage)),
        );
        final loadingSemantics = tester.widget<Semantics>(
          find.byKey(const Key('user-profile-identity-skeleton')),
        );
        expect(loadingSemantics.properties.label, l10n.profileLoading);
        expect(loadingSemantics.properties.liveRegion, isTrue);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byKey(const Key('user-profile-name')), findsNothing);
        expect(find.byKey(const Key('user-profile-copy-uid')), findsNothing);
        for (final kind in [
          'settings',
          'sendMessage',
          'addFriend',
          'removeFriend',
        ]) {
          expect(find.byKey(Key('user-profile-action-$kind')), findsNothing);
        }

        final scrollable = _profileScrollable(tester);
        final identityTop = tester
            .getTopLeft(find.byKey(const Key('user-profile-identity')))
            .dy;
        final avatar = tester.getRect(
          find.byKey(const Key('user-profile-avatar-skeleton')),
        );
        if (self) {
          final shortcuts = find.byKey(
            const Key('my-profile-native-shortcuts'),
          );
          expect(shortcuts, findsOneWidget);
          for (final kind in ['threads', 'replies', 'blogs', 'messages']) {
            final action = find.byKey(Key('user-profile-action-$kind'));
            expect(
              find.descendant(of: shortcuts, matching: action),
              findsOneWidget,
            );
            expect(tester.widget<InkWell>(action).onTap, isNotNull);
          }
          tester
              .widget<InkWell>(
                find.byKey(const Key('user-profile-action-threads')),
              )
              .onTap!();
          await tester.pumpAndSettle();
          expect(find.byType(MyThreadPage), findsOneWidget);
          expect(directory.queries.single.userId, '654321');
          Navigator.of(tester.element(find.byType(MyThreadPage))).pop();
          await tester.pump();
          expect(
            find.byKey(const Key('user-profile-identity-skeleton')),
            findsOneWidget,
          );
        } else {
          expect(
            find.byKey(const Key('my-profile-native-shortcuts')),
            findsNothing,
          );
          expect(find.byKey(const Key('user-profile-actions')), findsNothing);
        }

        initialRead.complete(_profileSuccess(profile));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('user-profile-identity-skeleton')),
          findsNothing,
        );
        expect(_profileScrollable(tester), same(scrollable));
        expect(
          tester.getTopLeft(find.byKey(const Key('user-profile-identity'))).dy,
          closeTo(identityTop, 0.01),
        );
        expect(
          tester.getRect(find.byKey(const Key('user-profile-avatar'))),
          avatar,
        );
        expect(find.text(profile.identity.displayName!), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${self ? 'self' : 'public'} refresh keeps identity geometry and scroll position through success and network failure',
      (tester) async {
        final profile = _scrollableProfile(self: self);
        final pendingReads = <Completer<_ProfileReadResult>>[];
        final repository = _ScriptedProfileRepository((_, call) {
          if (call == 0) return Future.value(_profileSuccess(profile));
          final read = Completer<_ProfileReadResult>();
          pendingReads.add(read);
          return read.future;
        });
        if (self) {
          await _pumpMyProfile(tester, repository: repository);
        } else {
          await _pumpPublicProfile(tester, repository: repository);
        }
        final page = find.byType(self ? MyProfilePage : UserProfilePage);
        final container = ProviderScope.containerOf(tester.element(page));
        final l10n = AppLocalizations.of(tester.element(page));
        final scrollable = _profileScrollable(tester);
        expect(scrollable.position.maxScrollExtent, greaterThan(96));
        scrollable.position.jumpTo(96);
        await tester.pump();
        final pixels = scrollable.position.pixels;
        final identity = tester.getRect(
          find.byKey(const Key('user-profile-identity')),
        );
        void expectUnchangedLayout() {
          expect(_profileScrollable(tester), same(scrollable));
          expect(scrollable.position.pixels, closeTo(pixels, 0.01));
          expect(
            tester.getRect(find.byKey(const Key('user-profile-identity'))),
            identity,
          );
          expect(find.text(profile.identity.displayName!), findsOneWidget);
          expect(
            find.byKey(const Key('user-profile-identity-skeleton')),
            findsNothing,
          );
        }

        for (final fails in [false, true]) {
          final refresh = self
              ? container.read(myUserProfileProvider.notifier).refresh()
              : container
                    .read(userProfileProvider('123456').notifier)
                    .refresh();
          await tester.pump();
          expect(
            find.byKey(const Key('user-profile-refresh-progress')),
            findsOneWidget,
          );
          expectUnchangedLayout();
          pendingReads.last.complete(
            fails
                ? const DataReadFailure(
                    kind: DataReadFailureKind.network,
                    diagnosticMessage: 'private diagnostic must not be shown',
                  )
                : _profileSuccess(profile),
          );
          await refresh;
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('user-profile-refresh-progress')),
            findsNothing,
          );
          expectUnchangedLayout();
          if (fails) {
            final error = find.text(
              l10n.profileLoadFailed(l10n.commonNetworkError),
            );
            expect(error, findsOneWidget);
            expect(
              find.text('private diagnostic must not be shown'),
              findsNothing,
            );
            expect(find.byType(SnackBar), findsOneWidget);
            expect(error.hitTestable(), findsOneWidget);
            expectUnchangedLayout();

            await tester.pump(const Duration(seconds: 5));
            await tester.pump(const Duration(milliseconds: 300));
            tester.element(page).markNeedsBuild();
            await tester.pump();
            expect(find.byType(SnackBar), findsNothing);
            expect(error, findsNothing);
            expect(repository.queries, hasLength(3));
            expectUnchangedLayout();
          }
        }
        expect(repository.queries, hasLength(3));
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('UserProfilePage renders source-neutral profile data', (
    tester,
  ) async {
    await _pumpPublicProfile(tester, repository: _FakeProfileRepository());

    expect(find.text('alice的资料'), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsNothing);
    expect(find.byKey(const Key('user-profile-action-settings')), findsNothing);
    expect(find.byKey(const Key('user-profile-metrics')), findsOneWidget);
    expect(find.text('2048'), findsOneWidget);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(UserProfilePage)),
    );
    expect(find.byKey(const Key('user-profile-actions')), findsOneWidget);
    expect(find.text(l10n.profileMyThreadsTab), findsOneWidget);
    expect(find.text(l10n.profileSendMessage), findsOneWidget);
    expect(find.byKey(const Key('user-profile-signature')), findsOneWidget);
    expect(_richTextContaining('Make a deal'), findsOneWidget);
    expect(find.byKey(const Key('user-profile-details')), findsOneWidget);
    expect(find.text('用户组'), findsOneWidget);
    expect(find.text('普通会员'), findsOneWidget);
  });

  testWidgets('public profile opens owner blogs and a direct conversation', (
    tester,
  ) async {
    ForumConversationTarget? opened;
    String? openedTitle;
    final blogRepository = _FakeBlogDirectoryRepository();
    await _pumpPublicProfile(
      tester,
      repository: _FakeProfileRepository(),
      blogRepository: blogRepository,
      conversationRoute: (target, {title = ''}) {
        opened = target;
        openedTitle = title;
        return MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('conversation fixture')),
        );
      },
    );
    final l10n = AppLocalizations.of(
      tester.element(find.byType(UserProfilePage)),
    );
    expect(find.text(l10n.profileSendMessage), findsOneWidget);
    final blogs = find.byKey(const Key('user-profile-action-blogs'));
    await _reveal(tester, blogs);
    await tester.tap(blogs);
    await tester.pumpAndSettle();
    expect(find.byType(ProfileBlogPage), findsOneWidget);
    expect(blogRepository.queries.single.ownerUserId, '123456');
    expect(blogRepository.queries.single.scope, UserBlogFeedScope.self);
    Navigator.of(tester.element(find.byType(ProfileBlogPage))).pop();
    await tester.pumpAndSettle();

    final send = find.byKey(const Key('user-profile-action-sendMessage'));
    await _reveal(tester, send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(opened, const ForumConversationTarget.direct('123456'));
    expect(openedTitle, 'alice');
    expect(find.text('conversation fixture'), findsOneWidget);
  });

  testWidgets('opening the verified viewer UID uses the self profile', (
    tester,
  ) async {
    final repository = _FakeProfileRepository(data: _allActionsProfile);
    await _pumpMyProfile(
      tester,
      repository: repository,
      home: const UserProfilePage(uid: '654321'),
    );
    expect(find.byType(MyProfilePage), findsOneWidget);
    expect(repository.queries.last.view, ForumUserProfileView.self);
    expect(repository.queries.last.viewerUserId, '654321');
    expect(
      find.byKey(const Key('user-profile-action-threads')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('user-profile-action-messages')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('user-profile-action-sendMessage')),
      findsNothing,
    );
  });

  testWidgets('guest profile exposes content and a localized login entry', (
    tester,
  ) async {
    await _pumpPublicProfile(
      tester,
      owner: null,
      repository: _FakeProfileRepository(
        data: const ForumUserProfileData(
          identity: ProfileUserIdentity(userId: '123456', displayName: 'alice'),
          metrics: [],
          details: [],
          actions: [
            ForumUserProfileActionKind.threads,
            ForumUserProfileActionKind.blogs,
            ForumUserProfileActionKind.sendMessage,
          ],
        ),
      ),
    );
    final l10n = AppLocalizations.of(
      tester.element(find.byType(UserProfilePage)),
    );
    expect(
      find.byKey(const Key('user-profile-action-threads')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('user-profile-action-blogs')), findsOneWidget);
    expect(
      find.byKey(const Key('user-profile-action-sendMessage')),
      findsNothing,
    );
    expect(find.text(l10n.profileLoginToInteract), findsOneWidget);
  });

  for (final owner in <VerifiedProfileOwner?>[
    null,
    (uid: '654321', revision: 0),
  ]) {
    testWidgets(
      'public profile omits settings even when advertised for $owner',
      (tester) async {
        await _pumpPublicProfile(
          tester,
          owner: owner,
          repository: _FakeProfileRepository(
            data: ForumUserProfileData(
              identity: const ProfileUserIdentity(userId: '123456'),
              viewerUserId: owner?.uid,
              actions: const [ForumUserProfileActionKind.settings],
              actionLinks: _allActionsProfile.actionLinks
                  .where(
                    (link) => link.kind == ForumUserProfileActionKind.settings,
                  )
                  .toList(),
              metrics: const [],
              details: const [],
            ),
          ),
        );

        expect(
          find.byKey(const Key('user-profile-action-settings')),
          findsNothing,
        );
        expect(find.byIcon(Icons.settings_outlined), findsNothing);
        expect(find.byIcon(Icons.home_outlined), findsNothing);
        expect(find.byKey(const Key('user-profile-open-web')), findsOneWidget);
      },
    );
  }

  testWidgets('UserProfilePage gates optional sections by capability', (
    tester,
  ) async {
    await _pumpPublicProfile(
      tester,
      repository: _FakeProfileRepository(
        capabilities: _profileCapabilities(
          supported: const <ForumUserProfileCapability>[
            ForumUserProfileCapability.stableUserIdentity,
            ForumUserProfileCapability.userName,
          ],
        ),
      ),
    );

    expect(find.byKey(const Key('user-profile-metrics')), findsNothing);
    expect(find.byKey(const Key('user-profile-signature')), findsNothing);
    expect(find.byKey(const Key('user-profile-details')), findsNothing);
    expect(find.text('2048'), findsNothing);
    expect(find.text('普通会员'), findsNothing);
  });

  testWidgets('UserProfilePage avatar uses profile cache ownership', (
    tester,
  ) async {
    await _pumpPublicProfile(
      tester,
      repository: _FakeProfileRepository(
        data: _profileWith(
          avatarUrl:
              'https://bbs.yamibo.com/uc_server/data/avatar/000/12/34/56_avatar_middle.jpg',
        ),
      ),
      imageCacheService: _NoopImageCacheService(),
    );

    final avatarImage = tester
        .widgetList<CachedLibraryImage>(
          find.descendant(
            of: find.byKey(const Key('user-profile-avatar')),
            matching: find.byType(CachedLibraryImage),
          ),
        )
        .singleWhere((image) => image.request != null);
    expect(avatarImage.request?.role, ImageCacheRole.avatar);
    expect(avatarImage.request?.ownerType, ImageCacheOwnerType.profile);
    expect(avatarImage.request?.ownerId, '123456');
  });

  testWidgets(
    'UserProfilePage localizes app chrome and preserves server text',
    (tester) async {
      await _pumpPublicProfile(
        tester,
        repository: _FakeProfileRepository(),
        locale: const Locale('zh', 'TW'),
      );

      expect(find.text('alice 的資料'), findsOneWidget);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(UserProfilePage)),
      );
      expect(find.byKey(const Key('user-profile-actions')), findsOneWidget);
      expect(find.text(l10n.profileMyThreadsTab), findsOneWidget);
      expect(find.text(l10n.profileSendMessage), findsOneWidget);
      expect(find.text('普通会员'), findsOneWidget);
    },
  );

  testWidgets('refresh failure keeps existing profile content', (tester) async {
    final repository = _FakeProfileRepository(failAfterSuccess: true);
    await _pumpPublicProfile(tester, repository: repository);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(UserProfilePage)),
    );

    await container.read(userProfileProvider('123456').notifier).refresh();
    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
    expect(find.textContaining('网络连接失败'), findsOneWidget);
    expect(repository.policies, <CacheLoadPolicy>[
      CacheLoadPolicy.cacheFirst,
      CacheLoadPolicy.networkFirst,
    ]);
  });

  testWidgets('MyProfilePage uses self view and opens structured blog feed', (
    tester,
  ) async {
    final profileRepository = _FakeProfileRepository(data: _myProfile);
    final blogRepository = _FakeBlogDirectoryRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...forumAuthOverrides(const _FakeAuthRepository()),
          forumUserProfileRepositoryProvider.overrideWithValue(
            profileRepository,
          ),
          userBlogDirectoryRepositoryProvider.overrideWithValue(blogRepository),
          forumImageRefererProvider.overrideWithValue(
            'https://bbs.yamibo.com/',
          ),
        ],
        child: const LocalizedTestApp(home: MyProfilePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(profileRepository.queries.single.view, ForumUserProfileView.self);
    expect(profileRepository.queries.single.userId, '654321');
    expect(profileRepository.policies.single, CacheLoadPolicy.networkFirst);
    expect(find.text('我的资料'), findsWidgets);
    expect(find.byKey(const Key('user-profile-actions')), findsOneWidget);
    expect(find.text('我的日志'), findsOneWidget);
    expect(find.text('消息提醒'), findsOneWidget);
    expect(find.text('论坛收藏'), findsNothing);
    expect(find.byKey(const Key('user-profile-action-settings')), findsNothing);
    expect(find.byIcon(Icons.home_outlined), findsNothing);
    expect(find.byKey(const Key('daily-sign-in-panel')), findsNothing);
    expect(
      ProviderScope.containerOf(
        tester.element(find.byType(MyProfilePage)),
      ).exists(dailySignInControllerProvider),
      isFalse,
    );

    await _reveal(tester, find.byKey(const Key('user-profile-action-blogs')));
    await tester.tap(find.text('我的日志'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-blog-list')), findsOneWidget);
    expect(find.text('还没有相关的日志'), findsOneWidget);
    expect(blogRepository.queries.single.scope, UserBlogFeedScope.self);
    expect(blogRepository.queries.single.order, isNull);
  });

  testWidgets('MyProfilePage opens the structured message center', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...forumAuthOverrides(const _FakeAuthRepository()),
          forumUserProfileRepositoryProvider.overrideWithValue(
            _FakeProfileRepository(data: _myProfile),
          ),
          messageRepositoryProvider.overrideWithValue(
            _EmptyMessageRepository(),
          ),
          forumImageRefererProvider.overrideWithValue(
            'https://bbs.yamibo.com/',
          ),
        ],
        child: const LocalizedTestApp(home: MyProfilePage()),
      ),
    );
    await tester.pumpAndSettle();

    await _reveal(
      tester,
      find.byKey(const Key('user-profile-action-messages')),
    );
    await tester.tap(find.text('消息提醒'));
    await tester.pumpAndSettle();

    expect(find.byType(MessageCenterPage), findsOneWidget);
  });

  testWidgets('MyProfilePage hides data as soon as the session is cleared', (
    tester,
  ) async {
    final store = YamiboSessionStore()..saveExtracted(_sessionFor('654321'));
    final opened = <ForumWebViewLaunchConfig>[];
    await _pumpMyProfile(
      tester,
      repository: _FakeProfileRepository(data: _allActionsProfile),
      store: store,
      routeFactory: (config) {
        opened.add(config);
        return MaterialPageRoute<Object?>(builder: (_) => const SizedBox());
      },
    );
    expect(find.text('sample-member'), findsOneWidget);
    final openSettings = tester
        .widget<IconButton>(
          find.byKey(const Key('user-profile-action-settings')),
        )
        .onPressed!;

    store.clear();
    await tester.pumpAndSettle();
    openSettings();
    await tester.pumpAndSettle();

    expect(find.text('sample-member'), findsNothing);
    expect(find.byKey(const Key('user-profile-action-settings')), findsNothing);
    expect(opened, isEmpty);
    expect(find.byKey(const Key('daily-sign-in-panel')), findsNothing);
    expect(find.byKey(const Key('my-profile-open-forum-page')), findsNothing);
    expect(
      find.text(_profileL10n(tester).profileLoginRequired),
      findsOneWidget,
    );
    expect(find.byKey(const Key('user-profile-actions')), findsNothing);
  });

  testWidgets('MyProfilePage does not query a mismatched session owner', (
    tester,
  ) async {
    final store = YamiboSessionStore()..saveExtracted(_sessionFor('777777'));
    final repository = _FakeProfileRepository(data: _allActionsProfile);
    await _pumpMyProfile(tester, repository: repository, store: store);

    expect(
      find.text(_profileL10n(tester).profileLoginRequired),
      findsOneWidget,
    );
    expect(repository.queries, isEmpty);
    expect(find.byKey(const Key('user-profile-action-settings')), findsNothing);
  });

  for (final oldResultFails in [false, true]) {
    testWidgets(
      'MyProfilePage rejects late old-owner ${oldResultFails ? 'network failure' : 'success'}',
      (tester) async {
        final store = YamiboSessionStore()
          ..saveExtracted(_sessionFor('654321'));
        final oldRefresh = Completer<_ProfileReadResult>();
        final repository = _ScriptedProfileRepository((query, call) {
          if (call == 1) return oldRefresh.future;
          return Future.value(
            _profileSuccess(
              query.userId == '654321'
                  ? _myProfile
                  : _selfProfile('777777', 'second-member'),
            ),
          );
        });
        await _pumpMyProfile(tester, repository: repository, store: store);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(MyProfilePage)),
        );
        unawaited(container.read(myUserProfileProvider.notifier).refresh());
        await tester.pump();
        expect(
          find.byKey(const Key('user-profile-refresh-progress')),
          findsOneWidget,
        );

        store.saveExtracted(_sessionFor('777777'));
        container
            .read(authSessionControllerProvider.notifier)
            .acceptSession(
              const ForumSessionIdentity(
                userId: '777777',
                username: 'second-member',
              ),
            );
        await tester.pumpAndSettle();
        expect(find.text('sample-member'), findsNothing);
        expect(find.text('second-member'), findsOneWidget);

        oldRefresh.complete(
          oldResultFails
              ? const DataReadFailure(
                  kind: DataReadFailureKind.network,
                  diagnosticMessage: 'old owner failure',
                )
              : _profileSuccess(_myProfile),
        );
        await tester.pumpAndSettle();
        expect(find.text('second-member'), findsOneWidget);
        expect(find.text('sample-member'), findsNothing);
        expect(
          find.byKey(const Key('my-profile-open-forum-page')),
          findsNothing,
        );
        expect(repository.queries.last.userId, '777777');
        expect(find.byType(SnackBar), findsNothing);
        final l10n = _profileL10n(tester);
        expect(
          find.text(l10n.profileLoadFailed(l10n.commonNetworkError)),
          findsNothing,
        );
      },
    );
  }
  testWidgets('same UID signing in again has a fresh profile owner', (
    tester,
  ) async {
    final store = YamiboSessionStore()..saveExtracted(_sessionFor('654321'));
    final newSession = Completer<_ProfileReadResult>();
    final opened = <ForumWebViewLaunchConfig>[];
    final repository = _ScriptedProfileRepository((query, call) {
      if (call == 0) return Future.value(_profileSuccess(_allActionsProfile));
      return newSession.future;
    });
    await _pumpMyProfile(
      tester,
      repository: repository,
      store: store,
      routeFactory: (config) {
        opened.add(config);
        return MaterialPageRoute<Object?>(builder: (_) => const SizedBox());
      },
    );
    expect(find.text('sample-member'), findsOneWidget);
    final openOldSettings = tester
        .widget<IconButton>(
          find.byKey(const Key('user-profile-action-settings')),
        )
        .onPressed!;

    store.clear();
    store.saveExtracted(_sessionFor('654321'));
    await tester.pump();
    expect(find.text('sample-member'), findsNothing);
    expect(find.byKey(const Key('user-profile-action-settings')), findsNothing);
    expect(
      find.byKey(const Key('user-profile-identity-skeleton')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('user-profile-name')), findsNothing);
    expect(find.byKey(const Key('user-profile-avatar')), findsNothing);
    expect(find.byKey(const Key('user-profile-copy-uid')), findsNothing);
    expect(find.byKey(const Key('user-profile-actions')), findsNothing);

    newSession.complete(_profileSuccess(_selfProfile('654321', 'new-session')));
    await tester.pumpAndSettle();
    openOldSettings();
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(find.text('new-session'), findsOneWidget);
    expect(repository.queries.length, greaterThanOrEqualTo(2));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MyProfilePage)),
    );
    expect(
      container.read(myUserProfileProvider).asData!.value.ownerRevision,
      container.read(verifiedProfileOwnerProvider)!.revision,
    );
    expect(
      repository.cancellations
          .skip(1)
          .take(repository.queries.length - 2)
          .every((cancellation) => cancellation!.isCancelled),
      isTrue,
    );
  });

  testWidgets('MyProfilePage retains content on network refresh failure', (
    tester,
  ) async {
    final repository = _FakeProfileRepository(
      data: _myProfile,
      failAfterSuccess: true,
    );
    await _pumpMyProfile(tester, repository: repository);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MyProfilePage)),
    );
    await container.read(myUserProfileProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(find.text('sample-member'), findsOneWidget);
    expect(find.textContaining('网络连接失败'), findsOneWidget);
    expect(repository.policies, <CacheLoadPolicy>[
      CacheLoadPolicy.networkFirst,
      CacheLoadPolicy.networkFirst,
    ]);
  });

  testWidgets('MyProfilePage clears content on unauthorized refresh', (
    tester,
  ) async {
    final repository = _ScriptedProfileRepository((query, call) async {
      if (call == 0) return _profileSuccess(_myProfile);
      return const DataReadFailure(
        kind: DataReadFailureKind.unauthorized,
        diagnosticMessage: 'auth_required',
      );
    });
    await _pumpMyProfile(tester, repository: repository);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MyProfilePage)),
    );
    await container.read(myUserProfileProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(find.text('sample-member'), findsNothing);
    expect(find.byKey(const Key('user-profile-actions')), findsNothing);
    expect(
      find.text(_profileL10n(tester).profileLoginRequired),
      findsOneWidget,
    );
    expect(find.byKey(const Key('my-profile-open-forum-page')), findsNothing);
  });

  for (final failureKind in <DataReadFailureKind>[
    DataReadFailureKind.parse,
    DataReadFailureKind.unsupported,
  ]) {
    testWidgets('MyProfilePage offers explicit fallback for $failureKind', (
      tester,
    ) async {
      final opened = <ForumWebViewLaunchConfig>[];
      final repository = _ScriptedProfileRepository(
        (query, call) async => DataReadFailure(
          kind: failureKind,
          diagnosticMessage: 'synthetic_profile_failure',
        ),
      );
      await _pumpMyProfile(
        tester,
        repository: repository,
        routeFactory: (config) {
          opened.add(config);
          return MaterialPageRoute<Object?>(
            builder: (_) => const Scaffold(body: Text('managed destination')),
          );
        },
      );

      final fallback = find.byKey(const Key('my-profile-open-forum-page'));
      expect(fallback, findsOneWidget);
      expect(
        find.text(_profileL10n(tester).profileOpenForumPage),
        findsOneWidget,
      );
      expect(opened, isEmpty);

      await tester.tap(fallback);
      await tester.pumpAndSettle();
      expect(opened, hasLength(1));
      expect(opened.single.popOnRootBack, isTrue);
      expect(
        opened.single.initialUri.toString(),
        'https://bbs.yamibo.com/home.php?mod=space&uid=654321&do=profile&mycenter=1&mobile=2',
      );
    });
  }

  for (final failureKind in <DataReadFailureKind>[
    DataReadFailureKind.unauthorized,
    DataReadFailureKind.network,
    DataReadFailureKind.timeout,
  ]) {
    testWidgets('MyProfilePage omits forum fallback for $failureKind', (
      tester,
    ) async {
      await _pumpMyProfile(
        tester,
        repository: _ScriptedProfileRepository(
          (query, call) async => DataReadFailure(
            kind: failureKind,
            diagnosticMessage: 'synthetic_profile_failure',
          ),
        ),
      );

      expect(find.byKey(const Key('my-profile-open-forum-page')), findsNothing);
    });
  }

  testWidgets('MyProfilePage fallback follows only the new verified owner', (
    tester,
  ) async {
    final store = YamiboSessionStore()..saveExtracted(_sessionFor('654321'));
    final oldRefresh = Completer<_ProfileReadResult>();
    final opened = <ForumWebViewLaunchConfig>[];
    final repository = _ScriptedProfileRepository((query, call) {
      if (call == 1) return oldRefresh.future;
      return Future.value(
        const DataReadFailure(
          kind: DataReadFailureKind.parse,
          diagnosticMessage: 'synthetic_profile_failure',
        ),
      );
    });
    await _pumpMyProfile(
      tester,
      repository: repository,
      store: store,
      routeFactory: (config) {
        opened.add(config);
        return MaterialPageRoute<Object?>(
          builder: (_) => const Scaffold(body: Text('managed destination')),
        );
      },
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MyProfilePage)),
    );
    unawaited(container.read(myUserProfileProvider.notifier).refresh());
    await tester.pump();

    store.saveExtracted(_sessionFor('777777'));
    container
        .read(authSessionControllerProvider.notifier)
        .acceptSession(
          const ForumSessionIdentity(
            userId: '777777',
            username: 'second-member',
          ),
        );
    await tester.pumpAndSettle();
    expect(repository.queries.last.userId, '777777');

    oldRefresh.complete(
      const DataReadFailure(
        kind: DataReadFailureKind.parse,
        diagnosticMessage: 'old_owner_failure',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('my-profile-open-forum-page')), findsOneWidget);
    await tester.tap(find.byKey(const Key('my-profile-open-forum-page')));
    await tester.pumpAndSettle();

    expect(opened.single.initialUri.queryParameters['uid'], '777777');
  });

  testWidgets('MyProfilePage fallback fits 300dp with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...forumAuthOverrides(const _FakeAuthRepository()),
          forumUserProfileRepositoryProvider.overrideWithValue(
            _ScriptedProfileRepository(
              (query, call) async => const DataReadFailure(
                kind: DataReadFailureKind.parse,
                diagnosticMessage: 'synthetic_profile_failure',
              ),
            ),
          ),
          forumImageRefererProvider.overrideWithValue(
            'https://bbs.yamibo.com/',
          ),
        ],
        child: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: LocalizedTestApp(home: MyProfilePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('my-profile-open-forum-page')), findsOneWidget);
  });

  testWidgets('MyProfilePage can retry an unexpected initial read failure', (
    tester,
  ) async {
    final repository = _ScriptedProfileRepository((query, call) async {
      if (call == 0) throw StateError('synthetic failure');
      return _profileSuccess(_myProfile);
    });
    await _pumpMyProfile(tester, repository: repository);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('sample-member'), findsNothing);
    expect(find.byKey(const Key('daily-sign-in-panel')), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MyProfilePage)),
    );
    expect(container.exists(dailySignInControllerProvider), isFalse);

    await tester.tap(find.text(_profileL10n(tester).commonRetry));
    await tester.pumpAndSettle();

    expect(find.text('sample-member'), findsOneWidget);
    expect(repository.queries.length, 2);
    expect(find.byKey(const Key('daily-sign-in-panel')), findsNothing);
    expect(container.exists(dailySignInControllerProvider), isFalse);
  });

  testWidgets('MyProfilePage shows an empty hint for UID-only details', (
    tester,
  ) async {
    await _pumpMyProfile(
      tester,
      repository: _FakeProfileRepository(
        data: const ForumUserProfileData(
          identity: ProfileUserIdentity(userId: '654321'),
          metrics: <ForumUserProfileMetric>[],
          details: <ForumUserProfileDetail>[
            ForumUserProfileDetail(label: 'UID', value: '654321'),
          ],
        ),
      ),
    );

    expect(
      find.text(_profileL10n(tester).profileNoAdditionalDetails),
      findsOneWidget,
    );
    expect(find.byKey(const Key('user-profile-actions')), findsNothing);
  });

  testWidgets('MyProfilePage opens its native topic directory', (tester) async {
    final directory = _ProfileThreadDirectoryRepository();
    await _pumpMyProfile(
      tester,
      repository: _FakeProfileRepository(data: _allActionsProfile),
      threadDirectory: directory,
    );
    final entry = find.byKey(const Key('user-profile-action-threads'));
    await _reveal(tester, entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(MyThreadPage), findsOneWidget);
    expect(directory.queries.single.userId, '654321');
    expect(directory.queries.single.type, UserThreadDirectoryType.threads);
  });

  for (final locale in [const Locale('zh'), const Locale('zh', 'TW')]) {
    testWidgets(
      'MyProfilePage labels and opens the self friends action for $locale',
      (tester) async {
        final directory = FriendFeedFixture(autoComplete: true);
        await _pumpMyProfile(
          tester,
          repository: _FakeProfileRepository(data: _allActionsProfile),
          friendDirectory: directory,
          locale: locale,
        );
        expect(directory.requests, isEmpty);
        final entry = find.byKey(const Key('user-profile-action-friends'));
        await _reveal(tester, entry);
        final l10n = _profileL10n(tester);
        expect(
          find.descendant(
            of: entry,
            matching: find.text(l10n.profileMyFriendsTitle),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: entry, matching: find.text(l10n.profileFriends)),
          findsNothing,
        );
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.byType(MyFriendsPage), findsOneWidget);
        expect(directory.requests.single.query.accountUserId, '654321');
        expect(
          directory.requests.single.query.scope,
          ForumFriendFeedScope.friends,
        );
        expect(
          find.byType(ForumWebViewPage, skipOffstage: false),
          findsNothing,
        );
        Navigator.of(tester.element(find.byType(MyFriendsPage))).pop();
        await tester.pumpAndSettle();
        expect(find.byType(MyProfilePage), findsOneWidget);
        expect(directory.requests, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('MyProfilePage opens advertised managed WebView action targets', (
    tester,
  ) async {
    final opened = <ForumWebViewLaunchConfig>[];
    final repository = _FakeProfileRepository(data: _allActionsProfile);
    await _pumpMyProfile(
      tester,
      repository: repository,
      routeFactory: (config) {
        opened.add(config);
        return MaterialPageRoute<Object?>(
          builder: (_) => Scaffold(
            appBar: AppBar(),
            body: const Text('managed destination'),
          ),
        );
      },
    );

    final settings = find.byKey(const Key('user-profile-action-settings'));
    expect(settings, findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: settings),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('user-profile-page-list')),
        matching: settings,
      ),
      findsNothing,
    );
    expect(
      tester.widget<IconButton>(settings).tooltip,
      _profileL10n(tester).profileSettings,
    );
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsNothing);
    expect(find.byKey(const Key('user-profile-open-web')), findsOneWidget);

    const targets = <ForumUserProfileActionKind>[
      ForumUserProfileActionKind.forumFavorites,
      ForumUserProfileActionKind.settings,
      ForumUserProfileActionKind.creditHistory,
    ];
    for (final kind in targets) {
      await _reveal(
        tester,
        find.byKey(Key('user-profile-action-${kind.name}')),
      );
      await tester.tap(find.byKey(Key('user-profile-action-${kind.name}')));
      await tester.pumpAndSettle();
      expect(opened.last.initialUri.host, 'bbs.yamibo.com');
      expect(opened.last.initialUri.path, '/home.php');
      expect(
        opened.last.initialUri,
        _allActionsProfile.actionLinks
            .singleWhere((link) => link.kind == kind)
            .uri,
      );
      expect(opened.last.popOnRootBack, isTrue);
      expect(opened.last.expectedAccountId, '654321');
      expect(
        opened.last.initialUri.queryParameters['uid'],
        kind == ForumUserProfileActionKind.forumFavorites ? '654321' : null,
      );
      Navigator.of(tester.element(find.text('managed destination'))).pop();
      await tester.pumpAndSettle();
    }
    expect(
      opened.map((config) => config.initialUri.queryParameters),
      <Map<String, String>>[
        {
          'mod': 'space',
          'uid': '654321',
          'do': 'favorite',
          'view': 'me',
          'type': 'thread',
        },
        {'mod': 'spacecp', 'ac': 'profile'},
        {'mod': 'spacecp', 'ac': 'credit', 'op': 'log'},
      ],
    );
    expect(repository.queries, hasLength(targets.length + 1));
    expect(
      repository.policies.every(
        (policy) => policy == CacheLoadPolicy.networkFirst,
      ),
      isTrue,
    );
  });

  testWidgets('MyProfilePage hides actions without the actions capability', (
    tester,
  ) async {
    await _pumpMyProfile(
      tester,
      repository: _FakeProfileRepository(
        data: _allActionsProfile,
        capabilities: _profileCapabilities(
          supported: ForumUserProfileCapability.values.where(
            (capability) =>
                capability != ForumUserProfileCapability.orderedActions,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('user-profile-actions')), findsNothing);
    expect(find.byKey(const Key('user-profile-action-settings')), findsNothing);
    expect(find.byIcon(Icons.settings_outlined), findsNothing);
  });

  testWidgets('MyProfilePage actions fit 300dp at enlarged text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...forumAuthOverrides(const _FakeAuthRepository()),
          forumUserProfileRepositoryProvider.overrideWithValue(
            _FakeProfileRepository(data: _allActionsProfile),
          ),
          forumImageRefererProvider.overrideWithValue(
            'https://bbs.yamibo.com/',
          ),
        ],
        child: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: LocalizedTestApp(home: MyProfilePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _reveal(
      tester,
      find.byKey(const Key('user-profile-action-creditHistory')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('user-profile-actions')), findsOneWidget);
  });

  testWidgets('profile layout remains usable at 300dp with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(300, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          verifiedProfileOwnerProvider.overrideWithValue((
            uid: '654321',
            revision: 0,
          )),
          forumUserProfileRepositoryProvider.overrideWithValue(
            _FakeProfileRepository(),
          ),
          forumImageRefererProvider.overrideWithValue(
            'https://bbs.yamibo.com/',
          ),
        ],
        child: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: LocalizedTestApp(home: UserProfilePage(uid: '123456')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('user-profile-page-list')), findsOneWidget);
  });
}

class _EmptyMessageRepository extends MessageTestRepository {
  @override
  Future<PrivateMessageRead> loadMessages(
    ForumPrivateMessageQuery query,
  ) async => messageTestPage([], owner: '654321');
}

Future<void> _pumpPublicProfile(
  WidgetTester tester, {
  required ForumUserProfileRepository repository,
  Locale locale = const Locale('zh'),
  ImageCacheService? imageCacheService,
  PrivateConversationRouteFactory? conversationRoute,
  UserBlogDirectoryRepository? blogRepository,
  VerifiedProfileOwner? owner = (uid: '654321', revision: 0),
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        verifiedProfileOwnerProvider.overrideWithValue(owner),
        forumUserProfileRepositoryProvider.overrideWithValue(repository),
        if (blogRepository != null) ...[
          userBlogDirectoryRepositoryProvider.overrideWithValue(blogRepository),
          blogAccountIdProvider.overrideWithValue(null),
        ],
        if (conversationRoute != null)
          privateConversationRouteFactoryProvider.overrideWithValue(
            conversationRoute,
          ),
        forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
        if (imageCacheService != null)
          imageCacheServiceProvider.overrideWithValue(imageCacheService),
      ],
      child: LocalizedTestApp(
        locale: locale,
        home: const UserProfilePage(uid: '123456'),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
}

Future<void> _pumpMyProfile(
  WidgetTester tester, {
  required ForumUserProfileRepository repository,
  Locale locale = const Locale('zh'),
  YamiboSessionStore? store,
  ForumWebViewRouteFactory? routeFactory,
  UserThreadDirectoryRepository? threadDirectory,
  ForumFriendFeedRepository? friendDirectory,
  Widget? home,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...forumAuthOverrides(const _FakeAuthRepository()),
        forumUserProfileRepositoryProvider.overrideWithValue(repository),
        if (threadDirectory != null)
          userThreadDirectoryRepositoryProvider.overrideWithValue(
            threadDirectory,
          ),
        if (friendDirectory != null) ...[
          friendFeedRepositoryProvider.overrideWithValue(friendDirectory),
          friendRemovalCommandProvider.overrideWithValue(
            FriendRemovalFixture(),
          ),
        ],
        if (store != null) yamiboSessionStoreProvider.overrideWithValue(store),
        if (routeFactory != null)
          forumWebViewRouteFactoryProvider.overrideWithValue(routeFactory),
        forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
      ],
      child: LocalizedTestApp(
        locale: locale,
        home: home ?? const MyProfilePage(),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
}

ScrollableState _profileScrollable(WidgetTester tester) =>
    tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('user-profile-page-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );

ForumUserProfileData _scrollableProfile({required bool self}) {
  final source = self ? _myProfile : _profile;
  return ForumUserProfileData(
    identity: source.identity,
    viewerUserId: source.viewerUserId,
    actions: source.actions,
    signatureHtml: _profile.signatureHtml,
    metrics: source.metrics,
    details: [
      ...source.details,
      for (var index = 0; index < 20; index++)
        ForumUserProfileDetail(label: 'Field $index', value: 'Value $index'),
    ],
  );
}

AppLocalizations _profileL10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(MyProfilePage)));

YamiboSessionSnapshot _sessionFor(String uid) => YamiboSessionSnapshot(
  isLoggedIn: true,
  uid: uid,
  username: 'sample-member',
  formhash: '',
  updatedAt: DateTime(2026, 1, 1),
  source: 'test',
);

typedef _ProfileReadResult =
    DataReadResult<ForumUserProfileData, ForumUserProfileReadCapabilities>;

_ProfileReadResult _profileSuccess(ForumUserProfileData data) =>
    DataReadSuccess(
      data: data,
      capabilities: _profileCapabilities(),
      metadata: const DataReadMetadata.network(),
    );

ForumUserProfileData _selfProfile(String uid, String name) =>
    ForumUserProfileData(
      identity: ProfileUserIdentity(userId: uid, displayName: name),
      metrics: const <ForumUserProfileMetric>[],
      details: <ForumUserProfileDetail>[
        ForumUserProfileDetail(label: 'UID', value: uid),
      ],
    );

class _ScriptedProfileRepository implements ForumUserProfileRepository {
  _ScriptedProfileRepository(this.onLoad);

  final Future<_ProfileReadResult> Function(ForumUserProfileQuery, int) onLoad;
  final queries = <ForumUserProfileQuery>[];
  final policies = <CacheLoadPolicy>[];
  final cancellations = <ForumRequestCancellation?>[];

  @override
  ForumUserProfileSourceCapabilities get capabilities =>
      ForumUserProfileSourceCapabilities(values: _profileCapabilities().values);

  @override
  Future<_ProfileReadResult> load(
    ForumUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) {
    final call = queries.length;
    queries.add(query);
    policies.add(cachePolicy);
    cancellations.add(cancellation);
    return onLoad(query, call);
  }
}

class _ProfileThreadDirectoryRepository extends Fake
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
    return const DataReadFailure(
      kind: DataReadFailureKind.parse,
      code: 'fixture_unavailable',
      diagnosticMessage: 'fixture_unavailable',
    );
  }
}

const _profile = ForumUserProfileData(
  identity: ProfileUserIdentity(userId: '123456', displayName: 'alice'),
  viewerUserId: '654321',
  actions: [
    ForumUserProfileActionKind.threads,
    ForumUserProfileActionKind.blogs,
    ForumUserProfileActionKind.sendMessage,
  ],
  signatureHtml: '<p>Make a deal with god</p>',
  metrics: <ForumUserProfileMetric>[
    ForumUserProfileMetric(label: '总积分', value: '2048'),
    ForumUserProfileMetric(label: '积分', value: '1800 点'),
    ForumUserProfileMetric(label: '对象', value: '333'),
  ],
  details: <ForumUserProfileDetail>[
    ForumUserProfileDetail(label: 'UID', value: '123456'),
    ForumUserProfileDetail(label: '用户组', value: '普通会员'),
  ],
);

const _myProfile = ForumUserProfileData(
  identity: ProfileUserIdentity(userId: '654321', displayName: 'sample-member'),
  actions: <ForumUserProfileActionKind>[
    ForumUserProfileActionKind.blogs,
    ForumUserProfileActionKind.messages,
  ],
  metrics: <ForumUserProfileMetric>[
    ForumUserProfileMetric(label: '总积分', value: '65'),
    ForumUserProfileMetric(label: '积分', value: '7 点'),
    ForumUserProfileMetric(label: '对象', value: '175'),
  ],
  details: <ForumUserProfileDetail>[
    ForumUserProfileDetail(label: 'UID', value: '654321'),
    ForumUserProfileDetail(label: '用户组', value: '普通会员'),
  ],
);

final _allActionsProfile = ForumUserProfileData(
  identity: const ProfileUserIdentity(
    userId: '654321',
    displayName: 'sample-member',
  ),
  metrics: const <ForumUserProfileMetric>[],
  details: const <ForumUserProfileDetail>[
    ForumUserProfileDetail(label: 'UID', value: '654321'),
  ],
  actions: const [
    ForumUserProfileActionKind.threads,
    ForumUserProfileActionKind.blogs,
    ForumUserProfileActionKind.forumFavorites,
    ForumUserProfileActionKind.messages,
    ForumUserProfileActionKind.friends,
    ForumUserProfileActionKind.settings,
    ForumUserProfileActionKind.creditHistory,
  ],
  actionLinks: [
    ForumUserProfileActionLink(
      kind: ForumUserProfileActionKind.forumFavorites,
      uri: Uri.parse(
        'https://bbs.yamibo.com/home.php?mod=space&uid=654321&do=favorite&view=me&type=thread',
      ),
    ),
    ForumUserProfileActionLink(
      kind: ForumUserProfileActionKind.friends,
      uri: Uri.parse('https://bbs.yamibo.com/home.php?mod=space&do=friend'),
    ),
    ForumUserProfileActionLink(
      kind: ForumUserProfileActionKind.settings,
      uri: Uri.parse('https://bbs.yamibo.com/home.php?mod=spacecp&ac=profile'),
    ),
    ForumUserProfileActionLink(
      kind: ForumUserProfileActionKind.creditHistory,
      uri: Uri.parse(
        'https://bbs.yamibo.com/home.php?mod=spacecp&ac=credit&op=log',
      ),
    ),
  ],
);

ForumUserProfileData _profileWith({String? avatarUrl}) {
  return ForumUserProfileData(
    identity: _profile.identity,
    avatarUrl: avatarUrl,
    viewerUserId: _profile.viewerUserId,
    actions: _profile.actions,
    signatureHtml: _profile.signatureHtml,
    metrics: _profile.metrics,
    details: _profile.details,
  );
}

ForumUserProfileReadCapabilities _profileCapabilities({
  Iterable<ForumUserProfileCapability> supported =
      ForumUserProfileCapability.values,
}) {
  return ForumUserProfileReadCapabilities(
    values: DataCapabilitySet<ForumUserProfileCapability>.from(
      supported: supported,
      unsupported: ForumUserProfileCapability.values.where(
        (value) => !supported.contains(value),
      ),
    ),
  );
}

class _FakeProfileRepository implements ForumUserProfileRepository {
  _FakeProfileRepository({
    this.data = _profile,
    ForumUserProfileReadCapabilities? capabilities,
    this.failAfterSuccess = false,
  }) : readCapabilities = capabilities ?? _profileCapabilities();

  final ForumUserProfileData data;
  final ForumUserProfileReadCapabilities readCapabilities;
  final bool failAfterSuccess;
  final List<ForumUserProfileQuery> queries = <ForumUserProfileQuery>[];
  final List<CacheLoadPolicy> policies = <CacheLoadPolicy>[];

  @override
  ForumUserProfileSourceCapabilities get capabilities =>
      ForumUserProfileSourceCapabilities(values: readCapabilities.values);

  @override
  Future<DataReadResult<ForumUserProfileData, ForumUserProfileReadCapabilities>>
  load(
    ForumUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) async {
    queries.add(query);
    policies.add(cachePolicy);
    if (failAfterSuccess && queries.length > 1) {
      return const DataReadFailure(
        kind: DataReadFailureKind.network,
        diagnosticMessage: 'network failure',
      );
    }
    return DataReadSuccess(
      data: data,
      capabilities: readCapabilities,
      metadata: const DataReadMetadata.network(),
    );
  }
}

class _FakeBlogDirectoryRepository implements UserBlogDirectoryRepository {
  final List<UserBlogDirectoryQuery> queries = <UserBlogDirectoryQuery>[];

  @override
  UserBlogDirectorySourceCapabilities get capabilities =>
      UserBlogDirectorySourceCapabilities(
        values: DataCapabilitySet<UserBlogDirectoryCapability>.supported(
          UserBlogDirectoryCapability.values,
        ),
        paginationPrecision: PaginationPrecision.unknown,
      );

  @override
  Future<
    DataReadResult<UserBlogDirectoryData, UserBlogDirectoryReadCapabilities>
  >
  load(
    UserBlogDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  }) async {
    queries.add(query);
    return DataReadSuccess(
      data: UserBlogDirectoryData(
        scope: query.scope,
        order: query.order,
        items: const <UserBlogSummary>[],
        pagination: UserBlogPagination(currentPage: query.page),
      ),
      capabilities: UserBlogDirectoryReadCapabilities(
        values: DataCapabilitySet<UserBlogDirectoryCapability>.supported(
          UserBlogDirectoryCapability.values,
        ),
        paginationPrecision: PaginationPrecision.unknown,
      ),
      metadata: const DataReadMetadata.network(),
    );
  }
}

class _NoopImageCacheService implements ImageCacheService {
  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult.failed;
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
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> clearUnprotected() async {}

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    return 0;
  }

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async {
    return 0;
  }

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}
}

class _FakeAuthRepository implements AuthRepository {
  const _FakeAuthRepository();

  @override
  Future<ApiResult<SessionInfo>> refreshSession() async => const ApiSuccess(
    SessionInfo(
      uid: '654321',
      username: 'sample-member',
      formhash: 'fh',
      isLoggedIn: true,
    ),
  );

  @override
  Future<ApiResult<bool>> verifyAuthByForumIndex() async =>
      const ApiSuccess<bool>(true);

  @override
  Future<ApiResult<SessionInfo>> login({
    required String username,
    required String password,
    String questionId = '0',
    String answer = '',
  }) async {
    return refreshSession();
  }

  @override
  Future<void> logout() async {}
}

Finder _richTextContaining(String text) {
  return find.byWidgetPredicate((widget) {
    return widget is RichText && widget.text.toPlainText().contains(text);
  });
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
}

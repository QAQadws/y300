import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo/yamibo_session_snapshot.dart';
import 'package:y300/core/network/yamibo/yamibo_session_store.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/auth/presentation/auth_session_controller.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/profile/data/models/my_message_models.dart';
import 'package:y300/features/profile/data/providers/daily_sign_in_providers.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/data/repositories/my_message_repository.dart';
import 'package:y300/features/profile/presentation/my_message_center_page.dart';
import 'package:y300/features/profile/presentation/user_profile_page.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_driver.dart';
import 'package:y300/features/forum/presentation/webview/forum_webview_route_factory.dart';
import 'package:y300/l10n/app_localizations.dart';

import '../../../support/forum_auth_test_support.dart';
import '../../../test_support/localized_test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('UserProfilePage renders source-neutral profile data', (
    tester,
  ) async {
    await _pumpPublicProfile(tester, repository: _FakeProfileRepository());

    expect(find.text('alice的资料'), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);
    expect(find.byKey(const Key('user-profile-metrics')), findsOneWidget);
    expect(find.text('2048'), findsOneWidget);
    expect(find.byKey(const Key('user-profile-actions')), findsNothing);
    expect(find.text('Ta的主题'), findsNothing);
    expect(find.text('发短消息'), findsNothing);
    expect(find.byKey(const Key('user-profile-signature')), findsOneWidget);
    expect(_richTextContaining('Make a deal'), findsOneWidget);
    expect(find.byKey(const Key('user-profile-details')), findsOneWidget);
    expect(find.text('用户组'), findsOneWidget);
    expect(find.text('普通会员'), findsOneWidget);
  });

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

    final avatarImage = tester.widget<CachedLibraryImage>(
      find.descendant(
        of: find.byKey(const Key('user-profile-avatar')),
        matching: find.byType(CachedLibraryImage),
      ),
    );
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
      expect(find.byKey(const Key('user-profile-actions')), findsNothing);
      expect(find.text('Ta 的主題'), findsNothing);
      expect(find.text('傳送短訊息'), findsNothing);
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
          dailySignInRepositoryProvider.overrideWithValue(
            _FakeSignRepository(),
          ),
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
    expect(find.text('每日签到'), findsOneWidget);

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
          dailySignInRepositoryProvider.overrideWithValue(
            _FakeSignRepository(),
          ),
          forumUserProfileRepositoryProvider.overrideWithValue(
            _FakeProfileRepository(data: _myProfile),
          ),
          myMessageRepositoryProvider.overrideWithValue(
            const _EmptyMyMessageRepository(),
          ),
          forumImageRefererProvider.overrideWithValue(
            'https://bbs.yamibo.com/',
          ),
        ],
        child: const LocalizedTestApp(home: MyProfilePage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('消息提醒'));
    await tester.tap(find.text('消息提醒'));
    await tester.pumpAndSettle();

    expect(find.byType(MyMessageCenterPage), findsOneWidget);
  });

  testWidgets('MyProfilePage hides data as soon as the session is cleared', (
    tester,
  ) async {
    final store = YamiboSessionStore()..saveExtracted(_sessionFor('654321'));
    await _pumpMyProfile(
      tester,
      repository: _FakeProfileRepository(data: _myProfile),
      store: store,
    );
    expect(find.text('sample-member'), findsOneWidget);

    store.clear();
    await tester.pumpAndSettle();

    expect(find.text('sample-member'), findsNothing);
    expect(find.byKey(const Key('daily-sign-in-panel')), findsNothing);
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
    final repository = _FakeProfileRepository(data: _myProfile);
    await _pumpMyProfile(tester, repository: repository, store: store);

    expect(
      find.text(_profileL10n(tester).profileLoginRequired),
      findsOneWidget,
    );
    expect(repository.queries, isEmpty);
  });

  testWidgets('MyProfilePage rejects a late refresh from the old owner', (
    tester,
  ) async {
    final store = YamiboSessionStore()..saveExtracted(_sessionFor('654321'));
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

    oldRefresh.complete(_profileSuccess(_myProfile));
    await tester.pumpAndSettle();
    expect(find.text('second-member'), findsOneWidget);
    expect(find.text('sample-member'), findsNothing);
    expect(repository.queries.last.userId, '777777');
  });

  testWidgets('same UID signing in again has a fresh profile owner', (
    tester,
  ) async {
    final store = YamiboSessionStore()..saveExtracted(_sessionFor('654321'));
    final newSession = Completer<_ProfileReadResult>();
    final repository = _ScriptedProfileRepository((query, call) {
      if (call == 0) return Future.value(_profileSuccess(_myProfile));
      return newSession.future;
    });
    await _pumpMyProfile(tester, repository: repository, store: store);
    expect(find.text('sample-member'), findsOneWidget);

    store.clear();
    store.saveExtracted(_sessionFor('654321'));
    await tester.pump();
    expect(find.text('sample-member'), findsNothing);

    newSession.complete(_profileSuccess(_selfProfile('654321', 'new-session')));
    await tester.pumpAndSettle();
    expect(find.text('new-session'), findsOneWidget);
    expect(repository.queries.length, 2);
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
  });

  testWidgets('MyProfilePage can retry an unexpected initial read failure', (
    tester,
  ) async {
    final repository = _ScriptedProfileRepository((query, call) async {
      if (call == 0) throw StateError('synthetic failure');
      return _profileSuccess(_myProfile);
    });
    await _pumpMyProfile(tester, repository: repository);
    expect(find.text('sample-member'), findsNothing);
    expect(find.byKey(const Key('daily-sign-in-panel')), findsOneWidget);
    expect(find.text(_profileL10n(tester).dailySignInSigned), findsOneWidget);

    await tester.tap(find.text(_profileL10n(tester).commonRetry));
    await tester.pumpAndSettle();

    expect(find.text('sample-member'), findsOneWidget);
    expect(repository.queries.length, 2);
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

  testWidgets('MyProfilePage opens fixed managed WebView action targets', (
    tester,
  ) async {
    final opened = <ForumWebViewLaunchConfig>[];
    await _pumpMyProfile(
      tester,
      repository: _FakeProfileRepository(data: _allActionsProfile),
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

    const targets = <ForumUserProfileActionKind>[
      ForumUserProfileActionKind.threads,
      ForumUserProfileActionKind.forumFavorites,
      ForumUserProfileActionKind.friends,
      ForumUserProfileActionKind.settings,
      ForumUserProfileActionKind.creditHistory,
    ];
    for (final kind in targets) {
      await tester.ensureVisible(
        find.byKey(Key('user-profile-action-${kind.name}')),
      );
      await tester.tap(find.byKey(Key('user-profile-action-${kind.name}')));
      await tester.pumpAndSettle();
      expect(opened.last.initialUri.host, 'bbs.yamibo.com');
      expect(opened.last.initialUri.path, '/home.php');
      expect(opened.last.popOnRootBack, isTrue);
      expect(
        opened.last.initialUri.queryParameters['uid'],
        kind == ForumUserProfileActionKind.threads ||
                kind == ForumUserProfileActionKind.forumFavorites
            ? '654321'
            : null,
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
          'do': 'thread',
          'view': 'me',
          'mobile': '2',
        },
        {
          'mod': 'space',
          'uid': '654321',
          'do': 'favorite',
          'view': 'me',
          'type': 'thread',
          'mobile': '2',
        },
        {'mod': 'space', 'do': 'friend', 'mobile': '2'},
        {'mod': 'spacecp', 'mobile': '2'},
        {'mod': 'spacecp', 'ac': 'credit', 'op': 'log'},
      ],
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
          dailySignInRepositoryProvider.overrideWithValue(
            _FakeSignRepository(),
          ),
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
    await tester.ensureVisible(
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

class _EmptyMyMessageRepository implements MyMessageRepository {
  const _EmptyMyMessageRepository();

  @override
  Future<ApiResult<MyMessageCenterData>> getMessageCenter() async {
    return ApiSuccess<MyMessageCenterData>(
      MyMessageCenterData(
        notifications: (await getNotifications()).dataOrNull!,
        privateMessages: (await getPrivateMessages()).dataOrNull!,
      ),
    );
  }

  @override
  Future<ApiResult<MyNotificationPage>> getNotifications() async {
    return const ApiSuccess<MyNotificationPage>(
      MyNotificationPage(
        count: 0,
        page: 1,
        perPage: 30,
        items: <MyNotificationItem>[],
      ),
    );
  }

  @override
  Future<ApiResult<MyPrivateMessagePage>> getPrivateMessages() async {
    return const ApiSuccess<MyPrivateMessagePage>(
      MyPrivateMessagePage(
        count: 0,
        page: 1,
        perPage: 30,
        items: <MyPrivateMessageItem>[],
      ),
    );
  }
}

Future<void> _pumpPublicProfile(
  WidgetTester tester, {
  required ForumUserProfileRepository repository,
  Locale locale = const Locale('zh'),
  ImageCacheService? imageCacheService,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        forumUserProfileRepositoryProvider.overrideWithValue(repository),
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
  await tester.pumpAndSettle();
}

Future<void> _pumpMyProfile(
  WidgetTester tester, {
  required ForumUserProfileRepository repository,
  YamiboSessionStore? store,
  ForumWebViewRouteFactory? routeFactory,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...forumAuthOverrides(const _FakeAuthRepository()),
        dailySignInRepositoryProvider.overrideWithValue(_FakeSignRepository()),
        forumUserProfileRepositoryProvider.overrideWithValue(repository),
        if (store != null) yamiboSessionStoreProvider.overrideWithValue(store),
        if (routeFactory != null)
          forumWebViewRouteFactoryProvider.overrideWithValue(routeFactory),
        forumImageRefererProvider.overrideWithValue('https://bbs.yamibo.com/'),
      ],
      child: const LocalizedTestApp(home: MyProfilePage()),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeSignRepository implements ForumDailySignInRepository {
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
  load(ForumDailySignInQuery query) async => DataReadSuccess(
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

  @override
  ForumUserProfileSourceCapabilities get capabilities =>
      ForumUserProfileSourceCapabilities(values: _profileCapabilities().values);

  @override
  Future<_ProfileReadResult> load(
    ForumUserProfileQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) {
    final call = queries.length;
    queries.add(query);
    policies.add(cachePolicy);
    return onLoad(query, call);
  }
}

const _profile = ForumUserProfileData(
  identity: ProfileUserIdentity(userId: '123456', displayName: 'alice'),
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

const _allActionsProfile = ForumUserProfileData(
  identity: ProfileUserIdentity(userId: '654321', displayName: 'sample-member'),
  metrics: <ForumUserProfileMetric>[],
  details: <ForumUserProfileDetail>[
    ForumUserProfileDetail(label: 'UID', value: '654321'),
  ],
  actions: ForumUserProfileActionKind.values,
);

ForumUserProfileData _profileWith({String? avatarUrl}) {
  return ForumUserProfileData(
    identity: _profile.identity,
    avatarUrl: avatarUrl,
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

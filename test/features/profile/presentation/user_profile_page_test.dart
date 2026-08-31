import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/profile/data/models/my_message_models.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/data/repositories/my_message_repository.dart';
import 'package:y300/features/profile/presentation/my_message_center_page.dart';
import 'package:y300/features/profile/presentation/user_profile_page.dart';

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
    expect(find.text('5263'), findsOneWidget);
    expect(find.byKey(const Key('user-profile-actions')), findsNothing);
    expect(find.text('Ta的主题'), findsNothing);
    expect(find.text('发短消息'), findsNothing);
    expect(find.byKey(const Key('user-profile-signature')), findsOneWidget);
    expect(_richTextContaining('Make a deal'), findsOneWidget);
    expect(find.byKey(const Key('user-profile-details')), findsOneWidget);
    expect(find.text('用户组'), findsOneWidget);
    expect(find.text('百合達人'), findsOneWidget);
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
    expect(find.text('5263'), findsNothing);
    expect(find.text('百合達人'), findsNothing);
  });

  testWidgets('UserProfilePage avatar uses profile cache ownership', (
    tester,
  ) async {
    await _pumpPublicProfile(
      tester,
      repository: _FakeProfileRepository(
        data: _profileWith(
          avatarUrl:
              'https://bbs.yamibo.com/uc_server/data/avatar/000/50/99/57_avatar_middle.jpg',
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
    expect(avatarImage.request?.ownerId, '509957');
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
      expect(find.text('百合達人'), findsOneWidget);
    },
  );

  testWidgets('refresh failure keeps existing profile content', (tester) async {
    final repository = _FakeProfileRepository(failAfterSuccess: true);
    await _pumpPublicProfile(tester, repository: repository);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(UserProfilePage)),
    );

    await container.read(userProfileProvider('509957').notifier).refresh();
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
    expect(find.text('我的资料'), findsWidgets);
    expect(find.byKey(const Key('user-profile-actions')), findsOneWidget);
    expect(find.text('我的日志'), findsOneWidget);
    expect(find.text('消息提醒'), findsOneWidget);
    expect(find.text('我的收藏'), findsNothing);
    expect(find.text('每日签到'), findsNothing);

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
        child: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: const LocalizedTestApp(home: UserProfilePage(uid: '509957')),
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
        home: const UserProfilePage(uid: '509957'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _profile = ForumUserProfileData(
  identity: ProfileUserIdentity(userId: '509957', displayName: 'alice'),
  signatureHtml: '<p>Make a deal with god</p>',
  metrics: <ForumUserProfileMetric>[
    ForumUserProfileMetric(label: '总积分', value: '5263'),
    ForumUserProfileMetric(label: '积分', value: '4300 点'),
    ForumUserProfileMetric(label: '对象', value: '2888'),
  ],
  details: <ForumUserProfileDetail>[
    ForumUserProfileDetail(label: 'UID', value: '509957'),
    ForumUserProfileDetail(label: '用户组', value: '百合達人'),
  ],
);

const _myProfile = ForumUserProfileData(
  identity: ProfileUserIdentity(userId: '597454', displayName: '2834758851'),
  metrics: <ForumUserProfileMetric>[
    ForumUserProfileMetric(label: '总积分', value: '65'),
    ForumUserProfileMetric(label: '积分', value: '7 点'),
    ForumUserProfileMetric(label: '对象', value: '175'),
  ],
  details: <ForumUserProfileDetail>[
    ForumUserProfileDetail(label: 'UID', value: '597454'),
    ForumUserProfileDetail(label: '用户组', value: '百合幼苗'),
  ],
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
  Future<ApiResult<SessionInfo>> refreshSession() async => ApiSuccess(
    SessionInfo(
      uid: '597454',
      username: '2834758851',
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

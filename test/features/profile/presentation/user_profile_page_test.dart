import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/auth/data/repositories/auth_repository.dart';
import 'package:y300/features/profile/data/models/profile_blog_models.dart';
import 'package:y300/features/profile/data/models/user_profile_models.dart';
import 'package:y300/features/profile/data/models/my_message_models.dart';
import 'package:y300/features/profile/data/repositories/my_message_repository.dart';
import 'package:y300/features/profile/data/repositories/profile_blog_repository.dart';
import 'package:y300/features/profile/data/repositories/user_profile_repository.dart';
import 'package:y300/features/profile/presentation/user_profile_page.dart';

void main() {
  testWidgets('UserProfilePage renders mobile profile data', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileRepositoryProvider.overrideWithValue(
            _FakeUserProfileRepository(_profile),
          ),
          imageRequestHeaderBuilderProvider.overrideWithValue(
            const _StaticImageHeaderBuilder(),
          ),
        ],
        child: const MaterialApp(home: UserProfilePage(uid: '509957')),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('alice的资料'), findsWidgets);
    expect(find.text('alice'), findsOneWidget);
    expect(find.byKey(const Key('user-profile-metrics')), findsOneWidget);
    expect(find.text('5263'), findsOneWidget);
    expect(find.text('Ta的主题'), findsOneWidget);
    expect(find.text('发短消息'), findsOneWidget);
    expect(find.byKey(const Key('user-profile-signature')), findsOneWidget);
    expect(_richTextContaining('Make a deal'), findsOneWidget);
    expect(find.byKey(const Key('user-profile-details')), findsOneWidget);
    expect(find.text('用户组'), findsOneWidget);
    expect(find.text('百合達人'), findsOneWidget);
  });

  testWidgets('MyProfilePage renders my actions and opens message center', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            _FakeAuthRepository(isLoggedIn: true),
          ),
          userProfileRepositoryProvider.overrideWithValue(
            _FakeUserProfileRepository(_myProfile),
          ),
          myMessageRepositoryProvider.overrideWithValue(
            const _FakeMyMessageRepository(),
          ),
          profileBlogRepositoryProvider.overrideWithValue(
            const _FakeProfileBlogRepository(),
          ),
          imageRequestHeaderBuilderProvider.overrideWithValue(
            const _StaticImageHeaderBuilder(),
          ),
        ],
        child: const MaterialApp(home: MyProfilePage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('user-profile-page-list')), findsOneWidget);
    expect(find.text('我的资料'), findsWidgets);
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('消息提醒'), findsOneWidget);
    expect(find.text('每日签到'), findsOneWidget);

    await tester.tap(find.text('我的日志'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-blog-list')), findsOneWidget);
    expect(find.text('还没有相关的日志'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('消息提醒'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('my-message-center-tabs')), findsOneWidget);
    expect(find.text('提醒 1'), findsOneWidget);
    expect(find.text('消息 1'), findsOneWidget);
  });
}

const _profile = UserProfileData(
  uid: '509957',
  username: 'alice',
  title: 'alice的资料',
  avatarUrl: null,
  coverUrl: null,
  signatureHtml: '<p>Make a deal with god</p>',
  threadUrl: 'https://bbs.yamibo.com/home.php?mod=space&uid=509957&do=thread',
  blogUrl: 'https://bbs.yamibo.com/home.php?mod=space&uid=509957&do=blog',
  messageUrl: 'https://bbs.yamibo.com/home.php?mod=space&do=pm&touid=509957',
  friendUrl: 'https://bbs.yamibo.com/home.php?mod=spacecp&ac=friend&uid=509957',
  credits: [
    UserProfileMetric(label: '总积分', value: '5263'),
    UserProfileMetric(label: '积分', value: '4300 点'),
    UserProfileMetric(label: '对象', value: '2888'),
  ],
  details: [
    UserProfileDetailItem(label: 'UID', value: '509957'),
    UserProfileDetailItem(label: '用户组', value: '百合達人'),
  ],
);

const _myProfile = UserProfileData(
  uid: '597454',
  username: '2834758851',
  title: '我的资料',
  avatarUrl: null,
  coverUrl: null,
  messageUrl: 'https://bbs.yamibo.com/home.php?mod=space&do=pm&mobile=2',
  credits: [
    UserProfileMetric(label: '总积分', value: '65'),
    UserProfileMetric(label: '积分', value: '7 点'),
    UserProfileMetric(label: '对象', value: '175'),
  ],
  actions: [
    UserProfileAction(
      label: '我的主题',
      url: 'https://bbs.yamibo.com/home.php?mod=space&do=thread',
    ),
    UserProfileAction(
      label: '我的收藏',
      url: 'https://bbs.yamibo.com/home.php?mod=space&do=favorite',
    ),
    UserProfileAction(
      label: '我的日志',
      url: 'https://bbs.yamibo.com/home.php?mod=space&do=blog&view=me',
    ),
    UserProfileAction(
      label: '消息提醒',
      url: 'https://bbs.yamibo.com/home.php?mod=space&do=pm',
    ),
    UserProfileAction(
      label: '每日签到',
      url: 'https://bbs.yamibo.com/plugin.php?id=zqlj_sign',
    ),
  ],
  details: [
    UserProfileDetailItem(label: 'UID', value: '597454'),
    UserProfileDetailItem(label: '用户组', value: '百合幼苗'),
  ],
);

class _FakeUserProfileRepository implements UserProfileRepository {
  const _FakeUserProfileRepository(this.profile);

  final UserProfileData profile;

  @override
  Future<ApiResult<UserProfileData>> getUserProfile({
    required String uid,
  }) async {
    return ApiSuccess<UserProfileData>(profile);
  }

  @override
  Future<ApiResult<UserProfileData>> getMyProfile({required String uid}) async {
    return ApiSuccess<UserProfileData>(profile);
  }
}

class _FakeProfileBlogRepository implements ProfileBlogRepository {
  const _FakeProfileBlogRepository();

  @override
  Future<ApiResult<ProfileBlogListPageData>> getBlogList({
    ProfileBlogView view = ProfileBlogView.all,
    ProfileBlogOrder order = ProfileBlogOrder.latest,
    int page = 1,
  }) async {
    return ApiSuccess<ProfileBlogListPageData>(
      ProfileBlogListPageData(
        title: '日志',
        activeView: view,
        activeOrder: order,
        viewTabs: [
          for (final item in ProfileBlogView.values)
            ProfileBlogNavigationTab(
              label: item.label,
              url: 'https://bbs.yamibo.com/home.php?view=${item.queryValue}',
              isActive: item == view,
            ),
        ],
        orderTabs: const <ProfileBlogNavigationTab>[],
        items: const <ProfileBlogListItem>[],
        emptyMessage: '还没有相关的日志',
      ),
    );
  }

  @override
  Future<ApiResult<ProfileBlogDetailData>> getBlogDetail({
    required String url,
  }) async {
    return const ApiFailure<ProfileBlogDetailData>(
      ApiError(type: ApiErrorType.business, message: 'not used'),
    );
  }
}

class _FakeMyMessageRepository implements MyMessageRepository {
  const _FakeMyMessageRepository();

  @override
  Future<ApiResult<MyMessageCenterData>> getMessageCenter() async {
    return const ApiSuccess<MyMessageCenterData>(
      MyMessageCenterData(
        notifications: MyNotificationPage(
          count: 1,
          page: 1,
          perPage: 30,
          items: [
            MyNotificationItem(
              id: 'n1',
              type: 'post',
              isNew: false,
              authorId: '8',
              author: '筱林透',
              noteHtml: '<a href="forum.php?mod=viewthread&tid=1">回复了您</a>',
              dateline: '2026-06-21 12:00',
            ),
          ],
        ),
        privateMessages: MyPrivateMessagePage(
          count: 1,
          page: 1,
          perPage: 15,
          items: [
            MyPrivateMessageItem(
              plid: 'p1',
              pmid: 'p1',
              isNew: false,
              subject: '嗨',
              fromUid: '597454',
              fromName: '2834758851',
              toUid: '8',
              toName: '筱林透',
              message: '好的',
              dateline: '2026-5-11 19:50',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Future<ApiResult<MyNotificationPage>> getNotifications() async {
    return ApiSuccess((await getMessageCenter()).dataOrNull!.notifications);
  }

  @override
  Future<ApiResult<MyPrivateMessagePage>> getPrivateMessages() async {
    return ApiSuccess((await getMessageCenter()).dataOrNull!.privateMessages);
  }
}

class _FakeAuthRepository implements AuthRepository {
  const _FakeAuthRepository({required this.isLoggedIn});

  final bool isLoggedIn;

  @override
  Future<ApiResult<SessionInfo>> login({
    required String username,
    required String password,
    String questionId = '0',
    String answer = '',
  }) async {
    return ApiSuccess(_session);
  }

  @override
  Future<void> logout() async {}

  @override
  Future<ApiResult<SessionInfo>> refreshSession() async {
    return ApiSuccess(
      isLoggedIn
          ? _session
          : SessionInfo(
              uid: '0',
              username: '',
              formhash: '',
              isLoggedIn: false,
            ),
    );
  }

  @override
  Future<ApiResult<bool>> verifyAuthByForumIndex() async {
    return ApiSuccess(isLoggedIn);
  }

  SessionInfo get _session {
    return SessionInfo(
      uid: '597454',
      username: '2834758851',
      formhash: 'fh',
      isLoggedIn: true,
    );
  }
}

class _StaticImageHeaderBuilder implements ImageRequestHeaderBuilder {
  const _StaticImageHeaderBuilder();

  @override
  Future<Map<String, String>> buildHeaders(String imageUrl) async {
    return const <String, String>{};
  }
}

Finder _richTextContaining(String text) {
  return find.byWidgetPredicate((widget) {
    if (widget is! RichText) {
      return false;
    }
    return widget.text.toPlainText().contains(text);
  });
}

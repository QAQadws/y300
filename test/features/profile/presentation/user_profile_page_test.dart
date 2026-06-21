import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/profile/data/models/user_profile_models.dart';
import 'package:y300/features/profile/data/user_profile_repository.dart';
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

class _FakeUserProfileRepository implements UserProfileRepository {
  const _FakeUserProfileRepository(this.profile);

  final UserProfileData profile;

  @override
  Future<ApiResult<UserProfileData>> getUserProfile({
    required String uid,
  }) async {
    return ApiSuccess<UserProfileData>(profile);
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

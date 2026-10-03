import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/navigation/friend_routes.dart';
import 'package:y300/app/navigation/message_routes.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/profile/data/providers/friend_read_providers.dart';
import 'package:y300/features/profile/presentation/profile_session_owner.dart';

import '../../features/profile/test_support/friend_read_fixture.dart';
import '../../test_support/localized_test_app.dart';

void main() {
  testWidgets('friend source links use the existing URL opener', (
    tester,
  ) async {
    const profileUrl =
        'https://bbs.yamibo.com/home.php?mod=space&uid=202&do=profile&mobile=2&from=friend#profile';
    final repository = FriendFeedFixture(autoComplete: true)
      ..items = [friendFeedItem('202', profileUrl: profileUrl)];
    final links = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          verifiedProfileOwnerProvider.overrideWithValue((
            uid: '101',
            revision: 0,
          )),
          friendFeedRepositoryProvider.overrideWithValue(repository),
          friendRemovalCommandProvider.overrideWithValue(
            FriendRemovalFixture(),
          ),
          forumImageRefererProvider.overrideWithValue('https://example.test/'),
          messageLinkOpenerProvider.overrideWithValue((context, url) {
            expect(context.mounted, isTrue);
            links.add(url);
          }),
        ],
        child: const LocalizedTestApp(home: MyFriendsDestination()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('my-friends-user-202')));
    await tester.pumpAndSettle();

    expect(links, [profileUrl]);
    expect(repository.requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}

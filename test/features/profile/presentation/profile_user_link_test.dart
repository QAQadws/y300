import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/profile/data/providers/profile_read_providers.dart';
import 'package:y300/features/profile/presentation/profile_blog_page.dart';
import 'package:y300/features/profile/presentation/profile_user_link.dart';
import 'package:y300/features/profile/presentation/user_profile_page.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

import '../../../test_support/localized_test_app.dart';
import '../test_support/blog_directory_fixture.dart';
import '../test_support/profile_repository_fixture.dart';

void main() {
  testWidgets(
    'author profile opens that author blog without changing the current account',
    (tester) async {
      final profiles = ProfileRepositoryFixture();
      final blogs = BlogDirectoryFixture();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            blogAccountIdProvider.overrideWithValue('202'),
            forumUserProfileRepositoryProvider.overrideWithValue(profiles),
            userBlogDirectoryRepositoryProvider.overrideWithValue(blogs),
            forumImageRefererProvider.overrideWithValue(
              'https://example.test/',
            ),
          ],
          child: const LocalizedTestApp(
            home: Scaffold(
              body: ProfileUserLink(userId: '101', child: Text('author link')),
            ),
          ),
        ),
      );
      expect(profiles.queries, isEmpty);
      expect(blogs.queries, isEmpty);
      final size = tester.getSize(find.byType(ProfileUserLink));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
      await tester.tap(find.text('author link'));
      await tester.pumpAndSettle();
      expect(profiles.queries.single.userId, '101');
      expect(blogs.queries, isEmpty);
      await tester.tap(find.byKey(const Key('user-profile-blogs')));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileBlogPage), findsOneWidget);
      expect(blogs.queries.single.scope, UserBlogFeedScope.self);
      expect(blogs.queries.single.ownerUserId, '101');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(UserProfilePage), findsOneWidget);
      expect(profiles.queries, hasLength(1));
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('author link'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final id in [null, '', '0', '-1', '01', 'display name']) {
    testWidgets(
      'invalid or anonymous identity $id never becomes a profile link',
      (tester) async {
        await tester.pumpWidget(
          LocalizedTestApp(
            home: Scaffold(
              body: ProfileUserLink(userId: id, child: const Text('12345')),
            ),
          ),
        );
        expect(find.byType(InkWell), findsNothing);
        await tester.tap(find.text('12345'));
        await tester.pumpAndSettle();
        expect(find.byType(UserProfilePage), findsNothing);
      },
    );
  }
}

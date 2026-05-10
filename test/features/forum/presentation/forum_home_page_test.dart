import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/forum/data/forum_home_repository.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';
import 'package:y300/features/forum/presentation/forum_home_page.dart';

void main() {
  group('ForumHomePage', () {
    testWidgets('shows loading skeleton before data returns', (tester) async {
      final completer = Completer<ApiResult<ForumHomePayload>>();
      final repository = _FakeForumHomeRepository(() => completer.future);

      await tester.pumpWidget(_buildTestApp(repository));

      expect(find.byKey(const Key('forum-home-skeleton')), findsOneWidget);

      completer.complete(ApiSuccess(_loggedOutPayload()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('forum-home-list')), findsOneWidget);
      expect(find.text('综合区'), findsOneWidget);
      expect(find.text('公告区'), findsOneWidget);
    });

    testWidgets('renders grouped forum data after successful load', (tester) async {
      final repository = _FakeForumHomeRepository(() async => ApiSuccess(_loggedOutPayload()));

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('forum-home-list')), findsOneWidget);
      expect(find.text('共1 个分组，1 个版块'), findsOneWidget);
      expect(find.text('综合区'), findsOneWidget);
      expect(find.text('公告区'), findsOneWidget);
      expect(find.byKey(const Key('forum-card-2')), findsOneWidget);
    });

    testWidgets('renders favorite forum section when logged in payload has favorites', (tester) async {
      final repository = _FakeForumHomeRepository(() async => ApiSuccess(_loggedInPayloadWithFavorites()));

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pumpAndSettle();

      expect(find.text('共2 个分组，1 个版块'), findsOneWidget);
      expect(find.text('我收藏的版块'), findsOneWidget);
      expect(find.byKey(const Key('forum-favorite-card-2')), findsOneWidget);
      expect(find.byKey(const Key('forum-favorite-card-55')), findsOneWidget);
      expect(find.text('综合区'), findsOneWidget);
    });
  });
}

Widget _buildTestApp(ForumHomeRepository repository) {
  return ProviderScope(
    overrides: [forumHomeRepositoryProvider.overrideWithValue(repository)],
    child: const MaterialApp(home: ForumHomePage()),
  );
}

ForumIndexData _sampleForumIndexData() {
  return ForumIndexData(
    categories: [
      ForumCategory(fid: '1', name: '综合区', forums: ['2']),
    ],
    forums: [
      ForumItem(
        fid: '2',
        name: '公告区',
        threads: 12,
        posts: 34,
        todayPosts: 2,
        description: '站点公告与维护信息',
        icon: '',
        subForums: const [],
      ),
    ],
  );
}

ForumHomePayload _loggedOutPayload() {
  return ForumHomePayload(
    forumIndex: _sampleForumIndexData(),
    isLoggedIn: false,
    favoriteForums: const [],
  );
}

ForumHomePayload _loggedInPayloadWithFavorites() {
  return ForumHomePayload(
    forumIndex: _sampleForumIndexData(),
    isLoggedIn: true,
    favoriteForums: [
      FavoriteForum(
        favid: '1',
        fid: '2',
        title: '百合会综合讨论区',
        description: '常逛版块',
        threads: 12,
        posts: 34,
        todayPosts: 1,
      ),
      FavoriteForum(
        favid: '2',
        fid: '55',
        title: '漫画交流区',
        description: '',
        threads: 56,
        posts: 78,
        todayPosts: 2,
      ),
    ],
  );
}

class _FakeForumHomeRepository implements ForumHomeRepository {
  _FakeForumHomeRepository(this._loader);

  final Future<ApiResult<ForumHomePayload>> Function() _loader;

  @override
  Future<ApiResult<ForumHomePayload>> getForumHomePayload() {
    return _loader();
  }
}

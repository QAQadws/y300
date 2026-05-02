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

    testWidgets('shows favorite section first when logged in', (tester) async {
      final repository = _FakeForumHomeRepository(() async => ApiSuccess(_loggedInPayloadWithFavorites()));

      await tester.pumpWidget(_buildTestApp(repository));
      await tester.pumpAndSettle();

      expect(find.text('我收藏的版块'), findsOneWidget);
      expect(find.byKey(const Key('forum-card-30')), findsOneWidget);
      expect(find.byKey(const Key('forum-card-55')), findsOneWidget);

      final favoriteTop = tester.getTopLeft(find.text('我收藏的版块')).dy;
      final regularTop = tester.getTopLeft(find.text('综合区')).dy;
      expect(favoriteTop, lessThan(regularTop));
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
        favid: '1863090',
        fid: '30',
        title: '中文百合漫画区',
        description: '',
        threads: 51916,
        posts: 1737117,
        todayPosts: 193,
      ),
      FavoriteForum(
        favid: '1792542',
        fid: '55',
        title: '轻小说译文区',
        description: '',
        threads: 1279,
        posts: 145828,
        todayPosts: 68,
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

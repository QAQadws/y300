import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/forum/data/forum_home_repository.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';
import 'package:y300/features/forum/presentation/forum_home_page.dart';
import 'package:y300/features/search/data/discuz_search_service.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';

void main() {
  testWidgets('ForumHomePage opens ForumSearchPage from app bar action', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumHomeRepositoryProvider.overrideWithValue(_FakeForumHomeRepository()),
          discuzSearchServiceProvider.overrideWithValue(_FakeDiscuzSearchService()),
        ],
        child: const MaterialApp(home: ForumHomePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('forum-home-search-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('forum-home-search-button')));
    await tester.pumpAndSettle();

    expect(find.text('搜索'), findsOneWidget);
    expect(find.byKey(const Key('forum-search-input')), findsOneWidget);
  });
}

class _FakeForumHomeRepository implements ForumHomeRepository {
  @override
  Future<ApiResult<ForumHomePayload>> getForumHomePayload() async {
    return ApiSuccess(
      ForumHomePayload(
        forumIndex: ForumIndexData(
          categories: [
            ForumCategory(fid: '1', name: '综合区', forums: ['2']),
          ],
          forums: [
            ForumItem(
              fid: '2',
              name: '公告区',
              threads: 1,
              posts: 1,
              todayPosts: 0,
              description: '',
              icon: '',
              subForums: const [],
            ),
          ],
        ),
        isLoggedIn: false,
        favoriteForums: const [],
      ),
    );
  }
}

class _FakeDiscuzSearchService implements ForumSearchService {
  @override
  Future<DiscuzSearchResponse> searchForum({
    required String keyword,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
    bool enforceRateLimit = true,
  }) async {
    return const DiscuzSearchResponse(
      items: <DiscuzSearchResultItem>[],
      rateLimited: false,
    );
  }

  @override
  Future<DiscuzSearchResponse> fetchNextPage({
    required String nextPageUrl,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
  }) async {
    return const DiscuzSearchResponse(
      items: <DiscuzSearchResultItem>[],
      rateLimited: false,
    );
  }
}

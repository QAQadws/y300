import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/auth/data/repositories/auth_repository.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/comic/data/providers/comic_search_refresh_queue_providers.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/forum/data/repositories/forum_home_repository.dart';
import 'package:y300/features/forum/data/models/forum_index_models.dart';
import 'package:y300/features/forum/presentation/forum_home_page.dart';
import 'package:y300/features/search/data/services/discuz_search_service.dart';
import 'package:y300/features/search/data/services/forum_search_scheduler.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/search/presentation/forum_search_page.dart';

void main() {
  testWidgets('ForumSearchPage builds dark theme chrome', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: ProviderScope(
          overrides: [
            discuzSearchServiceProvider.overrideWithValue(
              _FakeDiscuzSearchService(),
            ),
            comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
              ValueNotifier<ComicSearchRefreshQueueSnapshot>(
                ComicSearchRefreshQueueSnapshot.empty,
              ),
            ),
          ],
          child: const ForumSearchPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byKey(const Key('forum-search-input')), findsOneWidget);
    expect(find.byKey(const Key('forum-search-submit-button')), findsOneWidget);
  });

  testWidgets('ForumHomePage opens ForumSearchPage from app bar action', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forumHomeRepositoryProvider.overrideWithValue(
            _FakeForumHomeRepository(),
          ),
          discuzSearchServiceProvider.overrideWithValue(
            _FakeDiscuzSearchService(),
          ),
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
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

  testWidgets(
    'ForumSearchPage blocks search while comic search queue is active',
    (tester) async {
      final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
        ComicSearchRefreshQueueSnapshot(
          entries: <ComicSearchRefreshQueueEntry>[
            _queueEntry(id: 1, title: '排队漫画'),
          ],
          cadence: const Duration(milliseconds: 10500),
        ),
      );
      addTearDown(queueSnapshot.dispose);
      final searchService = _FakeDiscuzSearchService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discuzSearchServiceProvider.overrideWithValue(searchService),
            comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
              queueSnapshot,
            ),
          ],
          child: const MaterialApp(home: ForumSearchPage()),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('forum-search-input')),
        '测试关键词',
      );
      await tester.tap(find.byKey(const Key('forum-search-submit-button')));
      await tester.pump();

      expect(searchService.searchCallCount, 0);
      expect(find.text('《排队漫画》正在等待漫画搜索 预计耗时10.5s'), findsOneWidget);
      expect(find.text('测试关键词'), findsOneWidget);
    },
  );

  testWidgets(
    'ForumSearchPage searches normally when comic search queue is empty',
    (tester) async {
      final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
        ComicSearchRefreshQueueSnapshot.empty,
      );
      addTearDown(queueSnapshot.dispose);
      final searchService = _FakeDiscuzSearchService(
        response: const DiscuzSearchResponse(
          items: <DiscuzSearchResultItem>[
            DiscuzSearchResultItem(
              tid: '301',
              title: '搜索结果',
              url: 'thread-301-1-1.html',
              fid: '30',
            ),
          ],
          rateLimited: false,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discuzSearchServiceProvider.overrideWithValue(searchService),
            comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
              queueSnapshot,
            ),
          ],
          child: const MaterialApp(home: ForumSearchPage()),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('forum-search-input')),
        '测试关键词',
      );
      await tester.tap(find.byKey(const Key('forum-search-submit-button')));
      await tester.pump();
      await tester.pump();

      expect(searchService.searchCallCount, 1);
      expect(searchService.lastKeyword, '测试关键词');
      expect(find.text('搜索结果'), findsOneWidget);
    },
  );

  testWidgets(
    'ForumSearchPage shows scheduler wait when an interactive search is queued',
    (tester) async {
      final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
        ComicSearchRefreshQueueSnapshot.empty,
      );
      addTearDown(queueSnapshot.dispose);
      final searchService = _QueuedForumSearchService();
      addTearDown(searchService.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            discuzSearchServiceProvider.overrideWithValue(searchService),
            comicSearchRefreshQueueSnapshotProvider.overrideWithValue(
              queueSnapshot,
            ),
          ],
          child: const MaterialApp(home: ForumSearchPage()),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('forum-search-input')),
        '新的搜索',
      );
      await tester.tap(find.byKey(const Key('forum-search-submit-button')));
      await tester.pump();

      expect(searchService.searchCallCount, 0);
      expect(find.text('后台搜索 正在等待搜索 预计耗时10.5s'), findsOneWidget);
    },
  );
}

ComicSearchRefreshQueueEntry _queueEntry({
  required int id,
  required String title,
}) {
  return ComicSearchRefreshQueueEntry(
    id: id,
    comicId: 'comic:$id',
    title: title,
    request: ComicEpisodeRefreshRequest(
      comicId: 'comic:$id',
      sourceTid: '$id',
      displayTitle: title,
    ),
    origin: ComicSearchRefreshOrigin.favoriteSync,
    status: ComicSearchRefreshQueueStatus.pending,
    attempts: 0,
    availableAt: DateTime(2026, 5, 16),
    createdAt: DateTime(2026, 5, 16),
    updatedAt: DateTime(2026, 5, 16),
  );
}

class _FakeForumHomeRepository implements ForumHomeRepository {
  @override
  Future<ApiResult<ForumHomePayload>> getForumHomePayload({
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    DocumentRequestProfile? requestProfileOverride,
  }) async {
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

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<ApiResult<SessionInfo>> refreshSession() async {
    return ApiSuccess(
      SessionInfo(uid: '0', username: '', formhash: '', isLoggedIn: false),
    );
  }

  @override
  Future<ApiResult<SessionInfo>> login({
    required String username,
    required String password,
    String questionId = '0',
    String answer = '',
  }) async {
    throw StateError('login is not part of this test');
  }

  @override
  Future<void> logout() async {
    throw StateError('logout is not part of this test');
  }

  @override
  Future<ApiResult<bool>> verifyAuthByForumIndex() async {
    throw StateError('verifyAuthByForumIndex is not part of this test');
  }
}

class _FakeDiscuzSearchService implements ForumSearchService {
  _FakeDiscuzSearchService({
    this.response = const DiscuzSearchResponse(
      items: <DiscuzSearchResultItem>[],
      rateLimited: false,
    ),
  });

  final DiscuzSearchResponse response;
  int searchCallCount = 0;
  String? lastKeyword;

  @override
  Future<DiscuzSearchResponse> searchForum({
    required String keyword,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
    bool enforceRateLimit = true,
  }) async {
    searchCallCount++;
    lastKeyword = keyword;
    return response;
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

class _QueuedForumSearchService
    implements ForumSearchService, ForumSearchQueueStateReader {
  final ValueNotifier<ForumSearchSchedulerSnapshot> _snapshot =
      ValueNotifier<ForumSearchSchedulerSnapshot>(
        const ForumSearchSchedulerSnapshot(
          pendingCount: 1,
          running: true,
          headKeyword: '后台搜索',
          estimatedWait: Duration(milliseconds: 10500),
        ),
      );
  int searchCallCount = 0;

  @override
  ValueListenable<ForumSearchSchedulerSnapshot> get snapshot => _snapshot;

  void dispose() => _snapshot.dispose();

  @override
  Future<DiscuzSearchResponse> searchForum({
    required String keyword,
    DiscuzSearchContext context = const DiscuzSearchContext.forum(),
    bool enforceRateLimit = true,
  }) async {
    searchCallCount++;
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
